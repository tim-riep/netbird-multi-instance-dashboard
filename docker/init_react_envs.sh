#!/bin/bash
set -e

# One container can serve several NetBird instances, one per hostname.
# Each instance is a file <hostname>.env in NETBIRD_INSTANCES_DIR holding the
# same variables as the container environment (AUTH_AUTHORITY,
# NETBIRD_MGMT_API_ENDPOINT, ...). Values it leaves out are taken from the
# container environment. The container environment itself is the default
# instance, served for every other hostname; without it those get a 404.
INSTANCES_DIR=${NETBIRD_INSTANCES_DIR:-/etc/netbird-dashboard/instances}
# nginx serves /config.json and /OidcTrustedDomains.js from here, outside the
# web root so no hostname can read another instance's config.
RUNTIME_DIR=/var/lib/netbird-dashboard/instances
CONFIG_TEMPLATE=/usr/share/netbird-dashboard/config.json.tmpl
OIDC_TRUSTED_DOMAINS_TEMPLATE=/usr/share/nginx/html/OidcTrustedDomains.js.tmpl
NGINX_INSTANCES_CONF=/etc/nginx/http.d/00-netbird-instances.conf
DEFAULT_INSTANCE=_default

ENV_VARS="USE_AUTH0 AUTH_AUDIENCE AUTH_AUTHORITY AUTH_CLIENT_ID AUTH_CLIENT_SECRET AUTH_SUPPORTED_SCOPES NETBIRD_MGMT_API_ENDPOINT NETBIRD_MGMT_GRPC_API_ENDPOINT NETBIRD_HOTJAR_TRACK_ID NETBIRD_GOOGLE_ANALYTICS_ID NETBIRD_GOOGLE_TAG_MANAGER_ID AUTH_REDIRECT_URI AUTH_SILENT_REDIRECT_URI NETBIRD_TOKEN_SOURCE NETBIRD_DRAG_QUERY_PARAMS NETBIRD_AUTH_SERVICE_URL NETBIRD_WASM_PATH NETBIRD_LICENSED NETBIRD_CLOUD NETBIRD_AGENT_NETWORK_ONLY NETBIRD_AGENT_NETWORK_ENABLED NETBIRD_HUBSPOT_PORTAL_ID NETBIRD_HUBSPOT_SIGNUP_FORM_ID NETBIRD_HUBSPOT_ONBOARDING_FORM_ID NETBIRD_HUBSPOT_SURVEY_FORM_ID NETBIRD_ANALYTICS_EXCLUDED_EMAILS NETBIRD_ANNOUNCEMENT"
ENV_STR=$(for v in $ENV_VARS; do printf '$%s ' "$v"; done)

# check_required prints why the current environment is not a complete
# instance and fails, or succeeds silently.
check_required() {
    if [[ -z "${AUTH_AUTHORITY}" && -z "${AUTH0_DOMAIN}" ]]; then
        echo "AUTH_AUTHORITY or AUTH0_DOMAIN environment variable must be set"
        return 1
    fi
    if [[ -z "${AUTH_CLIENT_ID}" && -z "${AUTH0_CLIENT_ID}" ]]; then
        echo "AUTH_CLIENT_ID or AUTH0_CLIENT_ID environment variable must be set"
        return 1
    fi
    if [[ -z "${AUTH_AUDIENCE}" && -z "${AUTH0_AUDIENCE}" ]]; then
        echo "AUTH_AUDIENCE or AUTH0_AUDIENCE environment variable must be set"
        return 1
    fi
    if [[ -z "${AUTH_SUPPORTED_SCOPES}" && -z "${AUTH0_DOMAIN}" ]]; then
        echo "AUTH_SUPPORTED_SCOPES environment variable must be set"
        return 1
    fi
    if [[ -z "${USE_AUTH0}" && -z "${AUTH0_DOMAIN}" ]]; then
        echo "USE_AUTH0 environment variable must be set"
        return 1
    fi
    if [[ -z "${NETBIRD_MGMT_API_ENDPOINT}" ]]; then
        echo "NETBIRD_MGMT_API_ENDPOINT environment variable must be set"
        return 1
    fi
}

