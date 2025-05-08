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

if ! test -f bin/ollama; then
    version=0.6.8
    echo "### Installing Ollama ${version} for ${arch}..."
    curl -sSLf "https://github.com/ollama/ollama/releases/download/v${version}/ollama-linux-${alt_arch}.tgz" \
    | tar --extract --gzip --no-same-owner
fi

docker compose up --detach

# USAGE: OPENAI_ENDPOINT=http://localhost:11434 OPENAI_DEPLOYMENT_NAME=llama3.2 OPENAI_API_KEY="n/a" kubectl-ai
#version=0.0.13
#echo "### Installing Kubectl-AI (community) ${version} for ${arch}..."
#curl -sSLf "https://github.com/sozercan/kubectl-ai/releases/download/v${version}/kubectl-ai_linux_${alt_arch}.tar.gz" \
#| tar --extract --gzip --no-same-owner

# USAGE: kubectl-ai --llm-provider=ollama --model=llama3.2
version=0.0.8
echo "### Installing Kubectl-AI (Google) ${version} for ${arch}..."
curl -sSLf "https://github.com/GoogleCloudPlatform/kubectl-ai/releases/download/v${version}/kubectl-ai_Linux_${arch_suffix}.tar.gz" \
| tar --extract --gzip --no-same-owner
