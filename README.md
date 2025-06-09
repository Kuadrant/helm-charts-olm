# Helm chart for deploying Kuadrant and testing environment

This chart requires that your cluster has loadbalancing service capability. It is divided into two parts. 
**Operators chart** installs OLM operators first and after waiting for the full deployment the **Instnaces chart** will 
install the rest of custom CR's provided by those Operators.

These charts can help with installing different versions of Kuadrant on an **Openshift** cluster:
- Community stable Kuadrant operator released build
- Stable, nightly or any developer preview released build from [Quay](https://quay.io/repository/kuadrant/kuadrant-operator-catalog?tab=tags)
- Red Hat Connectivity Link released build (a `wasm-plugin-pull-secret` secret needed)
- Red Hat Connectivity Link pre-release build _for testing_

# What is installed

- Kuadrant-operator
- Red Hat cert-manager
- Istio provider
  - Openshift service mesh v3
- Gateway API CRD's

If you choose to enable Kuadrant testing environment with `tools.enable=true`:

- RH Keycloak
- Jaeger
- Mockserver
- Redis
- Dragonfly
- `kuadrant` and `kuadrant2` namespaces with additionalManifests.yaml

# How to run

1. Set up values.yaml and/or `INSTALL_RHCL_GA` environment variable
2. Login to your cluster
3. Run:
```sh
./install.sh
```
4. Enjoy
5. Cleanup: `./uninstall.sh`

Note: If you want to install current RHCL GA just set `INSTALL_RHCL_GA` to "true" and use the helper 
`./install.sh` script. It overrides certain values from values.yaml so that current RHCL GA is installed. 
It is not needed to modify values.yaml manually in such a case.

## Testsuite deploy

If you want an environment ready for running [Kuadrant testsuite](https://github.com/Kuadrant/testsuite) create additionalManifests.yaml with list of DNS provider credentials and Letsencrypt issuer. More info about required objects see [testsuite wiki](https://github.com/Kuadrant/testsuite/wiki/Guide-to-prepare-Openshift-cluster-to-run-testsuite)
Look at example-additionalManifests.yaml

Use `-t` flag to get Kuadrant testsuite dependencies installed: `./install.sh -t`. It sets `tools.enabled` to true and makes Helm consume additional values from additionalManifests.yaml.

## Manual helm

If you do not want to use helper `./install.sh` (and `./uninstall.sh`) script:

1. Install Operators
```sh
helm install --values values.yaml --values additionalManifests.yaml --wait -g operators/
```
2. Install instances (operands)
```sh
helm install --values values.yaml --values additionalManifests.yaml --wait --timeout 10m -g instances/
```

# Troubleshooting

## Cannot re-use name

```
$ ./install.sh 
Installing operators
Error: INSTALLATION FAILED: cannot re-use a name that is still in use
```
To fix this execute `helm uninstall kuadrant-operators`. Similarly if the error shows up during installing instances: `helm uninstall kuadrant-instances`.

## Unable to continue with install

```
$ ./install.sh 
Installing operators
Error: INSTALLATION FAILED: Unable to continue with install: CustomResourceDefinition "gatewayclasses.gateway.networking.k8s.io" in namespace "" exists and cannot be imported into the current release: invalid ownership metadata; label validation error: missing key "app.kubernetes.io/managed-by": must be set to "Helm"; annotation validation error: missing key "meta.helm.sh/release-name": must be set to "kuadrant-operators"; annotation validation error: missing key "meta.helm.sh/release-namespace": must be set to "default"
```
This happens if there are some leftovers there on a cluster. Typically the Kuadrant had been installed on the cluster previously not using Helm. To overcome such issues everything that Helm creates needs to be removed prior to installing via Helm. For this particular error the Gateway API CRDs needed to be removed.

## Last Resort
If there are not any leftovers from previous installations and the Helm install/uninstall is still failing, the "Helm internal stuff" needs to be cleared up as well.

`helm ls -a` - to see if there is some Helm release on the cluster.

If there is, one needs to remove the "Helm" secret from `default` namespace. The secret name looks similar to `sh.helm.release.v1.kuadrant-operators.v1`. Once removed (and no leftovers are indeed on the cluster) the Helm install/uninstall starts working as expected.
