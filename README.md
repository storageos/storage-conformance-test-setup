# k8s Storage Conformance Test Setup

k8s Storage conformance tests can be run against the latest, unreleased,
branches of k8s.

In this setup, Kubernetes-in-Docker(KinD) cluster is created from a given KinD
node image. Once the k8s cluster is ready, the storage system to be tested is
installed and a test config is generated, `test-driver.yaml`. k8s e2e test
binary is built and run against the provided storage system as per the driver
test config.

`setup_cluster.sh` builds and provisions k8s cluster.
`install_storage.sh` contains a template for installation of a storage system
with test config generation.
`test.sh` builds the k8s e2e test binary and runs the tests against the
installed storage system.

`K8S_REPO_VERSION` is the version of k8s that's used to build e2e test binary.

`K8S_VERSION` is the version used to download kubectl and construct kind node
image if not building kind node image from latest k8s.

This setup encourages daily test runs. When running daily, k8s should be built
from the latest git version, unreleased. To enable latest builds of kind node
image, set env var `KIND_NODE` to `latest`. When this is set, `K8S_VERSION` will
be ignored and a custom version of node image will be used to create a cluster.
`K8S_REPO_VERSION` should be set to a k8s branch that's updated with all the
new changes for a version release. This can be `release-1.15`, `release-1.16`,
etc. Building and testing against such branches can help detect any possible
failured in the upcoming release.

[stos branch](https://github.com/darkowlzz/storage-conformance-test-setup/tree/stos)
contains an example of a daily run setup for different versions of k8s
against StorageOS. `.travis.yml` in that branch has an example for creating
build matrix for different versions of k8s.
