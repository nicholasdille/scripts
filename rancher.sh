rancher2ssh() {
    # saner programming env: these switches turn some bugs into errors
    set -o errexit -o pipefail -o noclobber -o nounset

    ! getopt --test > /dev/null 
    if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
        echo 'I’m sorry, `getopt --test` failed in this environment.'
        exit 2
    fi

    OPTIONS=vu:k:
    LONGOPTS=verbose,user:,key:

    # -use ! and PIPESTATUS to get exit code with errexit set
    # -temporarily store output to be able to check for errors
    # -activate quoting/enhanced mode (e.g. by writing out “--options”)
    # -pass arguments only via   -- "$@"   to separate them correctly
    ! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo "Error specifying command line options to getopts."
        echo "  OPTIONS : ${OPTIONS}"
        echo "  LONGOPTS: ${LONGOPTS}"
        exit 3
    fi
    # read getopt’s output this way to handle the quoting right:
    eval set -- "$PARSED"

    VERBOSE=false
    SSH_USER=""
    SSH_KEY=""

    # now enjoy the options in order and nicely split until we see --
    while true; do
        case "$1" in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -u|--user)
                SSH_USER="$2"
                shift 2
                ;;
            -k|--key)
                SSH_KEY="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Unhandled argument encountered: $1"
                exit 3
                ;;
        esac
    done

    if [[ -z "${SSH_USER}" ]]; then
        echo "SSH user must be specified using -u|--user"
        exit 1
    fi

    rm -f ~/.ssh/config.d/rancher_*
    rancher hosts --format json | jq --raw-output '.Host | [.hostname,.agentIpAddress] | @csv' | tr -d '"' | while read LINE
    do
        SERVER_NAME=$(echo $LINE | cut -d, -f1 | cut -d. -f1)
        SERVER_IP=$(echo $LINE | cut -d, -f2)

        cat > ~/.ssh/config.d/rancher_${SERVER_NAME} <<EOF
Host ${SERVER_NAME} ${SERVER_IP}
    HostName ${SERVER_IP}
    User ${SSH_USER}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

        if [[ -n "${SSH_KEY}" ]]; then
            echo "    IdentityFile ${SSH_KEY}" >> ~/.ssh/config.d/rancher_${SERVER_NAME}
        fi

        chmod 0640 ~/.ssh/config.d/rancher_${SERVER_NAME}
    done
}