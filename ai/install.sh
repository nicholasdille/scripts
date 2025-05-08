#!/bin/bash
set -o errexit

arch="$(uname -m)"
case "${arch}" in
    x86_64)
        alt_arch="amd64"
        arch_suffix="${arch}"
        ;;
    aarch64)
        alt_arch="arm64"
        arch_suffix="${alt_arch}"
        ;;
    *)
        echo "ERROR: Unsupported architecture ${arch}."
        exit 1
        ;;
esac

docker compose up --detach ollama
