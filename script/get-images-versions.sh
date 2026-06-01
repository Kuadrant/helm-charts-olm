#!/bin/bash
# Requires jq
# Script queries semantically newest tag and outputs frozen versions
# Picks newest version as a version number which is semantically biggest

set -euo pipefail

get_token() {
    local registry="$1"
    local image="$2"
    local auth_url token_response

    case "$registry" in
        quay.io)
            auth_url="https://quay.io/v2/auth?service=quay.io&scope=repository:${image}:pull"
            ;;
        ghcr.io)
            auth_url="https://ghcr.io/token?service=ghcr.io&scope=repository:${image}:pull"
            ;;
        docker.dragonflydb.io)
            auth_url="https://ghcr.io/token?service=ghcr.io&scope=repository:${image}:pull"
            ;;
        *)
            echo ""
            return
            ;;
    esac

    token_response=$(curl -s "$auth_url")
    echo "$token_response" | jq -r '.token // .access_token // empty'
}

get_registry_url() {
    local registry="$1"
    case "$registry" in
        docker.dragonflydb.io)
            echo "ghcr.io"
            ;;
        *)
            echo "$registry"
            ;;
    esac
}

fetch_all_tags() {
    local base_url="$1"
    local token="$2"
    local url="${base_url}?n=100"
    local all_tags=""
    local response headers body next_link

    while [[ -n "$url" ]]; do
        if [[ -n "$token" ]]; then
            response=$(curl -sS -D - -H "Authorization: Bearer $token" "$url")
        else
            response=$(curl -sS -D - "$url")
        fi

        headers=$(echo "$response" | sed '/^\r$/q')
        body=$(echo "$response" | sed '1,/^\r$/d')

        tags=$(echo "$body" | jq -r '.tags[]' 2>/dev/null || true)
        all_tags="${all_tags}"$'\n'"${tags}"

        next_link=$(echo "$headers" | grep -i '^link:' | grep -oP '(?<=<)[^>]+(?=>; rel="next")' || true)
        if [[ -n "$next_link" ]]; then
            if [[ "$next_link" =~ ^https?:// ]]; then
                url="$next_link"
            else
                url="${base_url%%/v2/*}${next_link}"
            fi
        else
            url=""
        fi
    done

    echo "$all_tags"
}

get_latest_tag() {
    local full_image="$1"
    local registry image token tags latest actual_registry base_url

    registry="${full_image%%/*}"
    image="${full_image#*/}"

    token=$(get_token "$registry" "$image")
    actual_registry=$(get_registry_url "$registry")
    base_url="https://${actual_registry}/v2/${image}/tags/list"

    tags=$(fetch_all_tags "$base_url" "$token")

    latest=$(echo "$tags" | \
        grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | \
        sed 's/^v//' | \
        sort -t. -k1,1n -k2,2n -k3,3n | \
        tail -1)

    if echo "$tags" | grep -qE "^v${latest}$"; then
        latest="v${latest}"
    fi

    echo "$latest"
}

# Fetch all tags in parallel
tmpdir=$(mktemp -d)
trap "rm -rf $tmpdir" EXIT

get_latest_tag "quay.io/opstree/redis" > "$tmpdir/redis" &
get_latest_tag "docker.dragonflydb.io/dragonflydb/dragonfly" > "$tmpdir/dragonfly" &
get_latest_tag "ghcr.io/valkey-io/valkey" > "$tmpdir/valkey" &
get_latest_tag "quay.io/keycloak/keycloak" > "$tmpdir/keycloak" &
get_latest_tag "quay.io/jaegertracing/jaeger" > "$tmpdir/jaeger" &

wait

redis_tag=$(cat "$tmpdir/redis")
dragonfly_tag=$(cat "$tmpdir/dragonfly")
valkey_tag=$(cat "$tmpdir/valkey")
keycloak_tag=$(cat "$tmpdir/keycloak")
jaeger_tag=$(cat "$tmpdir/jaeger")

# Validate all tags were fetched successfully
failed=()
[[ -z "$redis_tag" ]] && failed+=("redis")
[[ -z "$dragonfly_tag" ]] && failed+=("dragonfly")
[[ -z "$valkey_tag" ]] && failed+=("valkey")
[[ -z "$keycloak_tag" ]] && failed+=("keycloak")
[[ -z "$jaeger_tag" ]] && failed+=("jaeger")

if [[ ${#failed[@]} -gt 0 ]]; then
    echo "ERROR: Failed to fetch versions for: ${failed[*]}" >&2
    exit 1
fi

# Output Helm values override YAML
cat <<EOF
tools:
  jaeger:
    image: quay.io/jaegertracing/jaeger:${jaeger_tag}
  keycloak:
    deployment:
      image: quay.io/keycloak/keycloak:${keycloak_tag}
  redis:
    image: quay.io/opstree/redis:${redis_tag}
  dragonfly:
    image: docker.dragonflydb.io/dragonflydb/dragonfly:${dragonfly_tag}
  valkey:
    image: ghcr.io/valkey-io/valkey:${valkey_tag}
EOF
