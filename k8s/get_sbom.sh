#!/bin/bash

if ! type curl >/dev/null 2>&1; then
    >&2 echo "ERROR: Missing curl."
    exit 1
fi
if ! type jq >/dev/null 2>&1; then
    >&2 echo "ERROR: Missing jq."
    exit 1
fi
if ! type numfmt >/dev/null 2>&1; then
    >&2 echo "ERROR: Missing numfmt."
    exit 1
fi

function usage() {
    cat <<EOF
Usage: kubectl get pods foo | $0 [<container>]

Retrieves SBOM files from GitLab repository maintained by vulnerability operator

Environment variables:
    GITLAB_HOST          GitLab host to use (default: gitlab.com)
    GITLAB_TOKEN         (required) Token to use for authentication
    GITLAB_PROJECT_ID    (required) Project ID with SBOM files
    PATH_PREFIX          Optional path prefix
    BRANCH               Branch to read SBOM files from (default: main)
    SBOM_FILE_NAME       Name of SBOM files (default: sbom.json)
EOF
}

CONTAINER=$1

: "${GITLAB_HOST:=gitlab.com}"
: "${BRANCH:=main}"
: "${SBOM_FILE_NAME:=sbom.json}"

if test -z "${GITLAB_TOKEN}"; then
    >&2 echo "ERROR: Missing GITLAB_TOKEN"
    exit 1
fi
if test -z "${GITLAB_PROJECT_ID}"; then
    >&2 echo "ERROR: Missing GITLAB_PROJECT_ID"
    exit 1
fi
if test -n "${PATH_PREFIX}"; then
    PATH_PREFIX="$( echo "${PATH_PREFIX}" | sed -E 's|^/*(.+[^/])/*$|\1|' )"
    PATH_PREFIX="${PATH_PREFIX}/"
fi

POD_JSON="$(cat)"
if test -z "${POD_JSON}"; then
    >&2 echo "ERROR: Got empty pod JSON."
    exit 1
fi
if ! jq '.' <<<"${POD_JSON}" >/dev/null 2>&1; then
    >&2 echo "ERROR: Input must be pod JSON from kubectl."
    exit 1
fi

if test -z "${CONTAINER}"; then
    CONTAINER="$( jq --raw-output '.spec.containers[0].name' <<<"${POD_JSON}" )"
else
    if ! jq --arg container "${CONTAINER}" --exit-status '.spec.containers[] | select(.name == $container)' <<<"${POD_JSON}" >/dev/null 2>&1; then
        >&2 echo "ERROR: Container ${CONTAINER} does not exist."
        exit 1
    fi
fi
>&2 echo "Using container ${CONTAINER}"

IMAGE_ID="$(
    jq --raw-output --arg container "${CONTAINER}" '.status.containerStatuses[] | select(.name == $container) | .imageID' <<<"${POD_JSON}" \
    | sed 's|^docker-pullable://||; s|@|/|;' \
    | sed 's|sha256:|sha256_|'
)"
if test "$?" -gt 0; then
    >&2 echo "ERROR: Failed to parse pod JSON."
    exit 1
fi
if test -z "${IMAGE_ID}"; then
    >&2 echo "ERROR: Failed to parse pod JSON"
    exit 1
fi
>&2 echo "Got image ID: ${IMAGE_ID}"

FILE_PATH="${PATH_PREFIX}${IMAGE_ID}/${SBOM_FILE_NAME}"
>&2 echo "Using file path: ${FILE_PATH}"

URL_ENCODED_FILE_PATH="$(
    echo ${FILE_PATH} \
    | sed 's|/|%2F|g'
)"

SIZE_BYTES="$(
    curl "https://${GITLAB_HOST}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/files/${URL_ENCODED_FILE_PATH}/raw?ref=${BRANCH}" \
        --silent \
        --fail \
        --request HEAD \
        --header "Private-Token: ${GITLAB_TOKEN}" \
        --head \
    | tr -d '\r' \
    | grep -i "X-GitLab-Size" \
    | cut -d' ' -f2 \
    | numfmt --to=iec
)"
if test -z "${SIZE_BYTES}"; then
    >&2 echo "ERROR: Failed to find file."
    exit 1
fi
>&2 echo "Downloading ${SIZE_BYTES}..."

curl "https://${GITLAB_HOST}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/files/${URL_ENCODED_FILE_PATH}/raw?ref=${BRANCH}" \
    --silent \
    --fail \
    --header "Private-Token: ${GITLAB_TOKEN}"