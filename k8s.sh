env2kubeconfig() {
    kubectl config set-cluster self \
        --server=${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT} \
        --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    kubectl config set-credentials self \
        --token=/var/run/secrets/kubernetes.io/serviceaccount/token
    kubectl config set-context self \
        --cluster=self \
        --user=self
}

k8s_api() {
    local request=$1
    : "${request:=/}"

    curl -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}${request}
}

k8s2ssh() {
    if [[ "$#" == 1 ]]; then
        CLUSTER=$1
    fi
    SSH_KEY=~/id_rsa
    if [[ -z "${CLUSTER}" ]]; then
        CONTEXT=$(kubectl config current-context)
        CLUSTER=$(kubectl config get-contexts ${CONTEXT} | tail -n +2 | tr -s ' ' | cut -d' ' -f3)
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
        SERVER_NAME=$(echo $LINE | cut -d' ' -f1)
        SERVER_IP=$(echo $LINE | cut -d' ' -f6)

        cat > ~/.ssh/config.d/k8s_${CLUSTER}_${SERVER_NAME} <<EOF
Host ${SERVER_NAME} ${SERVER_IP}
    HostName ${SERVER_IP}
    User rdadm
    IdentityFile ${SSH_KEY}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
        chmod 0640 ~/.ssh/config.d/k8s_${CLUSTER}_${SERVER_NAME}
    done
}

sa2kubeconfig() {
    if [[ "$#" == 1 ]]; then
        ACCOUNT=$1
    fi
    if [[ -z "${ACCOUNT}" ]]; then
        echo Specify name of service account as parameter
        exit 1
    fi

    CONTEXT=$(kubectl config current-context)
    if [[ -z "${CONTEXT}" ]]; then
        echo Failed to determine current context
        exit 1
    fi

    CLUSTER=$(kubectl config get-contexts svc-2-admin | tail -n +2 | tr -s ' ' | cut -d' ' -f3)
    if [[ -z "${CLUSTER}" ]]; then
        echo Failed to determine cluster
        exit 1
    fi

    SECRET=$(kubectl get serviceaccounts ${ACCOUNT} -o json | jq --raw-output ".secrets[0].name")
    if [[ -z "${SECRET}" ]]; then
        echo Failed to determine account secret for ${ACCOUNT}
        exit 1
    fi
    TOKEN=$(kubectl get secrets ${SECRET} -o json | jq --raw-output ".data.token" | base64 -d)
    if [[ -z "${TOKEN}" ]]; then
        echo Failed to determine account token for ${ACCOUNT}
        exit 1
    fi

    kubectl config set-credentials "${ACCOUNT}@${CLUSTER}" --token=${TOKEN}
    kubectl config set-context "${ACCOUNT}@${CLUSTER}" --cluster=${CLUSTER} --user="${ACCOUNT}@${CLUSTER}"
}

normalize_kubeconfig() {
    if [[ "$#" -ne "3" ]]; then
        echo "Usage: $0 <kubeconfig-file> <cluster-name> <dns-suffix>"
        exit 1
    fi

    FILE=$1
    CLUSTER=$2
    DNS_SUFFIX=$3

    if ! test -f ${FILE}; then
        echo "Kubeconfig file ${FILE} does not exist"
        exit 1
    fi
    if test -f ${FILE}.bak; then
        echo "Backup file ${FILE}.bak already exists"
        exit 1
    fi
    if test -z "${CLUSTER}"; then
        echo "Cluster name must not be empty"
        exit 1
    fi
    if test -z "${DNS_SUFFIX}"; then
        echo "DNS suffix must not be empty"
        exit 1
    fi
    if ! nslookup ${CLUSTER}.${DNS_SUFFIX} >/dev/null; then
        echo "DNS name for cluster (${CLUSTER}.${DNS_SUFFIX}) does not exist"
        exit 1
    fi

    export KUBECONFIG=${FILE}

    JSON=$(kubectl config view --raw -o json)
    echo "${JSON}" | jq --raw-output '.clusters[0].cluster."certificate-authority-data"' | base64 -d > certificate-authority.pem
    echo "${JSON}" | jq --raw-output '.users[0].user."client-certificate-data"'          | base64 -d > client-certificate.pem
    echo "${JSON}" | jq --raw-output '.users[0].user."client-key-data"'                  | base64 -d > client-key.pem

    mv ${FILE} ${FILE}.bak

    kubectl config set-cluster ${CLUSTER} \
        --server=https://${CLUSTER}.k8s.haufedev.systems:6443 \
        --certificate-authority=certificate-authority.pem \
        --embed-certs=true
    kubectl config set-credentials ${CLUSTER}-admin \
        --client-certificate=client-certificate.pem \
        --client-key=client-key.pem \
        --embed-certs=true
    kubectl config set-context ${CLUSTER}-admin \
        --cluster=${CLUSTER} \
        --namespace=default \
        --user=${CLUSTER}-admin
    kubectl config use-context ${CLUSTER}-admin

    rm certificate-authority.pem client-certificate.pem client-key.pem
}