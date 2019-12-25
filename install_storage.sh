#! /bin/bash

set -Eeuxo pipefail

install_stos() {
    # Install storageos-operator.
    kubectl apply -f https://github.com/storageos/cluster-operator/releases/download/1.5.2/storageos-operator.yaml
    # Wait for operator to be ready.
    until kubectl -n storageos-operator get deployment storageos-cluster-operator --no-headers -o go-template='{{.status.readyReplicas}}' | grep -q 1; do sleep 3; done
    # Create credentials and storageos cluster.
    kubectl apply -f https://raw.githubusercontent.com/storageos/cluster-operator/master/deploy/secret.yaml
    kubectl apply -f https://raw.githubusercontent.com/storageos/cluster-operator/master/deploy/crds/storageos_v1_storageoscluster_cr.yaml
    # Wait for the storageos cluster to be ready.
    until kubectl -n storageos get daemonset storageos-daemonset --no-headers -o go-template='{{.status.numberReady}}' | grep -q 1; do sleep 5; done
}

# Driver config for the e2e test.
generate_driver_config () {
    cat <<EOF
StorageClass:
  FromName: true
SnapshotClass:
  FromName: false
DriverInfo:
  Name: storageos
  SupportedSizeRange:
    Max: "5Gi"
    Min: "1Gi"
  Capabilities:
    persistence: true
    multipods: true
    exec: true
EOF
}

install() {
    install_stos
    generate_driver_config > "test-driver.yaml"
}

install
