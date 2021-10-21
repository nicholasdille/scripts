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