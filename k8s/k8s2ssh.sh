k8s2ssh() {
    if [[ "$#" == 1 ]]; then
        local CLUSTER=$1
    fi
    if [[ -z "${CLUSTER}" ]]; then
        local CONTEXT=$(kubectl config current-context)
        local CLUSTER=$(kubectl config get-contexts ${CONTEXT} | tail -n +2 | tr -s ' ' | cut -d' ' -f3)
    fi
    if [[ -z "${CLUSTER}" ]]; then
        echo Unable to determine cluster name
        kubectl config get-contexts
        exit 1
    fi
    echo "Found cluster name <${CLUSTER}>"

    rm -f ~/.ssh/config.d/k8s_${CLUSTER}_*
    kubectl get nodes -o wide | tail -n +2 | tr -s ' ' | while read LINE
    do
        local SERVER_NAME=$(echo $LINE | cut -d' ' -f1)
        local SERVER_IP=$(echo $LINE | cut -d' ' -f6)

        cat > ~/.ssh/config.d/k8s_${CLUSTER}_${SERVER_NAME} <<EOF
Host ${SERVER_NAME} ${SERVER_IP}
    HostName ${SERVER_IP}
    User rdadm
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
        chmod 0640 ~/.ssh/config.d/k8s_${CLUSTER}_${SERVER_NAME}
    done
}