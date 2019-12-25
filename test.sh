#! /bin/bash

set -Eeuxo pipefail

# Install the test dependencies
go get -v -u github.com/onsi/ginkgo/ginkgo
go get -v -u github.com/onsi/gomega/...

# Build e2e test binary.
pushd $GOPATH/src/k8s.io/kubernetes
make WHAT=test/e2e/e2e.test
# Test binary created at _output/bin/e2e.test
TEST_BIN_PATH=$PWD/_output/bin/e2e.test
popd

SKIP="\[Serial\]|\[Disruptive\]|\[Feature:|Disruptive|different\s+node"
# Skip following tests temporarily. Need to investigate.
SKIP+="|should fail in binding dynamic provisioned PV to PVC \[Slow\]"

# Export KUBECONFIG. This is used by the e2e test binary.
export KUBECONFIG="${HOME}/.kube/config"

ginkgo -v -p -focus="External.Storage" \
    -skip="$SKIP" \
    $TEST_BIN_PATH -- \
    -storage.testdriver=$PWD/test-driver.yaml
