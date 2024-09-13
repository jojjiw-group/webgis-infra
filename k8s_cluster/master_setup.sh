#!/usr/bin/env bash

# Tested with the following settings on DigitalOcean:
# 1. Ubuntu 24.04, containerd 1.7.22 (7f7fdf5fed64eb6a7caf99b3e12efcf9d60e311c) 3. Kubernetes 1.31.0

set -e
set -x

sudo apt-get install -y net-tools

# === Install Container Runtime ===
# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system


# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Install containerd
sudo apt-get install -y containerd.io

# Configure containerd
cat >> containerd_config.toml<< EOF
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
EOF
sudo cp containerd_config.toml /etc/containerd/config.toml
sudo systemctl restart containerd

# === Install kubeadm, kubelet, and kubectl ===
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo systemctl enable --now kubelet

#————————————————————————————

containerd config dump > prev_config.toml

# Re-configure containerd with the following settings
# 1. SystemdCgroup = true
# 2. sandbox_image = "registry.k8s.io/pause:3.10"
# References:
# [1] - https://github.com/kubernetes/kubernetes/issues/112622
# [2] - https://github.com/kubernetes/kubernetes/issues/110177
# [3] - https://medium.com/@zagfox/kubernetes-intro-1330a188b302
sed -i "s/SystemdCgroup = false/SystemdCgroup = true/g" prev_config.toml
sed -i "s/sandbox_image = \"registry\.k8s\.io\/pause:3\.8\"/sandbox_image = \"registry\.k8s\.io\/pause:3\.10\"/g" prev_config.toml   
sudo cp prev_config.toml /etc/containerd/config.toml
sudo systemctl restart containerd

#————————————————————————————

# Extract the private IP for the eth1 interface
private_ip=$(ip addr show eth1 | grep -oP '(?<=inet\s)10\.\d+\.\d+\.\d+')
echo "Use the following IP (eth1) for API server: $private_ip"
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --apiserver-advertise-address=$private_ip

# Configure kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install Weave net
kubectl apply -f https://reweave.azurewebsites.net/k8s/v1.29/net.yaml

# Add ENV variable for wave-net (env: IPALLOC_RANGE = 192.168.0.0/16)
kubectl get ds -n kube-system weave-net -o yaml > prev_weave-net.yaml
sed -i '/name: CHECKPOINT_DISABLE/{N;s/\(value: \"1\"\)/\1\n        - name: '"IPALLOC_RANGE"'\n          value: '"192\.168\.0\.0\/16"'/}' prev_weave-net.yaml
kubectl replace -f prev_weave-net.yaml

#————————————————————————————

# Allow scheduling pods on the master node
# References:
# [1] - https://discuss.kubernetes.io/t/0-1-nodes-are-available-1-node-s-had-untolerated-taint/23248
# [2] - https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#control-plane-node-isolation
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

#———————————————————————————— 