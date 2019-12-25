#! /bin/bash

set -Eeuxo pipefail

K8S_VERSION="${K8S_VERSION:-v1.17.0}"
KIND_VERSION="${KIND_VERSION:-0.6.1}"
KIND_NODE_IMAGE_REPO="${KIND_NODE_IMAGE_REPO:-storageos/kind-node}"

# KIND_NODE can be set to "master" to build KinD node image from k8s master.
KIND_NODE="${KIND_NODE:-}"

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

build_kind() {
    # Build kind only if the KIND_NODE is set to master. To build KinD node from
    # master, the base image needs some StorageOS specific changes.
    if [ "$KIND_NODE" = "master" ]; then
        # Clone the StorageOS fork of kind.
        KIND_IMPORT_PATH=sigs.k8s.io/kind
        KIND_REPO_DIR=$GOPATH/src/$KIND_IMPORT_PATH
        KIND_LATEST_STOS_BRANCH=kind-15-dec-19

        echo "Cloning kind repo..."
        git clone https://github.com/storageos/kind $KIND_REPO_DIR

        echo "Building kind..."
        pushd $KIND_REPO_DIR
        git fetch
        git checkout -b $KIND_LATEST_STOS_BRANCH origin/$KIND_LATEST_STOS_BRANCH
        go mod vendor
        go install -v $KIND_IMPORT_PATH
        popd

        echo "Checking the installed kind..."
        kind
    fi
}

# Node image building fails due to insufficient memory as per a known KinD
# issue https://kind.sigs.k8s.io/docs/user/known-issues/#failure-to-build-node-image.
build_kind_node() {
    # Build kind node image if KIND_NODE is set to master. Else, construct a
    # node image name using KIND_NODE_IMAGE_REPO and K8S_VERSION.
    if [ "$KIND_NODE" = "master" ]; then
        # Default kind node image name built from master.
        KIND_NODE_IMAGE=kindest/node:latest

        echo "Building kind base image..."
        kind build base-image
        echo "Building kind node image from k/k master..."
        kind build node-image --base-image kindest/base:latest
    else
        KIND_NODE_IMAGE="$KIND_NODE_IMAGE_REPO:$K8S_VERSION"
    fi
}

run_kind() {
    echo "Download kind binary..."
    wget -O kind "https://github.com/kubernetes-sigs/kind/releases/download/v$KIND_VERSION/kind-linux-amd64" && chmod +x kind && sudo mv kind /usr/local/bin/
    echo "Download kubectl..."
    curl -Lo kubectl https://storage.googleapis.com/kubernetes-release/release/$K8S_VERSION/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/
    echo

    echo "Create Kubernetes cluster with kind..."
    kind create cluster --image $KIND_NODE_IMAGE

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
    build_kind
    build_kind_node
    run_kind
}

setup
