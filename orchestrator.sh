#!/bin/bash
set -e

MASTER_NAME="master"
AGENT_NAME="agent"
MASTER_IP="192.168.56.10"
AGENT_IP="192.168.56.11"
K3S_VERSION="v1.30.14+k3s1"

echo "Master: $MASTER_NAME ($MASTER_IP)"
echo "Agent: $AGENT_NAME ($AGENT_IP)"
echo "K3s version: $K3S_VERSION"

install_master_k3s() {
    vagrant ssh master --no-tty -c \
    "curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION='$K3S_VERSION' \
    INSTALL_K3S_EXEC='server --write-kubeconfig-mode 644 --advertise-address $MASTER_IP --tls-san $MASTER_IP --node-ip $MASTER_IP --flannel-iface eth1' \
    sh -"
}

install_agent_k3s() {
    K3S_TOKEN=$(vagrant ssh master --no-tty -c \
        'sudo cat /var/lib/rancher/k3s/server/node-token' 2>/dev/null)

    vagrant ssh agent --no-tty -c \
    "curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION='$K3S_VERSION' \
    INSTALL_K3S_TYPE='agent' \
    K3S_URL='https://$MASTER_IP:6443' \
    K3S_TOKEN='$K3S_TOKEN' \
    sh -"

    unset K3S_TOKEN
}

create_vms() {
    vagrant up
    install_master_k3s
    install_agent_k3s
}
start_cluster() {
    vagrant start
}
stop_cluster() {
    vagrant halt
}
destroy_cluster() {
    vagrant destroy -f
}
status_cluster(){
    vagrant status
    kubectl get nodes
}
case "$1" in
    create)
        create_vms
        ;;
    start)
        start_cluster
        ;;
    stop)
        stop_cluster
        ;;
    destroy)
        destroy_cluster
        ;;
    status)
        status_cluster
        ;;
    *)
        echo "Usage: $0 {create|start|stop|destroy|status}"
        ;;
esac