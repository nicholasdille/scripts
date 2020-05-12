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

get_auth_user() {
    cat | cut -d: -f1
}

get_auth_pass() {
    cat | cut -d: -f2
}

get_token_usage() {
    echo "Usage: $0 <registry> <repository> <access> <username> <password> [<insecure>]"
    echo
    echo "           <registry>    Hostname of the container registry, e.g. index.docker.io"
    echo "           <repository>  Path of the repository to access, e.g. library/alpine"
    echo "           <access>      Required access, e.g. pull or push,pull"
    echo "           <username>    Username to use for authentication. Can be empty for anonymous access"
    echo "           <password>    Password for supplied username"
    echo "           <insecure>    Non-empty parameter forces HTTP otherwise HTTPS is used"
}

get_token() {
    local registry=$1
    local repository=$2
    local access=$3
    local user=$4
    local password=$5
    local insecure=$6

    ${TOKEN_AUTH_DEBUG} && >&2 echo "DDD got registry=${registry} repository=${repository} access=${access} user=${user} password=${password} insecure=${insecure}"

    if [[ "$#" -lt 5 || "$#" -gt 6 ]]; then
        get_token_usage
        return
    fi

    local schema=https
    if [[ "${#insecure}" -gt 0 ]]; then
        schema=http
    fi
    ${TOKEN_AUTH_DEBUG} && >&2 echo "DDD schema=${schema}."

    if [[ "${#registry}" -eq 0 ]]; then
        registry=index.docker.io
    fi

    if [[ "${#access}" -eq 0 ]]; then
        access=pull
    fi

    ${TOKEN_AUTH_DEBUG} && >&2 echo "DDD using registry=${registry} repository=${repository} access=${access} user=${user} password=${password} insecure=${insecure}"

    local temp_dir=$(mktemp -d)
    ${TOKEN_AUTH_DEBUG} && >&2 echo "DDD temp_dir=${temp_dir}."

    local http_code=$(curl ${schema}://${registry}/v2/ \
        --silent \
        --write-out "%{http_code}" \
        --output ${temp_dir}/body.txt \
        --dump-header ${temp_dir}/header.txt)
    ${TOKEN_AUTH_DEBUG} && >&2 echo "DDD http_code=${http_code}."
    case $http_code in
        401)
            ${TOKEN_AUTH_DEBUG} && >&2 echo "III Unauthorized"
            local www_authenticate=$(cat ${temp_dir}/header.txt | grep -iE "^Www-Authenticate: " | tr -d '\r')
            ${TOKEN_AUTH_DEBUG} && >&2 echo "DDD www_authenticate=${www_authenticate}."
            if [[ "${#www_authenticate}" -gt 0 ]]; then
                local service_info=$(echo "${www_authenticate}" | cut -d' ' -f3)
                local index=1
                while true; do
                    ${TOKEN_AUTH_DEBUG} && >&2 echo "DDD index=${index}."
                    local item=$(echo "${service_info}" | cut -d',' -f${index})
                    ${TOKEN_AUTH_DEBUG} && >&2 echo "DDD item=${item}."
                    if [[ "${#item}" -eq 0 ]]; then
                        break
                    fi
                    local key=$(echo "${item}" | cut -d= -f1)
                    local value=$(echo "${item}" | cut -d= -f2 | tr -d '"')
                    declare $key=$value
                    index=$((index+1))
                done
                ${TOKEN_AUTH_DEBUG} && >&2 echo "DDD realm=${realm}. service=${service}"
            fi

            if [[ "${#repository}" -eq 0 ]]; then
                >&2 echo "EEE Repository name not provided"
                get_token_usage
                rm -rf ${temp_dir}
                return
            fi
            ${TOKEN_AUTH_DEBUG} && >&2 echo "DDD #user=${#user} #password=${#password}"
            local basic_auth=""
            if [[ "${#user}" -gt 0 && "${#password}" -eq 0 ]]; then
                >&2 echo "EEE User name provided but missing password"
                usage
                rm -rf ${temp_dir}
                return
            elif [[ "${#user}" -eq 0 ]]; then
                ${TOKEN_AUTH_DEBUG} && >&2 echo "DDD No authentication specified"
                if echo "${access}" | grep -vq pull || ! ${TOKEN_AUTH_ANONYMOUS_PULL}; then
                    local auth=$(get_docker_auth ${registry})
                    ${TOKEN_AUTH_DEBUG} && >&2 echo "DDD Got auth length=${#auth}"
                    if [[ "${#auth}" -gt 0 ]]; then
                        ${TOKEN_AUTH_DEBUG} && >&2 echo "DDD Setting basic authentication from Docker credentials"
                        basic_auth="--user '$(echo "${auth}" | get_auth_user):$(echo "${auth}" | get_auth_pass)'"
                    fi
                fi
            else
                ${TOKEN_AUTH_DEBUG} && >&2 echo "DDD Using basic authentication"
                basic_auth="--user ${user}:${password}"
            fi
            ${TOKEN_AUTH_DEBUG} && >&2 echo curl "${realm}" \
                --silent \
                --request GET \
                ${basic_auth} \
                --data-urlencode "service=${service}" \
                --data-urlencode "scope=repository:${repository}:${access}"
            local code=$(curl "${realm}" \
                --silent \
                --request GET \
                ${basic_auth} \
                --data-urlencode "service=${service}" \
                --data-urlencode "scope=repository:${repository}:${access}" \
                --output ${temp_dir}/body.json \
                --write-out "%{http_code}" \
            )
            ${TOKEN_AUTH_DEBUG} && >&2 echo "DDD Got HTTP code <${code}>"
            if test "${code}" -lt 300; then
                ${TOKEN_AUTH_DEBUG} && >&2 echo "DDD Successfully obtained token"
                local expiry_seconds=$(cat ${temp_dir}/body.json | jq --raw-output '.expires_in')
                >&2 echo "Token expires in ${expiry_seconds} seconds"
                cat ${temp_dir}/body.json | jq --raw-output '.token'
            else
                ${TOKEN_AUTH_DEBUG} && >&2 echo "DDD Failed to obtain token"
                cat ${temp_dir}/body.json
                rm -rf ${temp_dir}
                return
            fi
            ;;
    esac

    rm -rf ${temp_dir}
}

get_manifest() {
    curl \
        -sL \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        http://localhost:5000/v2/hello-world-java/manifests/latest \
    | jq
}

get_config() {
    curl \
        -sL \
        -H "Accept: application/vnd.docker.container.image.v1+json" \
        http://localhost:5000/v2/hello-world-java/manifests/latest \
    | jq
}

get_layer() {
    DIGEST=$(
        curl \
            -sL \
            -H "Accept: application/vnd.docker.container.image.v1+json" \
            http://localhost:5000/v2/hello-world-java/manifests/latest \
        | jq --raw-output '.layers[-1].digest'
    )

    curl \
        -sL \
        -H "Accept: application/vnd.docker.image.rootfs.diff.tar.gzip" \
        http://localhost:5000/v2/hello-world-java/blobs/${DIGEST} \
    | tar -tvz
}

tag_remote() {
    # Download manifest from old name
    MANIFEST=$(curl -sL \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        localhost:5000/v2/hello-world-java/manifests/latest
    )

    # Push manifest with new name
    curl -X PUT \
        -H "Content-Type: application/vnd.docker.distribution.manifest.v2+json" \
        -d "${MANIFEST}" \
        localhost:5000/v2/hello-world-java/manifests/new
}