#!/usr/bin/env bash
set -e
set -x
kubectl create -R -f .
