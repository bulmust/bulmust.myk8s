#!/bin/sh

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# This scripts path
# Script may be run from any directory
SCRIPT_PATH=$(cd $(dirname "$0") && pwd)
echo ">>>${GREEN}Current Directory${NC}: ${SCRIPT_PATH}"

# Parse arguments
while [ "$#" -gt 0 ]; do
  case $1 in
    --nodes-cp=*) nodes_cp="${1#*=}"; shift ;;
    --nodes-cp) nodes_cp="$2"; shift 2 ;;
    --nodes-w=*) nodes_worker="${1#*=}"; shift ;;
    --nodes-w) nodes_worker="$2"; shift 2 ;;
    *) echo ">>>${RED}Unknown parameter passed: $1"; usage ;;
  esac
done

# Number of Control Plane Nodes and Worker nodes
# If no argument is passed, default values are nodes_cp = 1 and nodes_worker = 1
if [ -z "$nodes_cp" ]; then
    nodes_cp=1
fi
if [ -z "$nodes_worker" ]; then
    nodes_worker=1
fi

# Info
echo ">>>${GREEN}Number of Control Plane Nodes${NC}: ${nodes_cp}"
echo ">>>${GREEN}Number of Worker Nodes${NC}: ${nodes_worker}"

# Check Kind is Installed
echo ">>>${GREEN}Check Kind${NC}"
if [ -x "$(command -v kind)" ]; then
    echo ">>>${GREEN}Kind is Installed${NC}"
else
    echo ">>>${RED}Kind is Not Installed${NC}"
    exit 1
fi

# Check Kubectl is Installed
echo ">>>${GREEN}Check Kubectl${NC}"
if [ -x "$(command -v kubectl)" ]; then
    echo ">>>${GREEN}Kubectl is Installed${NC}"
else
    echo ">>>${RED}Kubectl is Not Installed${NC}"
    exit 1
fi

# Check Helm is Installed
echo ">>>${GREEN}Check Helm${NC}"
if [ -x "$(command -v helm)" ]; then
    echo ">>>${GREEN}Helm is Installed${NC}"
else
    echo ">>>${RED}Helm is Not Installed${NC}"
    exit 1
fi

# Cluster Name
clusterName="myk8s"

# Check if Cluster Exists
echo ">>>${GREEN}Check if ${clusterName} Cluster Exists${NC}"
if [ "$(kind get clusters | grep $clusterName)" ]; then
    echo ">>>${GREEN}Cluster Exists${NC}"
    echo ">>>${GREEN}Do you want to delete the cluster ${RED}${clusterName}${GREEN}?${NC}"
    echo ">>>${GREEN}y${NC}/${RED}n${NC}"
    read response
    if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
        
        echo ">>>${GREEN}Delete Cluster${NC}"
        kind delete cluster --name "$clusterName"
    else
        
        echo ">>>${GREEN}Cluster is not deleted${NC}"
        exit 1
    fi
else
    echo ">>>${GREEN}Cluster Does Not Exist${NC}"
fi

# Create Kind cluster with 2 worker nodes and ingress-ready label
echo ">>>${GREEN}Create Kind cluster with ${nodes_cp} control plane and ${nodes_worker} worker nodes and ingress-ready label${NC}"
kind create cluster --name "$clusterName" --config manifests/kind-${nodes_cp}CP${nodes_worker}W.yaml

# Resolve the kind's known too many open files issue
#* https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files
#* https://github.com/kubernetes-sigs/kind/issues/2586#issuecomment-1013614308
# Get docker container names started by $clusterName
containerNames=$(docker ps --format '{{.Names}}' | grep $clusterName)
# Execute the command in the each containers
echo ">>>${RED}Resolve the kind's known too many open files issue${NC}"
for containerName in $containerNames; do
    echo ">>>${GREEN}Container Name${NC}: ${containerName}"
    docker exec -it $containerName bash -c "echo 'fs.inotify.max_user_watches=1048576' >> /etc/sysctl.conf"
    docker exec -it $containerName bash -c "echo 'fs.inotify.max_user_instances=512' >> /etc/sysctl.conf"
    docker exec -it $containerName bash -c "sysctl -p /etc/sysctl.conf"
done

# Echo Current Context
echo ">>>${GREEN}Current Context${NC}"
# If current context is not kind-myk8s, switch to kind-myk8s
if [ "$(kubectl config current-context)" != "kind-myk8s" ]; then
    kubectl config use-context kind-myk8s
