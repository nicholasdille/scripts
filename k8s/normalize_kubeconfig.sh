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