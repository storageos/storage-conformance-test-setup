#!/bin/bash

set -Eeuxo pipefail

# This version is used to set the hyperkube version. Hyperkube is used to run
# the storageos-scheduler (scheduler-extender).
# When running the latest versions of k8s, the associated hyperkube container
# image required by StorageOS deployment isn't available, resulting in scheduler
# deployment failure.
K8S_VERSION="${K8S_VERSION:-v1.17.0}"

# Use this to print events and logs of all the pods in a given namespace.
# `$ print_pod_details_and_logs storageos` will print events and logs of all the
# pods in "storageos" namespace.
print_pod_details_and_logs() {
    local namespace="${1?Namespace is required}"

    kubectl get pods --no-headers --namespace "$namespace" | awk '{ print $1 }' | while read -r pod; do
        if [[ -n "$pod" ]]; then
            printf '\n================================================================================\n'
            printf ' Details from pod %s\n' "$pod"
            printf '================================================================================\n'

            printf '\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n'
            printf ' Description of pod %s\n' "$pod"
            printf '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n'

            kubectl describe pod --namespace "$namespace" "$pod" || true

            printf '\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n'
            printf ' End of description for pod %s\n' "$pod"
            printf '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n'

            local init_containers
            init_containers=$(kubectl get pods --output jsonpath="{.spec.initContainers[*].name}" --namespace "$namespace" "$pod")
            for container in $init_containers; do
                printf -- '\n--------------------------------------------------------------------------------\n'
                printf ' Logs of init container %s in pod %s\n' "$container" "$pod"
                printf -- '--------------------------------------------------------------------------------\n\n'

                kubectl logs --namespace "$namespace" --container "$container" "$pod" || true

                printf -- '\n--------------------------------------------------------------------------------\n'
                printf ' End of logs of init container %s in pod %s\n' "$container" "$pod"
                printf -- '--------------------------------------------------------------------------------\n'
            done

            local containers
            containers=$(kubectl get pods --output jsonpath="{.spec.containers[*].name}" --namespace "$namespace" "$pod")
            for container in $containers; do
                printf '\n--------------------------------------------------------------------------------\n'
                printf -- ' Logs of container %s in pod %s\n' "$container" "$pod"
                printf -- '--------------------------------------------------------------------------------\n\n'

                kubectl logs --namespace "$namespace" --container "$container" "$pod" || true

                printf -- '\n--------------------------------------------------------------------------------\n'
                printf ' End of logs of container %s in pod %s\n' "$container" "$pod"
                printf -- '--------------------------------------------------------------------------------\n'
            done

            printf '\n================================================================================\n'
            printf ' End of details for pod %s\n' "$pod"
            printf '================================================================================\n\n'
        fi
    done
}

generate_stos_cluster_config() {
    cat <<EOF
apiVersion: storageos.com/v1
kind: StorageOSCluster
metadata:
  name: example-storageoscluster
  namespace: "default"
spec:
  secretRefName: "storageos-api"
  secretRefNamespace: "default"
  namespace: "storageos"
  images:
    kubeSchedulerContainer: k8s.io/kube-scheduler:test
    nodeContainer: $NODE_CONTAINER
  csi:
    enable: true
    enableProvisionCreds: true
    enableControllerPublishCreds: true
    enableNodePublishCreds: true
  kvBackend:
    address: etcd-client.default.svc.cluster.local:2379
EOF
}

