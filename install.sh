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

if [[ -n "$extensions_image" && -f "extensionCRD.yaml" ]]; then
    additional_flags+=" --values extensionCRD.yaml"
    echo "Extensions enabled: image=$extensions_image, CRD=extensionCRD.yaml"
elif [[ -n "$extensions_image" && ! -f "extensionCRD.yaml" ]]; then
    echo "WARNING: extensionsImage is set but extensionCRD.yaml is missing — extensions will NOT be installed"
elif [[ -z "$extensions_image" && -f "extensionCRD.yaml" ]]; then
    echo "WARNING: extensionCRD.yaml is present but extensionsImage is empty — extensions will NOT be installed"
fi

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

if [[ " $* " == *" -t "* ]]; then
echo "--Installing tools operators"
helm_cmd="helm install $tools_additional_flags --wait tools-operators charts/tools-operators"
eval "$helm_cmd"

echo "--Installing tools instances"
helm_cmd="helm install $tools_additional_flags --wait --timeout 10m tools-instances charts/tools-instances"
eval "$helm_cmd"
fi

echo "Success!"
