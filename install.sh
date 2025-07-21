#!/bin/bash
# Quick script to run Helm

set -e; set -o pipefail;

cd "$(dirname "$0")"

additional_flags=''

if [[ "$1" == "-t" ]]; then
    additional_flags+=" --values additionalManifests.yaml --set tools.enabled=true"
fi

if [[ "$INSTALL_RHCL_GA" == "true" ]]; then
    additional_flags+=" --set kuadrant.indexImage='' --set kuadrant.operatorName=rhcl-operator --set kuadrant.channel=stable"
fi

echo "---Installing operators---"
helm_cmd="helm install $additional_flags --wait kuadrant-operators charts/kuadrant-operators"
eval "$helm_cmd"

echo "--Installing instances---"
helm_cmd="helm install $additional_flags --wait kuadrant-instances charts/kuadrant-instances"
eval "$helm_cmd"

if [[ "$1" == "-t" ]]; then
echo "--Installing tools operators"
helm install --wait tools-operators charts/tools-instances

echo "--Installing tools instances"
helm install --wait --timeout 10m tools-instances charts/tools-instances
fi

echo "Success!"
