#!/bin/bash
minikube start --driver=docker --embed-certs
helm install kyverno kyverno/kyverno -n kyverno --create-namespace --set replicaCount=1 --set image.repository=hisu/kyverno
helm install kyverno-policies kyverno/kyverno-policies -n kyverno
kubectl create ns signed
kubectl apply -f signed-policy.yaml
