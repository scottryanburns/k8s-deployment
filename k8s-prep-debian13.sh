Here's the script adapted for Debian 13 (Trixie):

```bash
#!/bin/bash
set -euo pipefail

# ──────────────────────────────────────────────
# Kubernetes Node Bootstrap — Debian 13 (Trixie)
# ──────────────────────────────────────────────

# 1. Disable Swap (Kubernetes Requirement)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Debian 13 may use zram-based swap — disable it too
if systemctl is-active --quiet zramswap 2>/dev/null; then
  sudo systemctl disable --now zramswap
fi

# 2. Load Kernel Modules for Networking
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# 3. Sysctl Params for IP Forwarding
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv4.ip_nonlocal_bind           = 1
EOF

sudo sysctl --system

# 4. Install containerd (CRI)
# Debian 13 ships a recent containerd — pull from Docker's repo for latest stable
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Use trixie as the codename (Debian 13)
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian trixie stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y containerd.io   # prefer containerd.io over plain containerd

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# 5. Install Kubernetes Binaries (v1.36)
sudo apt-get install -y apt-transport-https gpg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo systemctl enable --now kubelet

echo ""
echo "✅ Bootstrap complete. Run 'kubeadm init' on the control plane node,"
echo "   or 'kubeadm join' on worker nodes."
```

#Key changes from the original:

#**zram swap** — Debian 13 enables zram swap by default (unlike older Debian), so the script explicitly disables `zramswap.service` in addition to the fstab edit.

#**containerd source** — Rather than the distro's `containerd` package, the script adds Docker's apt repo and installs `containerd.io`. The plain `containerd` package in Debian 13 can lag behind and has had compatibility issues with recent CRI socket paths. The Docker repo targets `trixie` by codename.

#**`/etc/apt/keyrings` creation** — Debian 13 doesn't always pre-create this directory, so `install -m 0755 -d` ensures it exists with correct permissions before writing any keyring files.

#**`apt-transport-https` is optional** — Debian 13's `apt` natively supports HTTPS, so it's no longer a hard dependency, but it's left in as a no-op harmless install in case of edge cases.

#**`systemctl enable`** added for both `containerd` and `kubelet` so they survive reboots without a separate step.
