#!/bin/bash
# Quick script to run Helm

set -e; set -o pipefail;

cd "$(dirname "$0")"

additional_flags=''
tools_additional_flags=''

for arg in "$@"; do
    case "$arg" in
        -t)
            additional_flags+=" --values additionalManifests.yaml --set tools.enabled=true"
            ;;
    esac
done

extensions_image=$(grep 'extensionsImage:' values.yaml | head -1 | sed 's/.*extensionsImage:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | xargs)

if [[ "$INSTALL_RHCL_GA" == "true" ]]; then
    additional_flags+=" --set kuadrant.indexImage='' --set kuadrant.operatorName=rhcl-operator --set kuadrant.channel=stable"
fi

if [[ "$FREEZE_VERSIONS" == "true" ]]; then
    if ! [[ -e "values-versions.yaml" ]]; then
    	script/get-all-versions.sh > "values-versions.yaml" || exit 1;
    else
	echo -n "Using privously frozen versions ";
	head -1 "values-versions.yaml";
    fi
    additional_flags+=" --values values-versions.yaml"
    tools_additional_flags+=" --values values-versions.yaml"
fi

echo "---Installing operators---"
helm_cmd="helm install $additional_flags --wait kuadrant-operators charts/kuadrant-operators"
eval "$helm_cmd"

echo "--Installing instances---"
helm_cmd="helm install $additional_flags --wait kuadrant-instances charts/kuadrant-instances"
eval "$helm_cmd"

if [[ -n "$extensions_image" && -f "extensionCRD.yaml" ]]; then
echo "--Installing extensions---"
helm_cmd="helm install $additional_flags --values extensionCRD.yaml --wait kuadrant-extensions charts/kuadrant-extensions"
eval "$helm_cmd"
fi

if [[ " $* " == *" -t "* ]]; then
echo "--Installing tools operators"
helm_cmd="helm install $tools_additional_flags --wait tools-operators charts/tools-operators"
eval "$helm_cmd"

echo "--Installing tools instances"
helm_cmd="helm install $tools_additional_flags --wait --timeout 10m tools-instances charts/tools-instances"
eval "$helm_cmd"
fi

echo "Success!"
