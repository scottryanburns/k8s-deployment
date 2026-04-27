Here's a complete step-by-step guide to deploy a HA Kubernetes cluster on Ubuntu 24.

---

## Phase 1 — All Nodes (ctrl01, ctrl02, ctrl03, wrk01, wrk02, wrk03)

**1. Update and install dependencies:**
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y apt-transport-https ca-certificates curl gpg
```

**2. Disable swap:**
```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

**3. Load kernel modules:**
```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

**4. Set sysctl params:**
```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

**5. Install containerd:**
```bash
sudo apt install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd
```

**6. Install kubeadm, kubelet, kubectl:**
```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
```

---

## Phase 2 — Control Plane Nodes Only (ctrl01, ctrl02, ctrl03)

**7. Install keepalived and haproxy:**
```bash
sudo apt install -y keepalived haproxy
```

**8. Configure haproxy (same on all 3 control planes):**
```bash
cat <<EOF | sudo tee /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    maxconn 4096

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 10s
    timeout client 30s
    timeout server 30s

frontend kubernetes-frontend
    bind *:16443
    mode tcp
    option tcplog
    default_backend kubernetes-backend

backend kubernetes-backend
    mode tcp
    option tcp-check
    balance roundrobin
    server nobu-ctrl01 192.168.200.51:6443 check fall 3 rise 2
    server nobu-ctrl02 192.168.200.52:6443 check fall 3 rise 2
    server nobu-ctrl03 192.168.200.53:6443 check fall 3 rise 2

listen stats
    bind *:9000
    mode http
    stats enable
    stats uri /stats
EOF

sudo systemctl restart haproxy
sudo systemctl enable haproxy
```

**9. Configure keepalived:**

On **ctrl01 (MASTER):**
```bash
cat <<EOF | sudo tee /etc/keepalived/keepalived.conf
vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass k8s1234
    }
    virtual_ipaddress {
        192.168.200.50
    }
}
EOF
```

On **ctrl02 (BACKUP):**
```bash
cat <<EOF | sudo tee /etc/keepalived/keepalived.conf
vrrp_instance VI_1 {
    state BACKUP
    interface eth0
    virtual_router_id 51
    priority 90
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass k8s1234
    }
    virtual_ipaddress {
        192.168.200.50
    }
}
EOF
```

On **ctrl03 (BACKUP):**
```bash
cat <<EOF | sudo tee /etc/keepalived/keepalived.conf
vrrp_instance VI_1 {
    state BACKUP
    interface eth0
    virtual_router_id 51
    priority 80
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass k8s1234
    }
    virtual_ipaddress {
        192.168.200.50
    }
}
EOF
```

**Start keepalived on all control planes:**
```bash
sudo systemctl restart keepalived
sudo systemctl enable keepalived

# Verify VIP is on ctrl01
ip addr show | grep 192.168.200.50
```

---

## Phase 3 — Initialize Cluster (ctrl01 only)

**10. Initialize the cluster:**
```bash
sudo kubeadm init \
  --control-plane-endpoint "192.168.200.50:16443" \
  --upload-certs \
  --pod-network-cidr=192.168.0.0/16 \
  --kubernetes-version=1.36.0
```

**11. Set up kubeconfig on ctrl01:**
```bash
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

**12. Save the join commands from the output** — you will see two commands:
- One for control plane nodes (with `--control-plane --certificate-key`)
- One for worker nodes

---

## Phase 4 — Join Control Planes (ctrl02 and ctrl03)

**Run the control plane join command on ctrl02 and ctrl03:**
```bash
sudo kubeadm join 192.168.200.50:16443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <cert-key>

# Then set up kubeconfig
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

---

## Phase 5 — Join Workers (wrk01, wrk02, wrk03)

**Run the worker join command on each worker:**
```bash
sudo kubeadm join 192.168.200.50:16443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

---

## Phase 6 — Install Calico CNI (ctrl01 only)

**13. Install Calico:**
```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.5/manifests/tigera-operator.yaml

kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.5/manifests/custom-resources.yaml
```

**14. Watch pods come up:**
```bash
watch kubectl get pods -n calico-system
```

**15. Verify all nodes are Ready:**
```bash
kubectl get nodes
```

## Add labels to worker nodes
kubectl label node nobu-wrk01 node-role.kubernetes.io/worker=
kubectl label node nobu-wrk02 node-role.kubernetes.io/worker=
kubectl label node nobu-wrk03 node-role.kubernetes.io/worker=

## Add alias 
cat <<EOF | tee -a ~/.bashrc

# Kubernetes Aliases & Completion
alias k='kubectl'
complete -o default -F __start_kubectl k
EOF

source ~/.bashrc