# build_instance writes config.json, OidcTrustedDomains.js and the CSP for
# one instance from the current environment. Run it in a subshell: it
# exports the instance's values.
build_instance() {
    local name=$1

    # Explicit returns: set -e does not apply inside "( ... ) || exit".
    check_required || return 1

    if [[ "${AUTH_AUDIENCE}" == "none" ]]; then
        unset AUTH_AUDIENCE
    fi

    export AUTH_AUTHORITY=${AUTH_AUTHORITY:-https://$AUTH0_DOMAIN}
    export AUTH_CLIENT_ID=${AUTH_CLIENT_ID:-$AUTH0_CLIENT_ID}
    export AUTH_CLIENT_SECRET=${AUTH_CLIENT_SECRET}
    export AUTH_AUDIENCE=${AUTH_AUDIENCE:-$AUTH0_AUDIENCE}
    export AUTH_REDIRECT_URI=${AUTH_REDIRECT_URI}
    export AUTH_SILENT_REDIRECT_URI=${AUTH_SILENT_REDIRECT_URI}
    export USE_AUTH0=${USE_AUTH0:-true}
    export AUTH_SUPPORTED_SCOPES=${AUTH_SUPPORTED_SCOPES:-openid profile email api offline_access email_verified}

    export NETBIRD_MGMT_API_ENDPOINT=$(echo $NETBIRD_MGMT_API_ENDPOINT | sed -E 's/(:80|:443)$//')
    export NETBIRD_MGMT_GRPC_API_ENDPOINT=${NETBIRD_MGMT_GRPC_API_ENDPOINT}
    export NETBIRD_HOTJAR_TRACK_ID=${NETBIRD_HOTJAR_TRACK_ID}
    export NETBIRD_GOOGLE_ANALYTICS_ID=${NETBIRD_GOOGLE_ANALYTICS_ID}
    export NETBIRD_GOOGLE_TAG_MANAGER_ID=${NETBIRD_GOOGLE_TAG_MANAGER_ID}
    export NETBIRD_TOKEN_SOURCE=${NETBIRD_TOKEN_SOURCE:-accessToken}
    export NETBIRD_DRAG_QUERY_PARAMS=${NETBIRD_DRAG_QUERY_PARAMS:-false}
    export NETBIRD_AUTH_SERVICE_URL=${NETBIRD_AUTH_SERVICE_URL}
    export NETBIRD_WASM_PATH=${NETBIRD_WASM_PATH}
    export NETBIRD_CSP=${NETBIRD_CSP}
    export NETBIRD_LICENSED=${NETBIRD_LICENSED:-false}
    export NETBIRD_CLOUD=${NETBIRD_CLOUD:-false}
    export NETBIRD_AGENT_NETWORK_ONLY=${NETBIRD_AGENT_NETWORK_ONLY:-false}
    export NETBIRD_AGENT_NETWORK_ENABLED=${NETBIRD_AGENT_NETWORK_ENABLED:-false}
    export NETBIRD_HUBSPOT_PORTAL_ID=${NETBIRD_HUBSPOT_PORTAL_ID}
    export NETBIRD_HUBSPOT_SIGNUP_FORM_ID=${NETBIRD_HUBSPOT_SIGNUP_FORM_ID}
    export NETBIRD_HUBSPOT_ONBOARDING_FORM_ID=${NETBIRD_HUBSPOT_ONBOARDING_FORM_ID}
    export NETBIRD_HUBSPOT_SURVEY_FORM_ID=${NETBIRD_HUBSPOT_SURVEY_FORM_ID}
    export NETBIRD_ANALYTICS_EXCLUDED_EMAILS=${NETBIRD_ANALYTICS_EXCLUDED_EMAILS}
    # A permanent banner for this deployment, shown to every user; empty for none.
    export NETBIRD_ANNOUNCEMENT=${NETBIRD_ANNOUNCEMENT}

    # Build CSP
    local FIRST_PARTY_CSP="pkgs.netbird.io"
    local FIRST_PARTY_CSP_CONNECT_SRC="wss://*.netbird.io"
    local THIRD_PARTY_CSP="*.licdn.com *.linkedin.com *.vector.co *.sibforms.com *.hotjar.com *.hotjar.io *.redditstatic.com pixel-config.reddit.com *.clarity.ms c.bing.com *.microsoft.com googleads.g.doubleclick.net pagead2.googlesyndication.com www.google.com www.googleadservices.com *.google-analytics.com *.googletagmanager.com analytics.google.com *.hubapi.com *.hs-banner.com *.hubspot.com *.hubspot.net js.hs-analytics.com *.hsforms.net *.hscollectedforms.net *.hs-analytics.net *.hsforms.com track.hubspot.com *.hsadspixel.net static.hsappstatic.net"
    local THIRD_PARTY_CSP_CONNECT_SRC="https://api.github.com/repos/netbirdio/netbird/releases/latest https://raw.githubusercontent.com/netbirdio/dashboard/ wss://ws.hotjar.com https://api.hetzner.cloud https://api.digitalocean.com"
    local THIRD_PARTY_CSP_SCRIPT_SRC="'sha256-7knV6EIjKUvCpYWE2rCYx8dYV2WCNb2bpTuitFXzBcA=' *.hs-scripts.com"

    local CSP_DOMAINS=""
    local CSP_DOMAINS_CONNECT_SRC=""

    if [[ -n "${NETBIRD_CSP}" ]]; then
        CSP_DOMAINS="$CSP_DOMAINS $NETBIRD_CSP"
    fi

    # Add AUTH_AUTHORITY to CSP
    if [[ -n "${AUTH_AUTHORITY}" ]]; then
        CSP_DOMAINS="$CSP_DOMAINS $AUTH_AUTHORITY"
        local AUTH_AUTHORITY_ORIGIN=$(echo "$AUTH_AUTHORITY" | sed -E 's|^(https?://[^/]+).*|\1|')
        CSP_DOMAINS="$CSP_DOMAINS $AUTH_AUTHORITY_ORIGIN"
    fi

    # Add AUTH_AUDIENCE to CSP
    if [[ -n "${AUTH_AUDIENCE}" && ("${AUTH_AUDIENCE}" == *"http://"* || "${AUTH_AUDIENCE}" == *"https://"*) ]]; then
        CSP_DOMAINS="$CSP_DOMAINS $AUTH_AUDIENCE"
    fi

    # Add NETBIRD_AUTH_SERVICE_URL to CSP
    if [[ -n "${NETBIRD_AUTH_SERVICE_URL}" ]]; then
        CSP_DOMAINS="$CSP_DOMAINS $NETBIRD_AUTH_SERVICE_URL"
    fi

    # Add NETBIRD_MGMT_API_ENDPOINT to CSP
    if [[ -n "${NETBIRD_MGMT_API_ENDPOINT}" ]]; then
        local MGMT_DOMAIN=$(echo "$NETBIRD_MGMT_API_ENDPOINT" | sed -E 's|https?://||' | cut -d'/' -f1 | cut -d':' -f1)
        if [[ -n "$MGMT_DOMAIN" ]]; then
            if [[ "$NETBIRD_MGMT_API_ENDPOINT" == https://* ]]; then
                CSP_DOMAINS="$CSP_DOMAINS $NETBIRD_MGMT_API_ENDPOINT"
                CSP_DOMAINS_CONNECT_SRC="$CSP_DOMAINS_CONNECT_SRC wss://$MGMT_DOMAIN"
            elif [[ "$NETBIRD_MGMT_API_ENDPOINT" == http://* ]]; then
                CSP_DOMAINS="$CSP_DOMAINS $NETBIRD_MGMT_API_ENDPOINT"
                CSP_DOMAINS_CONNECT_SRC="$CSP_DOMAINS_CONNECT_SRC ws://$MGMT_DOMAIN"
            fi
        fi
    fi

    # Add LETSENCRYPT_DOMAIN to CSP
    if [[ -n "${LETSENCRYPT_DOMAIN}" ]]; then
        if [[ "$LETSENCRYPT_DOMAIN" == *"localhost"* ]]; then
            CSP_DOMAINS="$CSP_DOMAINS http://$LETSENCRYPT_DOMAIN"
            CSP_DOMAINS_CONNECT_SRC="$CSP_DOMAINS_CONNECT_SRC ws://$LETSENCRYPT_DOMAIN"
        else
            CSP_DOMAINS="$CSP_DOMAINS https://$LETSENCRYPT_DOMAIN"
            CSP_DOMAINS_CONNECT_SRC="$CSP_DOMAINS_CONNECT_SRC wss://$LETSENCRYPT_DOMAIN"
        fi
    fi

    local CSP_CONNECT_SRC="$CSP_DOMAINS $CSP_DOMAINS_CONNECT_SRC $FIRST_PARTY_CSP $FIRST_PARTY_CSP_CONNECT_SRC $THIRD_PARTY_CSP $THIRD_PARTY_CSP_CONNECT_SRC"
    local CSP_FRAME_SRC="$CSP_DOMAINS $FIRST_PARTY_CSP $THIRD_PARTY_CSP"
    local CSP_SCRIPT_SRC="$CSP_DOMAINS $FIRST_PARTY_CSP $THIRD_PARTY_CSP $THIRD_PARTY_CSP_SCRIPT_SRC"

    # Remove duplicates
    CSP_CONNECT_SRC=$(echo $CSP_CONNECT_SRC | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//')
    CSP_FRAME_SRC=$(echo $CSP_FRAME_SRC | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//')
    CSP_SCRIPT_SRC=$(echo $CSP_SCRIPT_SRC | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//')

    # upgrade-insecure-requests tells the browser to rewrite every http subresource,
    # fetch and WebSocket to https/wss. That is correct for https deployments but breaks
    # plain-http ones (e.g. local or self-hosted over http), where it would rewrite the
    # working http/ws endpoints to unreachable https/wss. Emit it only when the backend
    # is served over https, matching the ws:// vs wss:// scheme logic above.
    local CSP_UPGRADE_INSECURE=" upgrade-insecure-requests;"
    if [[ "$NETBIRD_MGMT_API_ENDPOINT" == http://* || "$AUTH_AUTHORITY" == http://* ]]; then
        CSP_UPGRADE_INSECURE=""
    fi

    local CSP_POLICY="default-src 'none'; connect-src 'self' $CSP_CONNECT_SRC; frame-src 'self' $CSP_FRAME_SRC; script-src 'self' 'wasm-unsafe-eval' $CSP_SCRIPT_SRC; font-src 'self'; img-src * data:; manifest-src 'self'; style-src 'self' 'unsafe-inline'; frame-ancestors 'self'; base-uri 'self'; form-action 'self';$CSP_UPGRADE_INSECURE"

    local dir="$RUNTIME_DIR/$name"
    mkdir -p "$dir" || return 1
    # nginx reads the CSP from the generated map; it must not contain a quote
    # that would end the nginx string.
    echo "${CSP_POLICY//\"/}" > "$dir/csp"

    envsubst "$ENV_STR" < "$OIDC_TRUSTED_DOMAINS_TEMPLATE" > "$dir/OidcTrustedDomains.js" || return 1

    # Escape backslashes and double quotes so any value stays valid JSON.
    local v value
    for v in $ENV_VARS; do
        value=${!v}
        value=${value//\\/\\\\}
        export "$v=${value//\"/\\\"}"
    done
    envsubst "$ENV_STR" < "$CONFIG_TEMPLATE" > "$dir/config.json" || return 1

    echo "Instance $name: API $NETBIRD_MGMT_API_ENDPOINT, CSP: $CSP_POLICY"
}

# The build ships a robots.txt that disallows everything.
# Deployments that want their homepage and install page in search results opt in here.
if [[ "${NETBIRD_ALLOW_SEARCH_INDEXING}" == "true" ]]; then
    cat > /usr/share/nginx/html/robots.txt <<'ROBOTS'
User-agent: *
Allow: /$
Allow: /install$
Allow: /install/$
Disallow: /
ROBOTS
fi

echo "NetBird latest version: ${NETBIRD_LATEST_VERSION}"

rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR"

shopt -s nullglob
INSTANCE_FILES=("$INSTANCES_DIR"/*.env)
shopt -u nullglob

# The container environment is the default instance. With instance files it
# is optional; without them it is the only one and must be complete.
HAS_DEFAULT=false
if (( ${#INSTANCE_FILES[@]} == 0 )); then
    ( build_instance "$DEFAULT_INSTANCE" ) || exit 1
    HAS_DEFAULT=true
elif reason=$(check_required); then
    ( build_instance "$DEFAULT_INSTANCE" ) || exit 1
    HAS_DEFAULT=true
else
    echo "No default instance ($reason); hostnames without an instance file get a 404"
fi

HOSTS=()
for file in "${INSTANCE_FILES[@]}"; do
    host=$(basename "$file" .env | tr '[:upper:]' '[:lower:]')
    if [[ ! "$host" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]]; then
        echo "Instance file $file: name must be a hostname, e.g. vpn.example.com.env" >&2
        exit 1
    fi
    (
        set -a
        # shellcheck disable=SC1090
        source "$file"
        set +a
        build_instance "$host"
    ) || { echo "Instance file $file is incomplete" >&2; exit 1; }
    HOSTS+=("$host")
done

# Map each hostname to its instance and the instance to its CSP header.
{
    echo "# Generated by init_react_envs.sh at container start."
    echo "map \$host \$nb_instance {"
    if [[ "$HAS_DEFAULT" == true ]]; then
        echo "    default \"$DEFAULT_INSTANCE\";"
    else
        echo "    default \"\";"
    fi
    for host in "${HOSTS[@]}"; do
        echo "    \"$host\" \"$host\";"
    done
    echo "}"
    echo "map \$nb_instance \$nb_csp {"
    echo "    default \"default-src 'none';\";"
    for name in "$RUNTIME_DIR"/*; do
        echo "    \"$(basename "$name")\" \"$(cat "$name/csp")\";"
    done
    echo "}"
} > "$NGINX_INSTANCES_CONF"

# When a command is provided, initialization happens before the server starts.
# The rootless image uses this path so nginx never needs to be reloaded.
if (( $# > 0 )); then
    exec "$@"
fi

# Reload nginx so the generated instances and CSP headers take effect.
# supervisord starts nginx (priority 100) before this script (priority 201) and
# never reloads it, so without this nginx keeps serving the static fallback
# from 00-netbird-instances.conf.
reloaded=false
for i in $(seq 1 10); do
    if nginx -s reload 2>/dev/null; then
        echo "Reloaded nginx to apply the instance configuration"
        reloaded=true
        break
    fi
    echo "Waiting for nginx to be ready before reload (attempt $i)..."
    sleep 1
done

if [[ "$reloaded" != true ]]; then
    echo "Failed to reload nginx after writing the instance configuration" >&2
    nginx -t || true
    exit 1
fi
