#!/bin/bash
# ------------------------------------------------------------------
# Script: common-setup.sh
# Descrizione: Prepara un nodo Linux per Kubernetes (Kubeadm)
# ------------------------------------------------------------------

set -e

KUBERNETES_VERSION="1.35"

echo "Disabilitazione Swap (Richiesto dal Kubelet)..."
# Kubernetes non gestisce bene la memoria se lo swap è attivo
sudo swapoff -a
# Disabilita lo swap in modo permanente commentando la riga in fstab
sudo sed -i '/swap/ s/^\(.*\)$/#\1/g' /etc/fstab

echo "Caricamento Moduli Kernel..."
# overlay: necessario per il filesystem dei container
# br_netfilter: permette a iptables di vedere il traffico bridged
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

echo "Configurazione Sysctl (Networking)..."
# Queste impostazioni sono CRITICHE per il funzionamento del CNI (es. Cilium)
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

echo "Installazione Containerd (Runtime)..."
# Installazione prerequisiti e chiave GPG Docker
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Aggiunta repository Docker
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y containerd.io

echo "Configurazione Containerd (SystemdCgroup)..."
# Genera configurazione di default
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

# Kubelet e Container Runtime devono usare lo stesso driver (systemd)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

sudo systemctl restart containerd

echo "Installazione Kubeadm, Kubelet, Kubectl..."
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Chiave GPG Kubernetes (Community Owned)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Repository Kubernetes
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
# Installazione pacchetti specifici
sudo apt-get install -y kubelet kubeadm kubectl
# Blocca gli aggiornamenti automatici (fondamentale in produzione!)
sudo apt-mark hold kubelet kubeadm kubectl

echo "Nodo pronto per 'kubeadm init' o 'kubeadm join'."