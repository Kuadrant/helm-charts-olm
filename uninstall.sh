#!/bin/bash
# Quick script to uninstall helm and kuadrant CRD

set -e;

cd "$(dirname "$0")"

echo "Uninstalling extensions"
helm uninstall --ignore-not-found --wait kuadrant-extensions
echo "Uninstalling instances"
helm uninstall --ignore-not-found --wait kuadrant-instances
echo "Uninstalling operators"
helm uninstall --ignore-not-found --wait kuadrant-operators
kubectl delete --ignore-not-found ns cert-manager
kubectl get crd -o name | grep "kuadrant" | xargs --no-run-if-empty kubectl delete
kubectl delete  --ignore-not-found consoleplugin.console.openshift.io/kuadrant-console-plugin
echo "Uninstalling tools instances"
helm uninstall --ignore-not-found --wait tools-instances
echo "Uninstalling tools operators"
helm uninstall --ignore-not-found --wait tools-operators
echo "Success!"
