[[_TOC_]]

[[_TOSP_]]

## Prerequisites

- Internet connection
- `kind` binary
- `kubectl` binary
- `helm` binary

## Failover Configuration for Minio

This is the documentation of failover cluster configuration of minio using bitnami helm chart. We will use the `kind` cluster for the local test.

Minio does not have the HA structure like Mongodb. Minio does not have primary and secondary clusters. When we write something into minio server, it writes the data to the all nodes. When we read something from minio server, it reads the data from the all nodes. This is called **Quorum Requrements**. The quorum requirements are the minimum number of nodes that must be available to read or write data. The quorum requirements are calculated as follows:

- **Read quorum**: `N / 2 + 1`
- **Write quorum**: `W`

Where `N` is the total number of nodes in the cluster and `W` is the number of nodes that must acknowledge a write operation before it is considered successful.

### Local Test: Kind

- Delete `myk8s` cluster if it exists.

```sh
kind delete cluster --name myk8s
```

- Create a kind cluster with 1 control-plane and 6 worker nodes. Its name is `myk8s`.

```sh
cat <<EOF | kind create cluster --name myk8s --config=-
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
   labels:
     role: monitoring
     topology.kubernetes.io/region: primary
  - role: worker
   labels:
     role: infra
     topology.kubernetes.io/region: primary
  - role: worker
   labels:
     role: infra
     topology.kubernetes.io/region: failover
  - role: worker
   labels:
     role: apps
     topology.kubernetes.io/region: primary
  - role: worker
   labels:
     role: apps
     topology.kubernetes.io/region: primary
  - role: worker
   labels:
     role: apps
     topology.kubernetes.io/region: primary
  - role: worker
   labels:
     role: apps
     topology.kubernetes.io/region: failover
EOF
```

- Apply the labels and taints to the nodes.

```sh
# Actual Nodes Taints
kubectl taint nodes myk8s-worker2 product=apps:NoSchedule
kubectl taint nodes myk8s-worker3 product=monitoring:NoSchedule
# Failover Nodes: app/monitoring Taints
kubectl taint nodes myk8s-worker5 product=apps:NoSchedule
kubectl taint nodes myk8s-worker6 product=monitoring:NoSchedule
# Failover Nodes: failover Taints
# kubectl taint nodes myk8s-worker4 nodeMode=failover:NoSchedule
# kubectl taint nodes myk8s-worker5 nodeMode=failover:NoSchedule
# kubectl taint nodes myk8s-worker6 nodeMode=failover:NoSchedule
# ---
# Labels
# Actual Nodes Labels
kubectl label nodes myk8s-worker role=infra
kubectl label nodes myk8s-worker2 role=apps
kubectl label nodes myk8s-worker3 role=monitoring
kubectl label nodes myk8s-worker topology.kubernetes.io/region=primary
kubectl label nodes myk8s-worker2 topology.kubernetes.io/region=primary
kubectl label nodes myk8s-worker3 topology.kubernetes.io/region=primary
# Failover Nodes Labels: infra/apps/monitoringFailover
kubectl label nodes myk8s-worker4 role=infra
kubectl label nodes myk8s-worker5 role=apps
kubectl label nodes myk8s-worker6 role=monitoring
kubectl label nodes myk8s-worker4 topology.kubernetes.io/region=failover
kubectl label nodes myk8s-worker5 topology.kubernetes.io/region=failover
kubectl label nodes myk8s-worker6 topology.kubernetes.io/region=failover
```
- Check kube-proxy pods.

```sh
kubectl get pods -n kube-system -l k8s-app=kube-proxy
```

