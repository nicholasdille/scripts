github_latest_release() {
    curl --silent https://api.github.com/repos/moby/buildkit/releases/latest | \
        jq --raw-output '.assets[] | select(.name | endswith(".linux-amd64.tar.gz")) | .browser_download_url' | \
        xargs curl --silent --location --fail | \
        tar -xvzC /usr/local/
}