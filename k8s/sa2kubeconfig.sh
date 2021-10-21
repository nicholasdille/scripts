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