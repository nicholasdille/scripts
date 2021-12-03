#!/bin/bash

OUTPUT="$(curl --silent --include --write-out '%{json}' "$@" | tr -d '\r')"
is_header=true
is_first_line=true
body=""
echo "${OUTPUT}" | while read -r LINE; do

    if ${is_first_line}; then
        protocol="$(echo "${LINE}" | cut -d' ' -f1)"
        code="$(echo "${LINE}" | cut -d' ' -f2)"
        echo -n "{\"protocol\": \"${protocol}\", \"code\": \"${code}\","
        is_first_line=false

    elif ${is_header}; then

        if test -n "${LINE}"; then
            key="$(echo "${LINE}" | cut -d: -f1)"
            val="$(echo "${LINE}" | cut -d: -f2- | sed 's/"/\\"/g')"
            echo -n "\"${key}\": \"${val:1}\","

        else
            echo -n '"X-Parser": "curl.sh", "X-Homepage": "https://dille.name"}'
            is_header=false
        fi

    else
        echo -n "${LINE}"
    fi
done | jq --slurp '{"curl_response_header": .[0], "curl_stats": .[2], "body": .[1]}'
