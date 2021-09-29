#!/bin/bash

# Check for filesystem permissions
: "${TARGET:=/usr}"
REQUIRES_SUDO=false
if test "$(stat "${TARGET}" -c '%u')" == "0"; then

    if test "$(id -u)" != "0"; then
        REQUIRES_SUDO=true
    fi
fi
if $REQUIRES_SUDO && ! sudo -n true 2>&1; then
    echo "ERROR: Unble to continue because..."
    echo "       - ...target directory <${TARGET}> is root-owned but..."
    echo "       - ...you are not root and..."
    echo "       - ...you do not have sudo configured."
    # TODO: Switch to rootless Docker?
    exit 1
fi

# Check GitHub rate limit
# https://docs.github.com/en/rest/reference/rate-limit
GITHUB_REMAINING_CALLS="$(curl -s https://api.github.com/rate_limit | jq --raw-output '.rate.remaining')"
if test "${GITHUB_REMAINING_CALLS}" -lt 10; then
    echo "ERROR: Unable to continue because..."
    echo "       - ...you have only ${GITHUB_REMAINING_CALLS} GitHub API calls remaining and..."
    echo "       - ...some tools require one API call to GitHub."
    exit 1
fi

# Check for iptables/nftables
# https://docs.docker.com/network/iptables/
if ! iptables --version | grep --quiet legacy; then
    echo "ERROR: Unable to continue because..."
    echo "       - ...you are using nftables and not iptables..."
    echo "       - ...to fix this iptables must point to iptables-legacy."
    echo "       You don't want to run Docker with iptables=false."
    exit 1
fi

# Install Docker CE
# TODO: Support rootless?
# https://docs.docker.com/engine/install/ubuntu/#install-using-the-convenience-script
curl -fL https://get.docker.com | sh

# TODO: Configure dockerd
#       https://docs.docker.com/engine/reference/commandline/dockerd/#daemon-configuration-file
#       - Default address pool? {"default-address-pools": [{"base": "10.222.0.0/16","size": 24}]}
if test -n "${DOCKER_REGISTRY_MIRROR}"; then
    # TODO: Test update
    cat <<< $(jq --args mirror "${DOCKER_REGISTRY_MIRROR}" '. * {"registry-mirrors":["\($mirror)"]}' /etc/docker/daemon.json) >/etc/docker/daemon.json
fi
cat <<< $(jq '. * {"features":{"buildkit":true}}' /etc/docker/daemon.json) >/etc/docker/daemon.json
# TODO: Restart dockerd

# Configure docker CLI
# https://docs.docker.com/engine/reference/commandline/cli/#docker-cli-configuration-file-configjson-properties
# NOTHING TO BE DONE FOR NOW

# TODO: Use RenovateBot to update pinned versions

# docker-compose v2
# TODO: Make major version configurable?
# TODO: Set target directory for non-root
DOCKER_COMPOSE_VERSION=2.0.0
curl -sLo "${TARGET}/libexec/docker/cli-plugins/docker-compose" "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-amd64"
chmod +x "${TARGET}/libexec/docker/cli-plugins/docker-compose"
cat >"${TARGET}/bin/docker-compose" <<EOF
#!/bin/bash
exec ${TARGET}/libexec/docker/cli-plugins/docker-compose copose "$@"
EOF

# docker-scan
curl -sLo "${TARGET}/bin/docker-scan" https://github.com/docker/scan-cli-plugin/releases/latest/download/docker-scan_linux_amd64
chmod +x "${TARGET}/bin/docker-scan"

# hub-tool
curl -sL https://github.com/docker/hub-tool/releases/latest/download/hub-tool-linux-amd64.tar.gz | tar -xzC "${TARGET}/bin" --strip-components=1

# docker-machine
curl -sLo "${TARGET}/bin/docker-machine" https://github.com/docker/machine/releases/latest/download/docker-machine-Linux-x86_64
chmod +x "${TARGET}/bin/docker-machine"

# buildx
BUILDX_VERSION=0.6.3
curl -sLo "${TARGET}/libexec/docker/cli-plugins/docker-buildx" "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-amd64"
chmod +x "${TARGET}/libexec/docker/cli-plugins/docker-buildx"

# manifest-tool
# https://github.com/estesp/manifest-tool/releases/download/v1.0.3/manifest-tool-linux-amd64

# TODO: portainer
# https://github.com/portainer/portainer/releases/download/2.9.0/portainer-2.9.0-linux-amd64.tar.gz
# portainer/portainer
# portainer/public/

# oras
# https://github.com/oras-project/oras/releases/download/v0.12.0/oras_0.12.0_linux_amd64.tar.gz

# regclient
# https://github.com/regclient/regclient/releases/download/v0.3.8/regctl-linux-amd64
# https://github.com/regclient/regclient/releases/download/v0.3.8/regbot-linux-amd64
# https://github.com/regclient/regclient/releases/download/v0.3.8/regsync-linux-amd64

# Kubernetes

# kubectl
# curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt
# curl -LO https://storage.googleapis.com/kubernetes-release/release/$()/bin/darwin/amd64/kubectl
# kind
# https://github.com/kubernetes-sigs/kind/releases/download/v0.11.1/kind-linux-amd64
# k3d
# https://github.com/rancher/k3d/releases/download/v4.4.8/k3d-linux-amd64
# helm
# https://get.helm.sh/helm-v3.7.0-linux-amd64.tar.gz
# krew
# https://krew.sigs.k8s.io/docs/user-guide/setup/install/
# kustomize
# https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv4.4.0/kustomize_v4.4.0_linux_amd64.tar.gz

# Security

# trivy
# https://github.com/aquasecurity/trivy/releases/download/v0.19.2/trivy_0.19.2_Linux-64bit.tar.gz

# Tools

# jq
# https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
# yq
# https://github.com/mikefarah/yq/releases/download/v4.13.2/yq_linux_amd64
