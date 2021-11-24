hcloud2ssh() {
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
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
        chmod 0640 ~/.ssh/config.d/hcloud_${SERVER_NAME}
    done
}