get_layer() {
    DIGEST=$(
        curl \
            -sL \
            -H "Accept: application/vnd.docker.container.image.v1+json" \
            http://localhost:5000/v2/hello-world-java/manifests/latest \
        | jq --raw-output '.layers[-1].digest'
    )

    curl \
        -sL \
        -H "Accept: application/vnd.docker.image.rootfs.diff.tar.gzip" \
        http://localhost:5000/v2/hello-world-java/blobs/${DIGEST} \
    | tar -tvz
}