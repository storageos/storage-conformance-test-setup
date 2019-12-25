# k8s Storage Conformance Test Setup

### StorageOS Test Status

[![Build Status](https://travis-ci.org/darkowlzz/storage-conformance-test-setup.svg?branch=stos)](https://travis-ci.org/darkowlzz/storage-conformance-test-setup)


k8s Storage conformance tests are run against the master branch of k8s.

By default, Kubernetes-in-Docker(KinD) cluster is created from a given KinD node
image.

Once the k8s cluster is ready, the storage system to be tested is installed and
a test config is generated, `test-driver.yaml`.

k8s e2e test binary is built and run against the provided storage system as per
the driver test config.
