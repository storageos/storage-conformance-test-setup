#! /bin/bash

set -Eeuxo pipefail

# Builds on k8s v1.15* fails due to some dependency issue. Use k8s-test archive
# for that version.
BROKEN_VERSION="v1.15"

K8S_VERSION="${K8S_VERSION:-v1.17.0}"

# Install the test dependencies
go get -v -u github.com/onsi/ginkgo/ginkgo
go get -v -u github.com/onsi/gomega/...

# Build e2e test binary.
if [[ "$BROKEN_VERSION" == *"$K8S_VERSION"* ]]; then
    # Building e2e test binary fails for v1.15. Download a pre-built version
    # for now.
    curl -Lo kubernetes-test.tar.gz https://dl.k8s.io/v1.15.7/kubernetes-test-linux-amd64.tar.gz
    tar -zxvf kubernetes-test.tar.gz
    TEST_BIN_PATH=$PWD/kubernetes/test/bin/e2e.test
else
    pushd "$GOPATH/src/k8s.io/kubernetes"
    make WHAT=test/e2e/e2e.test
    # Test binary created at _output/bin/e2e.test
    TEST_BIN_PATH=$PWD/_output/bin/e2e.test
    popd
fi

SKIP="\[Serial\]|\[Disruptive\]|\[Feature:|Disruptive|different\s+node"
# Skip following tests temporarily. Need to investigate.
SKIP+="|should fail in binding dynamic provisioned PV to PVC \[Slow\]"

# Export KUBECONFIG. This is used by the e2e test binary.
export KUBECONFIG="${HOME}/.kube/config"

ginkgo -v -p -focus="External.Storage" \
    -skip="$SKIP" \
    "$TEST_BIN_PATH" -- \
    -storage.testdriver="$PWD/test-driver.yaml"