install_stos() {
    STOS_IMPORT_PATH="github.com/storageos/cluster-operator"
    STOS_GIT_REPO_DIR=$GOPATH/src/$STOS_IMPORT_PATH

    # Clone operator repo and generate install manifest.
    git clone https://"$STOS_IMPORT_PATH" "$STOS_GIT_REPO_DIR" --depth 1
    pushd "$STOS_GIT_REPO_DIR"
        make generate-install-manifest
        # Find and replace the operator container image with a develop image.
        sed -i 's/storageos\/cluster-operator:test/darkowlzz\/operator:v0.0.454/' storageos-operator.yaml
        # Disable scheduler webhook.
        # NOTE: This is the only boolean in the file at the moment. This will
        # break and show unexpected results if any new boolean is added in the
        # manifest.
        sed -i 's/false/true/' storageos-operator.yaml
        # Install the operator.
        kubectl apply -f storageos-operator.yaml
        # Wait for operator to be ready.
        until kubectl -n storageos-operator get deployment storageos-cluster-operator --no-headers -o go-template='{{.status.readyReplicas}}' | grep -q 1; do sleep 3; done
        # Append CSI credentials to the base secret.
        csi_creds >> deploy/secret.yaml
        # Create credentials.
        kubectl apply -f deploy/secret.yaml
    popd

    # Apply the previously generated storageos cluster config.
    kubectl apply -f storageoscluster_cr.yaml
    # Wait for the storageos cluster to be ready.
    until kubectl -n storageos get daemonset storageos-daemonset --no-headers -o go-template='{{.status.numberReady}}' | grep -q 1; do sleep 5; done

    # Uncomment to print all the storageos pod logs.
    print_pod_details_and_logs storageos
}

# Driver config for the e2e test.
generate_driver_config () {
    cat <<EOF
StorageClass:
  FromName: false
  FromFile: $PWD/stos-sc.yaml
SnapshotClass:
  FromName: false
DriverInfo:
  Name: storageos
  SupportedSizeRange:
    Max: "5Gi"
    Min: "1Gi"
  Capabilities:
    persistence: true
    exec: true
EOF
}

generate_sc () {
    cat <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: storageos-sc
parameters:
  csi.storage.k8s.io/controller-publish-secret-name: csi-controller-publish-secret
  csi.storage.k8s.io/controller-publish-secret-namespace: storageos
  csi.storage.k8s.io/fstype: ext4
  csi.storage.k8s.io/node-publish-secret-name: csi-node-publish-secret
  csi.storage.k8s.io/node-publish-secret-namespace: storageos
  csi.storage.k8s.io/provisioner-secret-name: csi-provisioner-secret
  csi.storage.k8s.io/provisioner-secret-namespace: storageos
  pool: default
provisioner: $PROVISIONER
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF
}

generate_kube_scheduler_dockerfile() {
    cat <<EOF
FROM gcr.io/distroless/base-debian10
COPY kube-scheduler /usr/local/bin/kube-scheduler
CMD ["/bin/sh", "-c"]
EOF
}

# Build kube-scheduler container image and load the image in KinD.
build_kube_scheduler_image() {
    pushd "$GOPATH/src/k8s.io/kubernetes"
        generate_kube_scheduler_dockerfile > "Dockerfile"
        docker build -t k8s.io/kube-scheduler:test -f Dockerfile _output/dockerized/bin/linux/amd64/
        kind load docker-image k8s.io/kube-scheduler:test
        rm Dockerfile
    popd
}

install_etcd () {
    echo "Install Etcd Operator"

    # Install etcd operator pre-reqs.
    kubectl create -f ./etcd/etcd-rbac.yaml
    # Install etcd operator.
    kubectl create -f ./etcd/etcd-operator.yaml

    # Wait for etcd operator to be ready.
    until kubectl -n default get deployment etcd-operator --no-headers -o go-template='{{.status.readyReplicas}}' | grep -q 1; do sleep 3; done

    # Install etcd cluster.
    kubectl create -f ./etcd/etcd-cluster.yaml

    # Wait for etcd cluster to be ready.
    until kubectl -n default get pod -l app=etcd -l etcd_cluster=etcd -o go-template='{{range .items}}{{.status.phase}}{{end}}' | grep -q Running; do sleep 3; done
    echo
}

# CSI credentials. Append the default secret with these CSI credentials.
csi_creds () {
    cat <<EOF
  csiProvisionUsername: c3RvcmFnZW9z
  csiProvisionPassword: c3RvcmFnZW9z
  csiControllerPublishUsername: c3RvcmFnZW9z
  csiControllerPublishPassword: c3RvcmFnZW9z
  csiNodePublishUsername: c3RvcmFnZW9z
  csiNodePublishPassword: c3RvcmFnZW9z
EOF
}

install() {
    build_kube_scheduler_image
    generate_stos_cluster_config > "storageoscluster_cr.yaml"
    install_etcd
    install_stos
    generate_sc > "stos-sc.yaml"
    generate_driver_config > "test-driver.yaml"
}

install
