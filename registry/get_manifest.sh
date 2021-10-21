get_manifest() {
    curl \
        -sL \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        http://localhost:5000/v2/hello-world-java/manifests/latest \
    | jq
}