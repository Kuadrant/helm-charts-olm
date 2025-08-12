# Helm charts for deploying Kuadrant and testing environment on Openshift via OLM

If you are looking for non-OLM Helm charts, go to [helm-charts](https://github.com/Kuadrant/helm-charts)

These charts require that your cluster has loadbalancing service capability. It is divided into two parts. 
**Operators chart** installs OLM operators first and after waiting for the full deployment the **Instnaces chart** will 
install the rest of custom CR's provided by those Operators. Additionally, you can choose to deploy testing tools charts
which are also divided into operators and instances charts.

These charts can help with installing different versions of Kuadrant on an **Openshift** cluster:
- Community stable Kuadrant operator released build
- Stable, nightly or any developer preview released build from [Quay](https://quay.io/repository/kuadrant/kuadrant-operator-catalog?tab=tags)
- Red Hat Connectivity Link released build (a `wasm-plugin-pull-secret` secret needed)
- Red Hat Connectivity Link pre-release build _for testing_

## What is installed

- Kuadrant-operator
- Red Hat cert-manager
- Istio provider
  - Openshift service mesh v3
  - Just GatewayClass CR (for ocp419+, use `ocp` istioProvider)
- Gateway API CRD's (if `ocp` istio Provider not set)

## Testing charts

If you choose to enable Kuadrant testing environment with `tools.enable=true`:
- `kuadrant` and `kuadrant2` namespaces
- testing CA issuers

If you choose to install tools charts:

- RH Keycloak or community Keycloak
- Jaeger
- Mockserver
- Redis
- Dragonfly
- Valkey
- SpiceDB

# How to run

1. Set up [values.yaml](./values.yaml) (and [tool values.yaml](values-tools.yaml))
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

If you want an environment ready for running [Kuadrant testsuite](https://github.com/Kuadrant/testsuite) 
create additionalManifests.yaml with list of DNS provider credentials and Letsencrypt issuer. 
More info about required objects see [testsuite wiki](https://github.com/Kuadrant/testsuite/wiki/Guide-to-prepare-Openshift-cluster-to-run-testsuite)
Look at [example-additionalManifests.yaml](./example-additionalManifests.yaml)

Use `-t` flag to get Kuadrant testsuite dependencies installed: `./install.sh -t`. It sets `tools.enabled` to true 
and makes Helm consume additional values from additionalManifests.yaml and installs tools helm charts.

If you want to install just tools use `./tools-install.sh`. Add `-k` option to install on Kind.

## Manual helm

If you do not want to use helper `./install.sh` (and `./uninstall.sh`) script:

1. Install Operators
```sh
helm install --values values.yaml --wait -g charts/kuadrant-operators
```
2. Install instances (operands)
```sh
helm install --values values.yaml --values additionalManifests.yaml --wait -g charts/kuadrant-instances
```

3. (Optional) Install tools operators
```sh
helm install --values values-tools.yaml --wait -g charts/tools-operators
```

4. (Optional) Install tools instances
```sh
helm install --values values-tools.yaml --wait --timeout 10m -g charts/tools-instances
```

### Installing Authorino Standalone

It is possible to use the charts to install only the Authorino operator without the other Kuadrant dependencies (Cert-Manager, Istio/OSSM, Gateway API). 
This is useful for scenarios where you only need the authorization capabilities of Authorino.

This is controlled by the `kuadrant.operatorName` value. 
To install only the Authorino operator, follow these steps:

1.  Install the operators chart:
    This command will install the OLM subscription for the Authorino operator.
    ```sh
    helm install my-authorino-operators ./charts/kuadrant-operators \
      --wait \
      --set kuadrant.operatorName=authorino-operator
    ```

After the operator is running, you need to create an `Authorino` Custom Resource (CR) to deploy an instance of the Authorino server. 
You can do this by applying a YAML file.

2. (Optional) Installing Test Resources

The `instances` chart is used for development purposes to set up resources needed by the test suite (like the `kuadrant` and `kuadrant2` namespaces). 
Regular users installing Authorino for their own use cases will likely not need this step.

If you need to run the project's test suite, you can install it with the following command:
```sh
helm install my-authorino-instances ./charts/kuadrant-instances \
  --set kuadrant.operatorName=authorino-operator \
  --set tools.enabled=true  
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
This happens if there are some leftovers there on a cluster. Typically, the Kuadrant had been installed on the cluster previously not using Helm. To overcome such issues everything that Helm creates needs to be removed prior to installing via Helm. For this particular error the Gateway API CRDs needed to be removed.

## Last Resort
If there are not any leftovers from previous installations and the Helm install/uninstall is still failing, the "Helm internal stuff" needs to be cleared up as well.

`helm ls -a` - to see if there is some Helm release on the cluster.

If there is, one needs to remove the "Helm" secret from `default` namespace. The secret name looks similar to `sh.helm.release.v1.kuadrant-operators.v1`. Once removed (and no leftovers are indeed on the cluster) the Helm install/uninstall starts working as expected.
