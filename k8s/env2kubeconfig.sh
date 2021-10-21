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