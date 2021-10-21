tag_remote() {
    # Download manifest from old name
    MANIFEST=$(curl --silent --location \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        localhost:5000/v2/hello-world-java/manifests/latest
    )

    # Push manifest with new name
    curl --request PUT \
        -H "Content-Type: application/vnd.docker.distribution.manifest.v2+json" \
        -d "${MANIFEST}" \
        localhost:5000/v2/hello-world-java/manifests/new
}