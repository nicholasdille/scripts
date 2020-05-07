hcloud2null() {
    hcloud volume list -o columns=id | tail -n +2 | xargs -r -n 1 hcloud volume detach
    hcloud volume list -o columns=id | tail -n +2 | xargs -r -n 1 hcloud volume delete
    hcloud server list -o columns=id | tail -n +2 | xargs -r -n 1 hcloud server delete
}

hcloud2ansible() {
    if ! test -d host_vars; then
        echo "No host_vars directory found. Is this really an ansible directory?"
        exit 1
    fi

    hcloud server list -o columns=name,ipv4 | tail -n +2 | while read LINE
    do
        SERVER_NAME=$(echo $LINE | awk '{print $1}')
        SERVER_IP=$(echo $LINE | awk '{print $2}')

        cat > host_vars/${SERVER_NAME} <<EOF
---

ansible_host: ${SERVER_IP}
ansible_user: deploy
ansible_become: yes
ansible_ssh_private_key_file: ~/id_rsa_hetzner
EOF
    done
}

hcloud2ssh() {
    SSH_KEY_FILE=~/id_rsa_hetzner
    if [[ -n "$1" ]]; then
        SSH_KEY_FILE=$1
    fi

    rm -f ~/.ssh/config.d/hcloud_*
    hcloud server list -o columns=name,ipv4 | tail -n +2 | while read LINE
    do
        SERVER_NAME=$(echo $LINE | awk '{print $1}')
        SERVER_IP=$(echo $LINE | awk '{print $2}')

        echo "Adding SSH configuration for <${SERVER_NAME}> at <${SERVER_IP}>"

        cat > ~/.ssh/config.d/hcloud_${SERVER_NAME} <<EOF
Host ${SERVER_NAME} ${SERVER_IP}
    HostName ${SERVER_IP}
    User root
    IdentityFile ${SSH_KEY_FILE}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
        chmod 0640 ~/.ssh/config.d/hcloud_${SERVER_NAME}
    done
}

docker-hcloud() {
    mkdir -p ~/.config/docker-hcloud
    CONFIG_FILE=~/.config/docker-hcloud/config.sh
    [[ -f "${CONFIG_FILE}" ]] && . ${CONFIG_FILE}
    : "${VM_BASE_NAME:=docker}"
    : "${HCLOUD_IMAGE:=ubuntu-18.04}"
    : "${HCLOUD_LOCATION:=fsn1}"
    : "${HCLOUD_SSH_KEY:=209622}"
    : "${HCLOUD_TYPE:=cx21}"

    if ! test -f ~/.config/docker-hcloud/docker-user-data.txt; then
        cat >~/.config/docker-hcloud/docker-user-data.txt <<EOF1
#!/bin/bash

curl -fL https://get.docker.com | sh

apt-get -y install curl jq make

# kubectl
curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt | \
    xargs -I{} curl -sLo /usr/local/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/{}/bin/linux/amd64/kubectl
chmod +x /usr/local/bin/kubectl
cat >>~/.bashrc <<EOF2
source <(kubectl completion bash)
alias k=kubectl
complete -F __start_kubectl k
EOF2

# k3s
curl -s https://api.github.com/repos/rancher/k3s/releases/latest | \
    jq --raw-output '.assets[] | select(.name == "k3s") | .browser_download_url' | \
    xargs curl -sLfo /usr/local/bin/k3s
chmod +x /usr/local/bin/k3s

# k3d
curl -s https://raw.githubusercontent.com/rancher/k3d/master/install.sh | bash

# kind
curl -s https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | \
        jq --raw-output '.assets[] | select(.name == "kind-linux-amd64") | .browser_download_url' | \
            xargs curl -sLfo /usr/local/bin/kind
chmod +x /usr/local/bin/kind
EOF1
    fi

    HCLOUD_VM_IP=$(hcloud server list --selector docker-hcloud=true --output columns=ipv4 | tail -n +2)
    if [[ -z "${HCLOUD_VM_IP}" ]]; then
        HCLOUD_VM_NAME="${VM_BASE_NAME}-$(date +%Y%m%d%H%M)"
        hcloud server create \
            --location ${HCLOUD_LOCATION} \
            --image ${HCLOUD_IMAGE} \
            --name ${HCLOUD_VM_NAME} \
            --ssh-key ${HCLOUD_SSH_KEY} \
            --type ${HCLOUD_TYPE} \
            --user-data-from-file ~/.config/docker-hcloud/docker-user-data.txt
        hcloud server add-label ${HCLOUD_VM_NAME} docker-hcloud=true
        HCLOUD_VM_IP=$(hcloud server list --output columns=ipv4,name | grep docker-${HCLOUD_DOCKER_VM_NAME} | cut -d' ' -f1)
    fi

    # Creating SSH config
    cat >~/.ssh/config.d/docker-hcloud <<EOF
Host docker-hcloud ${HCLOUD_VM_IP}
    HostName ${HCLOUD_VM_IP}
    User root
    IdentityFile ~/id_rsa_hetzner
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
    chmod 0600 ~/.ssh/config.d/docker-hcloud

    # Wait for dockerd
    echo Waiting for dockerd...
    timeout 300 bash -c "while test -z \"\$(ssh ${HCLOUD_VM_IP} ps -C dockerd --no-headers)\"; do sleep 5; done"

    # Configuring docker
    docker context ls -q | grep docker-hcloud | xargs -r docker context rm -f
    docker context create docker-hcloud --docker "host=ssh://${HCLOUD_VM_IP}"
    docker context use docker-hcloud
}