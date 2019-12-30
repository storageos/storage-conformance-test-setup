#!/bin/bash

set -Eeuxo pipefail

# Version of k8s to be used for kind node image and kubectl version if not
# building from the latest k8s by setting KIND_NODE to "latest".
K8S_VERSION="${K8S_VERSION:-v1.17.0}"
# k8s repo version to build e2e test binary and kind node image from.
K8S_REPO_VERSION="${K8S_REPO_VERSION:-master}"
# KinD version to be downloaded if not building from latest version by setting
# KIND_NODE to "latest".
KIND_VERSION="${KIND_VERSION:-0.6.1}"
# Container repo to be used to build kind image name.
KIND_NODE_IMAGE_REPO="${KIND_NODE_IMAGE_REPO:-kindest/node}"
# KinD git repo to build custom version of kind.
KIND_GIT_REPO="${KIND_GIT_REPO:-github.com/kubernetes-sigs/kind}"
# KinD git repo branch to build custom version of kind.
KIND_GIT_REPO_BRANCH="${KIND_GIT_REPO_BRANCH:-master}"

# KIND_NODE can be set to "latest" to build KinD node image from k8s master and
# latest version of the release-* branches.
KIND_NODE="${KIND_NODE:-}"

enable_lio() {
    echo "Enable LIO"
    sudo apt -y update
    sudo apt -y install linux-modules-extra-"$(uname -r)"
    sudo mount --make-shared /sys
    sudo mount --make-shared /
    sudo mount --make-shared /dev
    docker run --name enable_lio --privileged --rm --cap-add=SYS_ADMIN -v /lib/modules:/lib/modules -v /sys:/sys:rshared storageos/init:0.1
    echo
}

build_kind() {
    # Build kind only if the KIND_NODE is set to latest.
    if [ "$KIND_NODE" = "latest" ]; then
        # Clone kind repo.
        KIND_IMPORT_PATH=sigs.k8s.io/kind
        KIND_GIT_REPO_DIR=$GOPATH/src/$KIND_IMPORT_PATH

        echo "Cloning kind repo..."
        git clone --branch "$KIND_GIT_REPO_BRANCH" https://"$KIND_GIT_REPO" "$KIND_GIT_REPO_DIR" --depth 1

        echo "Building kind..."
        pushd "$KIND_GIT_REPO_DIR"
            go mod vendor
            go install -v $KIND_IMPORT_PATH
        popd

        echo "Checking the installed kind..."
        kind
    fi
}

build_kind_node() {
    # Build kind node image if KIND_NODE is set to latest. Else, construct a
    # node image name using KIND_NODE_IMAGE_REPO and K8S_VERSION.
    if [ "$KIND_NODE" = "latest" ]; then
        # Default kind node image name built from master.
        KIND_NODE_IMAGE=kindest/node:latest

        echo "Building kind base image..."
        kind build base-image
        echo "Building kind node image from latest k/k $K8S_REPO_VERSION..."
        kind build node-image --base-image kindest/base:latest
    else
        KIND_NODE_IMAGE="$KIND_NODE_IMAGE_REPO:$K8S_VERSION"
    fi
}

run_kind() {
    # Download kind if it's not built.
    if [ "$KIND_NODE" != "latest" ]; then
        echo "Download kind binary..."
        wget -O kind "https://github.com/kubernetes-sigs/kind/releases/download/v$KIND_VERSION/kind-linux-amd64" && chmod +x kind && sudo mv kind /usr/local/bin/
    fi

    echo "Download kubectl..."
    curl -Lo kubectl "https://storage.googleapis.com/kubernetes-release/release/$K8S_VERSION/bin/linux/amd64/kubectl" && chmod +x kubectl && sudo mv kubectl /usr/local/bin/
    echo

    echo "Create Kubernetes cluster with kind..."
    kind create cluster --image "$KIND_NODE_IMAGE"

    echo "Get cluster info..."
    kubectl cluster-info
    kubectl version
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
