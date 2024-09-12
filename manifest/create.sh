#!/usr/bin/env bash
set -e
set -x
#kubectl create -R -f storage
#sleep 2
kubectl create -R -f deployments
sleep 2
kubectl create -R -f services
