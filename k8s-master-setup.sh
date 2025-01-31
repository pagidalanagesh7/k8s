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

# Master node setup

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

# Initialize Kubernetes master
echo "Initializing Kubernetes master..."
kubeadm init

# If initialization fails with a CRI socket error, suggest the alternative command
if [ $? -ne 0 ]; then
  echo "Initialization failed. Retrying with CRI socket specified..."
  kubeadm init --cri-socket /run/containerd/containerd.sock
  if [ $? -ne 0 ]; then
    echo "Kubernetes initialization failed again. Please check logs."
    exit 1
  fi
fi

# Configure kubectl for the current user
echo "Configuring kubectl for the current user..."
su -c "mkdir -p \$HOME/.kube && sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config && sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config" $(logname)

# Verify kubectl setup
echo "Verifying kubectl setup..."
kubectl version
kubectl get nodes || { echo "Failed to verify nodes. Please check your configuration."; exit 1; }
kubectl get pods -o wide -n kube-system || { echo "Failed to verify pods. Please check your configuration."; exit 1; }

# Install a pod network addon
echo "Installing a pod network addon (Weave Net)..."
kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml

# Verify pods and nodes
echo "Verifying nodes and pods..."
kubectl get nodes
kubectl get pods --all-namespaces

# Display join token
echo "Generating join token for worker nodes..."
kubeadm token create --print-join-command

# Please run the above token on your worker nodes to join with the control plane in the cluster.

echo "Kubernetes master setup complete."