else
    kubectl config current-context
fi

# Deploy Metrics Server
echo ">>>${GREEN}Deploy Metrics Server${NC}"
kubectl apply -f manifests/metrics-server.yaml

# Deploy Ingress-Nginx
echo ">>>${GREEN}Deploy Ingress${NC}"
wget https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml -O manifests/nginx-deploy.yaml
kubectl apply -f manifests/nginx-deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=180s

# Do you want self-signed certificate?
echo ">>>${GREEN}Do you want self-signed certificate?${NC}"
echo ">>>${GREEN}y${NC}/${RED}n${NC}"
read response
if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
    # # Install Cert-Manager via Helm
    # #* https://michalwojcik.com.pl/2021/08/29/automatically-provision-tls-certificates-in-kubernetess-with-cert-manager/

    # CERT_MANAGER_VERSION=v1.15.1
    # echo ">>>${GREEN}Install Cert-Manager ${CERT_MANAGER_VERSION} via Helm${NC}"
    # helm install \
    #     cert-manager jetstack/cert-manager \
    #     --namespace cert-manager \
    #     --create-namespace \
    #     --version ${CERT_MANAGER_VERSION} \
    #     --set installCRDs=true
    
    # # Create Self-Signed Certificate
    # openssl req -x509 -nodes -days 1000 -newkey rsa:2048 -keyout localhost.key -out localhost.crt -subj "/C=TR/ST=TR/L=IST/O=bulmust Clusters Company/CN=localhost"
    # # Create Certificate and Key Secret in kube-system Namespace 
    # kubectl create secret tls -n kube-system localhost-tls --cert=localhost.crt --key=localhost.key
    # # Sleep for 15 seconds
    # sleep 15
    # # create Issuer and refer to use newly created key-pair
    # # cat <<EOF| k apply -f-
    # # apiVersion: cert-manager.io/v1
    # # kind: Issuer
    # # metadata:
    # #   name: ca-issuer
    # #   namespace: default
    # # spec:
    # #   ca:
    # #     secretName: ca-key-pair
    # # EOF
    
    # # hence we now have issuer, we can generate proper certificate for my domain ingress.local
    # # cat <<EOF| k apply -f-
    # # apiVersion: cert-manager.io/v1
    # # kind: Certificate
    # # metadata:
    # #   name: ingress-localhost
    # #   namespace: default
    # # spec:
    # #   secretName: ingress-local-tls
    # #   issuerRef:
    # #     name: ca-issuer
    # #     kind: Issuer
    # #   commonName: ingress.localhost
    # #   dnsNames:
    # #     - ingress.localhost
    # #     - www.ingress.localhost
    # # EOF

    # Create Self-Signed Certificate
    #* https://michalwojcik.com.pl/2021/08/08/ingress-tls-in-kubernetes-using-self-signed-certificates/
    echo ">>>${GREEN}Create 1000 Days valid Self-Signed certificate in certificates/ folder${NC}"
    # Check certificates folder
    if [ ! -d "certificates/" ]; then
        echo ">>>${GREEN}Create certificates folder${NC}"
        mkdir certificates/
        cd certificates/
        # Create Self-Signed Certificate
        openssl req -x509 -nodes -days 1000 -newkey rsa:2048 -keyout localhost.key -out localhost.crt -subj "/C=TR/ST=TR/L=IST/O=bulmust Clusters Company/CN=localhost"
        # Create Certificate and Key Secret in kube-system Namespace 
        kubectl create secret tls -n kube-system localhost-tls --cert=localhost.crt --key=localhost.key
        cd -
    else
        echo ">>>${GREEN}certificates Folder Exists${NC}"
        # Hold Old Certificates and Continue
        echo ">>>${GREEN}Hold old certificates and continue${NC}"
        cd certificates/
        # Create Certificate and Key Secret in kube-system Namespace 
        kubectl create secret tls -n kube-system localhost-tls --cert=localhost.crt --key=localhost.key
        cd -
    fi
    PORT=443
else
    echo ">>>${GREEN}No Self-Signed Certificate${NC}"
    PORT=80
fi

# Deploy Echo-Deployment
echo ">>>${GREEN}Create Test Namespace${NC}"
kubectl create ns test
echo ">>>${GREEN}Deploy Echo-Server${NC}"
# Deployment
kubectl apply -f manifests/echoserver-deployment-1-10.yaml
# Wait for Deployment to be Ready
kubectl wait --namespace test --for=condition=available deployment/echo-server --timeout=180s

