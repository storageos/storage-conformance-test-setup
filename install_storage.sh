#! /bin/bash

set -Eeuxo pipefail

# Use this to print events and logs of all the pods in a given namespace.
# `$ print_pod_details_and_logs foons` will print events and logs of all the
# pods in "foons" namespace.
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

install_storage() {
    # Install the storage system.

    # Uncomment to print all the foo-ns pod logs.
    # print_pod_details_and_logs foo-ns
}

# Driver config for the e2e test.
generate_driver_config () {
    cat <<EOF
StorageClass:
  FromName: true
SnapshotClass:
  FromName: false
DriverInfo:
  Name: <storage-name>
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
    install_storage
    generate_driver_config > "test-driver.yaml"
}

install
