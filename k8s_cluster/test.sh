#!/usr/bin/bash
set -e

NODE_PORT=30080

kubectl run nginx-pod --image=nginx --port=80
kubectl expose pod nginx-pod --type=NodePort --port=80 --target-port=80
kubectl get all -o wide
echo Pod: nginx created and accessible.
echo Hit any key to destroy the pod.
read -n 1 -s
kubectl delete service/nginx-pod
kubectl delete pod/nginx-pod
echo "Pod and service deleted."
