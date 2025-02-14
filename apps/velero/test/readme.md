[[_TOC_]]

[[_TOSP_]]

## Prerequisites

- Internet connection
- `kind` binary
- `kubectl` binary
- `helm` binary

## Velero Test

- Delete velero-test cluster.

```sh
kind delete cluster --name velero-test
```

- Create kind cluster:

```sh
cat << EOF | kind create cluster --name velero-test --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
    - |
      kind: InitConfiguration
      nodeRegistration:
        kubeletExtraArgs:
          node-labels: "ingress-ready=true"
    extraPortMappings:
    - containerPort: 80
      hostPort: 80
      protocol: TCP
    - containerPort: 443
      hostPort: 443
      protocol: TCP
  - role: worker
EOF
```

- Check kube-proxy pods.

```sh
kubectl get pods -n kube-system -l k8s-app=kube-proxy
```

- If their statuses are CrashLoopBackOffrun following command (the kind's known "too many open files" issue.)

```sh
export DOCKER_CLI_HINTS=false
containerNames=$(docker ps --format '{{.Names}}' | grep "velero-test")
# Execute the command in the each containers
echo "Resolve the kind's known too many open files issue"
echo "$containerNames" | while read -r containerName; do
    echo "Container Name: ${containerName}"
    docker exec -t ${containerName} bash -c "echo 'fs.inotify.max_user_watches=1048576' >> /etc/sysctl.conf"
    docker exec -t ${containerName} bash -c "echo 'fs.inotify.max_user_instances=512' >> /etc/sysctl.conf"
    docker exec -t ${containerName} bash -c "sysctl -p /etc/sysctl.conf"
done
```

- Install the `ingress-nginx` controller.

```sh
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=180s
```

- Create minio standalone deployment using helm.

```sh
helm repo add minio https://charts.min.io/
helm repo update
cat << EOF | helm install minio minio/minio -n minio --create-namespace --version 5.2.0 --debug --values=-
mode: standalone
rootUser: bulmustAdmin
rootPassword: bulmustbulmust
persistence:
  enabled: true
  #storageClass: standard
  size: 10Gi
ingress:
  enabled: true
  ingressClassName: nginx
  hosts:
    - minio.localhost
consoleIngress:
  enabled: true
  ingressClassName: nginx
  hosts:
    - minio-console.localhost
  tls:
    - secretName: velero-minio-console-tls
      hosts:
        - minio-console.localhost
users:
  - accessKey: bulmust
    secretKey: bulmustbulmust
    policy: readwrite
buckets:
  - name: velero
    policy: none
    purge: false
    versioning: true
serviceAccount:
  name: minio-sa-velero
resources:
  requests:
    memory: 1Gi
EOF
```

- [Optional] You can manually send a file to the minio bucket.

```sh
# Set Alias
# mc alias set velero http://minio.minio.svc.cluster.local:9000 bulmust bulmustbulmust
# # Create a file
# echo "print('hello world')">/tmp/hello.py
# # Copy the file to the bucket
# mc cp /tmp/hello.py velero/velero
# # List the files in the bucket
# mc ls velero/velero
```

- Create access and secret keys.
  - Navigate to minio console: https://minio-console.localhost (username: bulmust, password: bulmustbulmust)
  - Click the `Access Keys` tab on left
  - Click the `Create New Access Key` button
  - Click the `Create` button
  - Copy the `Access Key` and `Secret Key` values. For Example: Access Key: jc0nl7sfZgd11uUCz0sB , Secret Key: XoHaiNnJSMbkeGcExXucMmVwlok9JqztVQSJ0gBs
  - You will use these values in the `credentials.secretContents.cloud` section of the Velero Helm installation `values.yaml`.

- Add Velero Helm repository: https://github.com/vmware-tanzu/helm-charts/tree/main/charts/velero

- Create a app that uses the persistent volume.

```sh
kubectl apply -f - << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-persistent-storage
          mountPath: /usr/share/nginx/html
      volumes:
      - name: nginx-persistent-storage
        persistentVolumeClaim:
          claimName: nginx-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nginx-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
```

```sh
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update
```

- Install Velero using Helm.

```sh
helm uninstall velero -n velero;cat << EOF | helm upgrade --install velero vmware-tanzu/velero -n velero --create-namespace --version 7.2.1 --debug --values=-
initContainers:
- name: velero-plugin-for-aws
  image: velero/velero-plugin-for-aws:latest
  imagePullPolicy: IfNotPresent
  volumeMounts:
    - mountPath: /target
      name: plugins
# - name: velero-plugin-for-csi
#   image: velero/velero-plugin-for-csi:latest
#   imagePullPolicy: IfNotPresent
#   volumeMounts:
#     - mountPath: /target
#       name: plugins
configuration:
  features: EnableCSI
  backupStorageLocation:
  - name: velero-test
    provider: aws
    bucket: velero
    default: true
    config:
      region: default
      s3ForcePathStyle: true
      s3Url: http://minio.minio.svc.cluster.local:9000
      # insecureSkipTLSVerify: true
  volumeSnapshotLocation:
  - name: velero-test
    provider: aws
credentials:
  secretContents: 
    cloud: |
      [default]
      aws_access_key_id=jc0nl7sfZgd11uUCz0sB
      aws_secret_access_key=XoHaiNnJSMbkeGcExXucMmVwlok9JqztVQSJ0gBs
schedules:
  evreyminutesbackup:
    disabled: false
    schedule: "* * * * *"
    template:
      ttl: "240h"
      storageLocation: velero-test
      includedNamespaces:
        - default
      # includedNamespaces:
      #   - kube-system
resources:
  requests:
    cpu: 500m
    memory: 128Mi
  limits:
    memory: 512Mi
EOF
```

- Check

## Refs

- https://hub.docker.com/r/velero/velero-plugin-for-aws/tags
- https://medium.webdoxclm.com/install-velero-with-helm-in-gcp-15b7a0186ae
- https://wekeo.docs.cloudferro.com/en/latest/kubernetes/Backup-of-Kubernetes-Cluster-using-Velero.html
- https://github.com/vmware-tanzu/velero/discussions/7850
- https://velero.io/docs/main/file-system-backup/
- https://github.com/vmware-tanzu/velero-plugin-for-csi