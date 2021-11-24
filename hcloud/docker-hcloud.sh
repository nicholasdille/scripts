docker-hcloud() {
    mkdir -p ~/.config/docker-hcloud
    test -n "${VM_BASE_NAME}" || local VM_BASE_NAME=docker
    test -n "${HCLOUD_IMAGE}" || local HCLOUD_IMAGE=ubuntu-20.04
    test -n "${HCLOUD_LOCATION}" || local HCLOUD_LOCATION=fsn1
    test -n "${HCLOUD_SSH_KEY}" || local HCLOUD_SSH_KEY=4662975
    test -n "${HCLOUD_TYPE}" || local HCLOUD_TYPE=cx21

    echo "Creating VM with type <${HCLOUD_TYPE}> and image <${HCLOUD_IMAGE}> in location <${HCLOUD_LOCATION}>"

    if ! test -f ~/.config/docker-hcloud/docker-user-data.txt; then
        cat >~/.config/docker-hcloud/docker-user-data.txt <<EOF
#cloud-config

apt:
  conf: |
    APT {
      Install-Recommends "false";
      Install-Suggests "false";
      Get {
        Assume-Yes "true";
        Fix-Broken "true";
      };
    };

package_update: true
package_upgrade: true
packages:
- bash
- curl
- ca-certificates
- jq
- git
- make

write_files:
- path: /opt/init_dotfiles.sh
  owner: root:root
  permissions: 0750
  content: |
    #!/bin/bash
    set -xe
    printenv | sort
    git clone --bare https://github.com/nicholasdille/dotfiles "${USER_HOME}/.cfg"
    alias config='/usr/bin/git --git-dir="${USER_HOME}/.cfg" --work-tree="${USER_HOME}"'
    config config --local status.showUntrackedFiles no
    rm "${USER_HOME}/.bash_logout" "${USER_HOME}/.bashrc" "${USER_HOME}/.profile"
    config checkout

runcmd:
- sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=1"/' /etc/default/grub
- update-grub
- curl -fL https://get.docker.com | sh
- sudo -u user env "USER=${USER_NAME}" "HOME=${USER_HOME}" bash /opt/init_dotfiles.sh

power_state:
  mode: reboot
  delay: now
EOF
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
Host docker-hcloud hcloud ${HCLOUD_VM_IP}
    HostName ${HCLOUD_VM_IP}
    User root
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
