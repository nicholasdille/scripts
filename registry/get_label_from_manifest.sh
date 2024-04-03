function get_label_from_manifest() {
    local image=$1

    if test -z "${image}"; then
        echo "Usage: $0 <image>"
        return 1
    fi

    if ! type regctl >/dev/null 2>&1; then
        echo "ERROR: Missing regctl."
        return 1
    fi
    if ! type jq >/dev/null 2>&1; then
        echo "ERROR: Missing jq."
        return 1
    fi

    regctl manifest get "${image}" --platform linux/amd64 --format raw-body \
    | jq --raw-output '.config.digest' \
    | xargs -I{} regctl blob get "${image}" {} \
    | jq --raw-output '.config.Labels'
}