vm-hcloud() {
    test -n "${VM_BASE_NAME}" || local VM_BASE_NAME=vm
    test -n "${HCLOUD_IMAGE}" || local HCLOUD_IMAGE=ubuntu-22.04
    test -n "${HCLOUD_LOCATION}" || local HCLOUD_LOCATION=fsn1
    test -n "${HCLOUD_SSH_KEY}" || local HCLOUD_SSH_KEY=4662975
    test -n "${HCLOUD_TYPE}" || local HCLOUD_TYPE=cx21

    echo "Creating VM with type <${HCLOUD_TYPE}> and image <${HCLOUD_IMAGE}> in location <${HCLOUD_LOCATION}>"

    HCLOUD_VM_IP=$(hcloud server list --selector vm-hcloud=true --output columns=ipv4 | tail -n +2)
    if [[ -z "${HCLOUD_VM_IP}" ]]; then
        HCLOUD_VM_NAME="${VM_BASE_NAME}-$(date +%Y%m%d%H%M)"
        hcloud server create \
            --location ${HCLOUD_LOCATION} \
            --image ${HCLOUD_IMAGE} \
            --name ${HCLOUD_VM_NAME} \
            --ssh-key ${HCLOUD_SSH_KEY} \
            --type ${HCLOUD_TYPE} \
            --user-data-from-file <(curl -sL https://github.com/nicholasdille/docker-setup/raw/main/contrib/cloud-init.yaml)
        hcloud server add-label ${HCLOUD_VM_NAME} vm-hcloud=true
        HCLOUD_VM_IP=$(hcloud server list --output columns=ipv4,name | grep ${HCLOUD_VM_NAME} | cut -d' ' -f1)
    fi

    # Creating SSH config
    cat >~/.ssh/config.d/vm-hcloud <<EOF
Host vm-hcloud vm ${HCLOUD_VM_IP}
    HostName ${HCLOUD_VM_IP}
    User root
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
    chmod 0600 ~/.ssh/config.d/vm-hcloud
}
