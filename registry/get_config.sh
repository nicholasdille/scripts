get_config() {
    curl \
        -sL \
        -H "Accept: application/vnd.docker.container.image.v1+json" \
        http://localhost:5000/v2/hello-world-java/manifests/latest \
    | jq
}