# Initialize Echo Ingress
echo ">>>${GREEN}Initialize Echo Ingress${NC}"
# If check if self-signed certificate is used
if [ "$PORT" = "443" ]; then
    echo ">>>${GREEN}Initialize Echo Ingress with Self-Signed Certificate${NC}"
    kubectl apply -f manifests/echoserver-ingress-self-signed.yaml
    
    # Test Ingress (Skip Certificate Verification)
    echo ">>>${GREEN}Test Ingress${NC}: ${RED}curl -k https://echo.localhost${NC}"
else
    echo ">>>${GREEN}Initialize Echo Ingress without Self-Signed Certificate${NC}"
    kubectl apply -f manifests/echoserver-ingress.yaml
    
    # Test Ingress
    echo ">>>${GREEN}Test Ingress${NC}: ${RED}curl echo.localhost${NC}"
fi

# Echo Which Ingress to Use
echo ">>>---------------------------------"
echo ">>>${GREEN}All DNS should be:${RED} *.localhost${NC}"
echo ">>>---------------------------------"

Do you want to deploy argocd?
echo ">>>${GREEN}Do you want to deploy argocd?${NC}"
echo ">>>${GREEN}y${NC}/${RED}n${NC}"
read response
if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
    # Deploy ArgoCD
    echo ">>>${GREEN}Deploy ArgoCD using helm${NC}"

    # Check htpasswd is installed
    echo ">>>${GREEN}Check htpasswd${NC}"
    if [ -x "$(command -v htpasswd)" ]; then
        echo ">>>${GREEN}htpasswd is Installed${NC}"
    else
        # Install htpasswd
        echo ">>>${RED}htpasswd is Not Installed${NC}"
        echo ">>>${GREEN}Install htpasswd, using apt-get install apache2-utils${NC}"
        sudo apt-get install apache2-utils
    fi

    # Check yq is installed
    echo ">>>${GREEN}Check yq${NC}"
    if [ -x "$(command -v yq)" ]; then
        echo ">>>${GREEN}yq is Installed${NC}"
    else
        # Install yq
        echo ">>>${RED}yq is Not Installed${NC}"
        echo ">>>${GREEN}Install yq, using apt-get install yq${NC}"
        sudo apt-get install yq
    fi

    # Add ArgoCD Repo
    helm repo add argo https://argoproj.github.io/argo-helm
    
    # Update That Repo
    helm repo update argo

    # Helm Install
    ARGOCD_CHART_VERSION=$(cat ./argocd/helm/info.yaml|yq -r '.version')
    echo ">>>${GREEN}Helm Install ArgoCD, Chart Version: ${ARGOCD_CHART_VERSION}${NC}"
    helm upgrade --install --debug argocd argo/argo-cd --namespace=argocd --create-namespace --version=${ARGOCD_CHART_VERSION} -f ./argocd/helm/values.yaml

    # Wait for ArgoCD to be Ready
    echo ">>>${GREEN}Wait for ArgoCD to be Ready${NC}"
    kubectl wait --namespace argocd --for=condition=ready pod --selector=app.kubernetes.io/name=argocd-applicationset-controller --timeout=180s

    # Apply Application Sets
    echo ">>>${GREEN}Apply Application Sets${NC}"
    kubectl apply -n argocd -f argocd/raw-manifests/applicationset-helm.yaml

else
    echo ">>>${GREEN}ArgoCD is not deployed${NC}"
fi

# Do you want to tainted the worker nodes?
# echo ">>>${GREEN}Do you want to tainted the myk8s-worker2 node? https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/${NC}"
# echo ">>>${GREEN}y${NC}/${RED}n${NC}"
# read response
# if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
#     # Taint Worker Nodes
#     echo ">>>${GREEN}Taint Worker Nodes${NC}${RED} product=monitoring:NoSchedule${NC}"
#     kubectl taint nodes myk8s-worker2 product=monitoring:NoSchedule
#     echo ">>>${GREEN}Taints${NC}"
#     kubectl get nodes -ojsonpath='{.items[*].spec.taints}'
#     echo ">>>${GREEN}Label Worker Nodes${NC}${RED} role=monitoring${NC}"
#     kubectl label nodes myk8s-worker2 role=monitoring
#     echo ">>>${GREEN}Labels${NC}"
#     kubectl get nodes -ojsonpath='{.items[*].metadata.labels}'
# else
#     echo ">>>${GREEN}myk8s-worker2 Node is not tainted${NC}"
# fi