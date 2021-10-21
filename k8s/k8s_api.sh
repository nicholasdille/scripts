k8s_api() {
    local request=$1
    : "${request:=/}"

    curl --header "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}${request}
}