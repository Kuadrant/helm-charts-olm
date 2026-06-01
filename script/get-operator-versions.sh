#!/bin/bash
# Requires jq
# Script queries newest version of operator from catlaog.redhat.com and outputs frozen versions
# Picks newest version as a version number which is semantically biggest

set -euo pipefail

API_BASE="https://catalog.redhat.com/api/containers/v1/images"

get_latest_version() {
    local repo="$1"
    local keep_suffix="${2:-false}"
    local response version

    response=$(curl -s "${API_BASE}?page_size=10&filter=repositories.repository==${repo}&sort_by=creation_date%5Bdesc%5D")

    if [[ "$keep_suffix" == "true" ]]; then
        # For keycloak: sort by both version and suffix number
        version=$(echo "$response" | jq -r '
            [.data[].repositories[]
             | select(.repository == "'"$repo"'")
             | .tags[].name
             | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+-[0-9]+$"))]
            | unique
            | sort_by(split("-") | [(.[0] | split(".") | map(tonumber)), (.[1] | tonumber)])
            | last // empty
        ')
    else
        version=$(echo "$response" | jq -r '
            [.data[].repositories[]
             | select(.repository == "'"$repo"'")
             | .tags[].name
             | select(test("^v?[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9]{1,2})?$"))]
            | unique
            | sort_by(split("-")[0] | ltrimstr("v") | split(".") | map(tonumber))
            | last // empty
        ')
    fi

    if [[ -z "$version" ]]; then
        return
    fi

    [[ "$version" != v* ]] && version="v${version}"
    echo "$version"
}

# Fetch all versions in parallel
tmpdir=$(mktemp -d)
trap "rm -rf $tmpdir" EXIT

get_latest_version "cert-manager/cert-manager-operator-bundle" > "$tmpdir/cert-manager" &
get_latest_version "rhbk/keycloak-operator-bundle" "true" > "$tmpdir/keycloak" &
get_latest_version "openshift-service-mesh/istio-sail-operator-bundle" > "$tmpdir/istio-operator" &
get_latest_version "openshift-service-mesh/istio-pilot-rhel9" > "$tmpdir/istio-version" &

wait

cert_manager_version=$(cat "$tmpdir/cert-manager")
keycloak_full_version=$(cat "$tmpdir/keycloak")
istio_operator_version=$(cat "$tmpdir/istio-operator")
istio_version=$(cat "$tmpdir/istio-version")

# Validate all versions were fetched successfully
failed=()
[[ -z "$cert_manager_version" ]] && failed+=("cert-manager")
[[ -z "$keycloak_full_version" ]] && failed+=("keycloak")
[[ -z "$istio_operator_version" ]] && failed+=("istio-operator")
[[ -z "$istio_version" ]] && failed+=("istio-version")

if [[ ${#failed[@]} -gt 0 ]]; then
    echo "ERROR: Failed to fetch versions for: ${failed[*]}" >&2
    exit 1
fi

# Transform keycloak version: v26.4.11-2 -> base=v26.4.11, suffix=2
keycloak_version="${keycloak_full_version%%-*}"
keycloak_suffix="${keycloak_full_version##*-}"

# Output Helm values override YAML
cat <<EOF
certManager:
  operator:
    startingCSV: cert-manager-operator.${cert_manager_version}
    installPlanApproval: Manual
tools:
  keycloak:
    operator:
      channel: stable-${keycloak_version%%.*}
      startingCSV: rhbk-operator.${keycloak_version}-opr.${keycloak_suffix}
      installPlanApproval: Manual
istio:
  ossm3:
    operator:
      startingCSV: servicemeshoperator3.${istio_operator_version}
      installPlanApproval: Manual
    version: ${istio_version}
EOF
