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
ansible_ssh_private_key_file: ~/.ssh/id_rsa_hetzner
EOF
    done
}

hcloud2ssh() {
    SSH_KEY_FILE=~/.ssh/id_rsa_hetzner
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
    #CONFIG_FILE=~/.config/docker-hcloud/config.sh
    #[[ -f "${CONFIG_FILE}" ]] && . ${CONFIG_FILE}
    test -n "${VM_BASE_NAME}" || local VM_BASE_NAME=docker
    test -n "${HCLOUD_IMAGE}" || local HCLOUD_IMAGE=ubuntu-20.04
    test -n "${HCLOUD_LOCATION}" || local HCLOUD_LOCATION=fsn1
    test -n "${HCLOUD_SSH_KEY}" || local HCLOUD_SSH_KEY=209622
    test -n "${HCLOUD_TYPE}" || local HCLOUD_TYPE=cx21

    echo "Creating VM with type <${HCLOUD_TYPE}> and image <${HCLOUD_IMAGE}> in location <${HCLOUD_LOCATION}>"

    if ! test -f ~/.config/docker-hcloud/docker-user-data.txt; then
        cat >~/.config/docker-hcloud/docker-user-data.txt <<EOF1
#!/bin/bash

GROUP_NAME=user
GROUP_ID=1000
USER_NAME=user
USER_ID=1000
USER_SHELL=/bin/bash
USER_HOME=/home/${USER_NAME}

apt-get update
apt-get -y install \
    bash \
    curl \
    jq \
    git \
    make

curl -fL https://get.docker.com | sh

groupadd --gid "${GROUP_ID}" "${GROUP_NAME}"
useradd --create-home --shell "${USER_SHELL}" --uid "${USER_ID}" --gid "${GROUP_NAME}" "${USER_NAME}"

mkdir "${USER_HOME}/.ssh"
chmod 0700 "${USER_HOME}/.ssh"
chown user:user "${USER_HOME}/.ssh"
cp /root/.ssh/authorized_keys "${USER_HOME}/.ssh"
chmod 0600 "${USER_HOME}/.ssh/authorized_keys"
chown -R user:user "${USER_HOME}/.ssh"

sudo -u user env "USER=${USER_NAME}" "HOME=${USER_HOME}" bash <<EOF
set -xe
printenv | sort
git clone --bare https://github.com/nicholasdille/dotfiles "${USER_HOME}/.cfg"
alias config='/usr/bin/git --git-dir="${USER_HOME}/.cfg" --work-tree="${USER_HOME}"'
config config --local status.showUntrackedFiles no
rm "${USER_HOME}/.bash_logout" "${USER_HOME}/.bashrc" "${USER_HOME}/.profile"
config checkout
EOF
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
    IdentityFile ~/.ssh/id_rsa_hetzner
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