- If their statuses are CrashLoopBackOffrun following command (the kind's known "too many open files" issue.)

```sh
export DOCKER_CLI_HINTS=false
containerNames=$(docker ps --format '{{.Names}}' | grep "myk8s")
# Execute the command in the each containers
echo "Resolve the kind's known too many open files issue"
echo "$containerNames" | while read -r containerName; do
    echo "Container Name: ${containerName}"
    docker exec -t ${containerName} bash -c "echo 'fs.inotify.max_user_watches=1048576' >> /etc/sysctl.conf"
    docker exec -t ${containerName} bash -c "echo 'fs.inotify.max_user_instances=512' >> /etc/sysctl.conf"
    docker exec -t ${containerName} bash -c "sysctl -p /etc/sysctl.conf"
done
```

Restart the kube-proxy pods.

```sh
kubectl delete pod -n kube-system -l k8s-app=kube-proxy
```

- [Optional] Install the `ingress-nginx` controller.

```sh
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=180s
```

- [Optional] Create/Install certificate for the `ingress-nginx` controller.

```sh
openssl req -x509 -nodes -days 1000 -newkey rsa:2048 -keyout localhost.key -out localhost.crt -subj "/C=TR/ST=TR/L=IST/O=bulmust Clusters Company/CN=localhost"
kubectl create secret tls -n kube-system localhost-tls --cert=localhost.crt --key=localhost.key
rm -f localhost.key localhost.crt
```

- [Optional] Create metrices server.

```sh
#kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
#! This will give an error in kind v0.24.0. See `https://github.com/kubernetes-sigs/metrics-server/issues/1025#issuecomment-2363638136`
```

### Bitnami Minio Helm Chart

- Install the bitnami's minio using helm.

```sh
helm repo add bitnami https://charts.bitnami.com/bitnami
cat <<EOF | helm upgrade --install --version 14.1.7 -n minio --create-namespace --debug minio bitnami/minio -f -
# global:
#   imageRegistry: nexus-image.bordatech.com
#   imagePullSecrets:
#     - nexus
mode: distributed
auth:
  rootUser: hia
  rootPassword: BtttttttttYAYdL8djc8VYykt7
provisioning:
  enabled: true
  resources:
    requests:
      cpu: 20m
      memory: 30Mi
    limits:
      memory: 600Mi
  policies:
    - name: hia
      statements:
        - resources:
            - "arn:aws:s3:::hia/*"
          effect: "Allow"
          actions:
            - "s3:*"
  users:
    - username: hia3
      password: BtttttttttYAYdL8djc8VYykt3
      policies:
        - hia
  buckets:
    - name: hia
  cleanupAfterFinished:
    enabled: true
    seconds: 60
resources:
  requests:
    cpu: 20m
    memory: 400Mi
  limits:
    memory: 3Gi
ingress:
  enabled: false
  # ingressClassName: nginx
  # hostname: minio-quattro.borda.hamadairport.com.qa
  # annotations:
  #   nginx.org/client-max-body-size: 400m
  #   nginx.org/proxy-buffer-size: 8k
  #   nginx.org/proxy-buffering: "false"
  #   nginx.org/proxy-connect-timeout: 300s
  #   nginx.org/websocket-services: minio
  # tls: true
apiIngress:
  enabled: false
  # ingressClassName: nginx
  # hostname: minio-quattro.borda.hamadairport.com.qa
  # annotations:
  #   nginx.org/client-max-body-size: 400m
  #   nginx.org/proxy-buffer-size: 8k
  #   nginx.org/proxy-buffering: "false"
  #   nginx.org/proxy-connect-timeout: 300s
  #   nginx.org/websocket-services: minio
  # tls: true
persistence:
  enabled: true
  storageClass: standard #local-path
  size: 10Gi
metrics:
  serviceMonitor:
    enabled: false
    # paths:
    #   - /minio/v2/metrics/cluster
    #   - /minio/v2/metrics/node
    #   - /minio/v2/metrics/bucket
    #   - /minio/v2/metrics/resource

statefulset:
  replicaCount: 4 #Minimum 4
  zones: 1
  drivesPerNode: 1

affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
            - key: topology.kubernetes.io/region
              operator: In
              values:
                - primary
      - weight: 50
        preference:
          matchExpressions:
            - key: topology.kubernetes.io/region
              operator: In
              values:
                - failover
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
              - key: app
                operator: In
                values:
                  - mongodb
          topologyKey: topology.kubernetes.io/region
tolerations:
  - key: "product"
    operator: "Equal"
    value: "apps"
    effect: "NoSchedule"
EOF
```

- **CAUTION**: The pods have to be spread over 4 nodes for HA. 
  - You can not create less than 4 pod replica.
  - If you spread your pods for only 2 nodes (2 pods for primary, 2 pods for failover or 3 primary, 1 failover), the failover minio will not work properly at primary nodes failure. The error is `<ERROR> Unable to initialize new alias from the provided credentials. Resource requested is unwritable, please reduce your request rate`. This error is related to the `minio` itself. To overcome this error, I spread minio in also `role=apps` nodes. In this way, the failover minio will work properly after the primary nodes failure. This is called **Quorum Requrements**.

## Test

- Check the minio pods.

```sh
kubectl get pods -n minio
```

- Login one of the minio pods.

```sh
kubectl exec -it minio-0 -n minio -- bash
```

- Shell to the minio pod and add an a file to `hiaBucket` bucket.

```sh
# Set Alias
mc alias set hiaBucket http://minio.minio.svc.cluster.local:9000 hia BtttttttttYAYdL8djc8VYykt7
# Create a file
echo "print('hello world')">/tmp/hello.py
# Copy the file to the bucket
mc cp /tmp/hello.py hiaBucket/hia
# List the files in the bucket
mc ls hiaBucket/hia
exit
```

- Check `hello.py` file in different pods, preferably in the failover pods.

```sh
# Check the pod in the failover region
kubectl get pods -n minio -o wide
# NAME      READY   STATUS    RESTARTS   AGE     IP           NODE            NOMINATED NODE   READINESS GATES
# minio-0   1/1     Running   0          4m45s   10.244.5.3   myk8s-worker    <none>           <none>
# minio-1   1/1     Running   0          4m45s   10.244.4.3   myk8s-worker4   <none>           <none>
# minio-2   1/1     Running   0          4m45s   10.244.3.3   myk8s-worker2   <none>           <none>
# minio-3   1/1     Running   0          4m45s   10.244.2.4   myk8s-worker5   <none>           <none>
kubectl exec -it minio-3 -n minio -- bash
```

- Verify that `hello.py` file is in the failover bucket.

```sh
# Set Alias
mc alias set hiaBucket http://minio.minio.svc.cluster.local:9000 hia BtttttttttYAYdL8djc8VYykt7
# List the files in the bucket
mc ls hiaBucket/hia
exit
```

Alternatively, you can get information about the bucket.

```sh
mc admin info hiaBucket
```
- Exit the pod `exit`.
- Delete the primary nodes.

```sh
docker stop myk8s-worker
docker stop myk8s-worker2
```

- Check the nodes.

```sh
kubectl get nodes
```

- Wait for a while and shell the one of the failover pods. (Here, `minio-1` is in worker4 node.)

```sh
kubectl exec -it minio-1 -n minio -- bash
```
- Get the information minio cluster.

```sh
# Set Alias
mc alias set hiaBucket http://minio.minio.svc.cluster.local:9000 hia BtttttttttYAYdL8djc8VYykt7
mc admin info hiaBucket
```

The output should be like below.

```sh
●  minio-0.minio-headless.minio.svc.cluster.local:9000
   Uptime: offline
   Drives: 0/1 OK 

●  minio-1.minio-headless.minio.svc.cluster.local:9000
   Uptime: 7 minutes 
   Version: 2024-04-06T05:26:02Z
   Network: 2/4 OK 
   Drives: 1/1 OK 
   Pool: 1

●  minio-2.minio-headless.minio.svc.cluster.local:9000
   Uptime: offline
   Drives: 0/1 OK 

●  minio-3.minio-headless.minio.svc.cluster.local:9000
   Uptime: 7 minutes 
   Version: 2024-04-06T05:26:02Z
   Network: 2/4 OK 
   Drives: 1/1 OK 
   Pool: 1

Pools:
   1st, Erasure sets: 1, Drives per erasure set: 4

21 B Used, 1 Bucket, 1 Object, 1 Version
2 nodes offline, 2 drives online, 2 drives offline
```

As we can see, `minio-0` and `minio-2` are offline. The failover minios are working. You can check the created file can be accessible in failover minio pods.

```sh
mc alias set hiaBucket http://minio.minio.svc.cluster.local:9000 hia BtttttttttYAYdL8djc8VYykt7
# List the files in the bucket
mc ls hiaBucket/hia
exit
```

The output is like below.

```sh
Added `hiaBucket` successfully.
[2024-09-27 08:17:53 UTC]    21B STANDARD hello.py
```

### After Node Failure

The senerio is like below.

- Primary nodes are down.
- Failover nodes are up and running.
- Quattro will continue to use (read/write) the minios in failover nodes.
- After the primary nodes are up, Do the new files be written to the primary nodes?

We will continue the from the previous step.

- Examine the nodes and pods

```sh
kubectl get nodes
# NAME                  STATUS     ROLES           AGE   VERSION
# myk8s-control-plane   Ready      control-plane   17m   v1.31.0
# myk8s-worker          NotReady   <none>          17m   v1.31.0
# myk8s-worker2         NotReady   <none>          17m   v1.31.0
# myk8s-worker3         Ready      <none>          17m   v1.31.0
# myk8s-worker4         Ready      <none>          17m   v1.31.0
# myk8s-worker5         Ready      <none>          17m   v1.31.0
# myk8s-worker6         Ready      <none>          17m   v1.31.0
kubectl get pods -n minio -owide
# NAME      READY   STATUS        RESTARTS   AGE   IP           NODE            NOMINATED NODE   READINESS GATES
# minio-0   1/1     Terminating   0          14m   10.244.5.3   myk8s-worker    <none>           <none>
# minio-1   1/1     Running       0          14m   10.244.4.3   myk8s-worker4   <none>           <none>
# minio-2   1/1     Terminating   0          14m   10.244.3.3   myk8s-worker2   <none>           <none>
# minio-3   1/1     Running       0          14m   10.244.2.4   myk8s-worker5   <none>           <none>
```

- Shell the `minio-1` pod.

```sh
kubectl exec -it minio-1 -n minio -- bash
```

- Login and create a second file.

```sh
# Set Alias
mc alias set hiaBucket http://minio.minio.svc.cluster.local:9000 hia BtttttttttYAYdL8djc8VYykt7
# Create a file
echo "print('hello world2')">/tmp/hello2.py
# Copy the file to the bucket
mc cp /tmp/hello2.py hiaBucket/hia
# List the files in the bucket
mc ls hiaBucket/hia
exit
```

### References

- https://github.com/bitnami/charts/pull/25301
- https://min.io/docs/minio/linux/operations/concepts/erasure-coding.html
- https://github.com/minio/minio/discussions/19304