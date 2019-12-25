#! /bin/bash

set -Eeuxo pipefail

readonly K8S_VERSION="v1.17.0"
readonly KIND_VERSION="0.6.1"
readonly KIND_NODE_IMAGE_REPO="storageos/kind-node"

enable_lio() {
    echo "Enable LIO"
    sudo apt -y update
    sudo apt -y install linux-modules-extra-$(uname -r)
    sudo mount --make-shared /sys
    sudo mount --make-shared /
    sudo mount --make-shared /dev
    docker run --name enable_lio --privileged --rm --cap-add=SYS_ADMIN -v /lib/modules:/lib/modules -v /sys:/sys:rshared storageos/init:0.1
    echo
}

run_kind() {
    echo "Download kind binary..."
    wget -O kind "https://github.com/kubernetes-sigs/kind/releases/download/v$KIND_VERSION/kind-linux-amd64" && chmod +x kind && sudo mv kind /usr/local/bin/
    echo "Download kubectl..."
    curl -Lo kubectl https://storage.googleapis.com/kubernetes-release/release/$K8S_VERSION/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/
    echo

    echo "Create Kubernetes cluster with kind..."
    kind create cluster --image $KIND_NODE_IMAGE_REPO:$K8S_VERSION

    echo "Get cluster info..."
    kubectl cluster-info
    echo

    echo "Wait for kubernetes to be ready"
    JSONPATH='{range .items[*]}{@.metadata.name}:{range @.status.conditions[*]}{@.type}={@.status};{end}{end}'; until kubectl get nodes -o jsonpath="$JSONPATH" 2>&1 | grep -q "Ready=True"; do sleep 1; done
    echo

    kubectl get all --all-namespaces
}

setup() {
    enable_lio
    run_kind
}

setup
