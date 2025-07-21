#!/bin/bash
# Quick script to run Helm for installing tools

set -e; set -o pipefail;

cd "$(dirname "$0")"

additional_flags=''

if [[ "$1" == "-k" ]]; then
    additional_flags+=" --set tools.keycloak.keycloakProvider=deployment"
fi

echo "--Installing tools operators"
helm_cmd="helm install $additional_flags --wait tools-operators charts/tools-operators"
eval "$helm_cmd"

echo "--Installing tools instances"
helm_cmd="helm install $additional_flags --wait --timeout 10m tools-instances charts/tools-instances"
eval "$helm_cmd"
