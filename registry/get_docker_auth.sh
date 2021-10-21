: "${TOKEN_AUTH_DEBUG:=false}"
: "${TOKEN_AUTH_ANONYMOUS_PULL:=true}"

get_docker_auth() {
    local registry=$1

    ${TOKEN_AUTH_DEBUG} && >&2 echo "DDD Got registry=<${registry}>"

    if [[ "${#registry}" -eq 0 ]] || [[ "${registry}" == "index.docker.io" ]]; then
        registry=https://index.docker.io/v1/
    fi
    ${TOKEN_AUTH_DEBUG} && >&2 echo "DDD Using registry=<${registry}>"

    cat ~/.docker/config.json | jq --raw-output ".auths | to_entries[] | select(.key == \"${registry}\") | .value.auth" | base64 -d
}