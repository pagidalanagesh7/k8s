#!/bin/bash

# Switch to root user
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit
fi

# Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Add kernel settings
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Enable IP tables (CNI prerequisites) for communication between PODs
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# Install containerd runtime and its dependencies
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release

# Add Docker’s official GPG key
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

# Install containerd
apt-get update -y
apt-get install -y containerd.io

# Generate default configuration for containerd
containerd config default > /etc/containerd/config.toml

# Configure containerd to use systemd as the cgroup driver
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Restart and enable containerd service
systemctl restart containerd
systemctl enable containerd

# Install kubeadm, kubelet, and kubectl
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl

# Add Kubernetes GPG key
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add Kubernetes repository
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" > /etc/apt/sources.list.d/kubernetes.list

# Install kubeadm, kubelet, and kubectl
apt-get update -y
apt-get install -y kubelet kubeadm kubectl

# Prevent automatic upgrades for Kubernetes tools
apt-mark hold kubelet kubeadm kubectl

# Enable and start kubelet service
systemctl daemon-reload
systemctl start kubelet
systemctl enable kubelet.service

echo "Setup complete. Kubernetes components are installed."

## Run the below command on control-plane to create the node's join token
# kubeadm token create --print-join-command

## Run the generated token on the worker node to join with the master node in the kubenretes cluster
# Ex: kubeadm join 172.31.16.48:6443 --token pslh6t.w5rlc87eq00b1shl --discovery-token-ca-cert-hash sha256:2dcfa43f0a6f77eea1b8bf3098b06f68505f245086caedbc17d705d696b47763
