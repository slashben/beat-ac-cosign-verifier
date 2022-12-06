#!/bin/bash
# Setup a Kubernetes cluster with Kyverno and a signed image policy for the attack POC
# Usage: setup-cluster.sh 

# Check if minikube is available
if ! command -v minikube &> /dev/null
then
    echo "minikube could not be found"
    exit
fi

# Check if .minikube directory exists
if [ ! -d ~/.minikube ]; then
    echo "minikube is not initialized"
    exit
fi

# Make sure that minikube is not running
if minikube status | grep -q "host: Running"; then
    echo "minikube is running"
    exit
fi

# copy the benCA.pem to the minikube certs directory
cp certs/benCA.pem ~/.minikube/certs/. || exit 1


# start minikube with docker driver and embed the certs
minikube start --driver=docker --embed-certs || exit 1

# Check if Kyverno HELM repository is available
if ! helm repo list | grep -q "kyverno"; then
    # add Kyverno Helm repository and update
    helm repo add kyverno https://kyverno.github.io/kyverno/ || exit 1
    helm repo update || exit 1
fi

# install Kyverno and Kyverno policies
helm install kyverno kyverno/kyverno -n kyverno --create-namespace --set replicaCount=1 --set image.repository=hisu/kyverno || exit 1
helm install kyverno-policies kyverno/kyverno-policies -n kyverno || exit 1

sleep 15

# Wait for Kyverno to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kyverno -n kyverno --timeout=120s || exit 1

# create a namespace for the attack POC
kubectl create ns signed || exit 1

# add Kyverno policy to allow only signed images
kubectl apply -f signed-policy.yaml || exit 1

