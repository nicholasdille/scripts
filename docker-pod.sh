#!/bin/bash

set -o errexit

pod_create() {
    local pod_name=$1
    shift

    if test "$#" -gt 0; then
        echo "Usage: $0 create ${pod_name}"
    fi

    docker run -d --name pod_${pod_name}_sleeper ubuntu bash -c 'sleep infinity'
}

pod_add() {
    local pod_name=$1
    shift
    local container_name=$1
    shift

    if test "$#" -eq 0; then
        echo "Usage: $0 add ${pod_name} ${container_name} [<options>]"
    fi

    docker run -d --name pod_${pod_name}_${container_name} --network container:pod_${pod_name}_sleeper --pid container:pod_${pod_name}_sleeper "$@"
}

pod_remove() {
    local pod_name=$1
    shift
    local container_name=$1
    shift

    if test "$#" -gt 0; then
        echo "Usage: $0 remove ${pod_name} ${container_name}"
    fi

    docker rm -f pod_${pod_name}_${container_name}
}

pod_delete() {
    local pod_name=$1
    shift

    if test "$#" -gt 0; then
        echo "Usage: $0 create ${pod_name}"
    fi

    docker ps --filter name=pod_${pod_name} --all --quiet | xargs docker container rm --force
}

pod_list() {
    local pod_name=$1
    shift

    if test "$#" -gt 0; then
        echo "Usage: $0 list ${pod_name}"
    fi

    docker ps --filter name=pod_${pod_name} --all
}

pod_logs() {
    local pod_name=$1
    shift
    local container_name=$1
    shift

    if test "$#" -eq 0; then
        echo "Usage: $0 logs ${pod_name} ${container_name} [<options>]"
    fi

    docker logs pod_${pod_name}_${container_name}
}

pod_exec() {
    local pod_name=$1
    shift

    if test "$#" -gt 0; then
        echo "Usage: $0 exec ${pod_name}"
    fi

    docker exec -it pod_${pod_name}_${container_name} "$@"
}

pod_run() {
    local pod_name=$1
    shift
    local container_name=$1
    shift

    if test "$#" -eq 0; then
        echo "Usage: $0 run ${pod_name} ${container_name} [<options>]"
    fi

    docker run -it --rm --name pod_${pod_name}_${container_name} --network container:pod_${pod_name}_sleeper --pid container:pod_${pod_name}_sleeper "$@"
}

verb=$1
shift

case "${verb}" in
    example)
        cat <<EOF
Example 1:
$0 create test
$0 add test registry registry:2
$0 add test dind --privileged docker:stable-dind dockerd --host=tcp://localhost:2375
$0 run test console docker:stable sh

Example 2:
$0 create test
$0 add test registry --env REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io --env REGISTRY_PROXY_USERNAME=nicholasdille --env REGISTRY_PASSWORD=${PASS} registry:2
$0 add test dind --privileged docker:stable-dind dockerd --host=tcp://localhost:2375 --registry-mirror=http://localhost:5000
$0 exec test dind sh
EOF
    ;;
    help)
        cat <<EOF
Usage: $0 <command> <pod_name> [<container_name>] [<options>]

Supported commands:
    create    Create a new pod
    add       Add a new container to the pod
    remove    Remove a container from the pod
    delete    Remove the whole pod
    list      List containers in a pod
    logs      Display logs for a container in the pod
    exec      Enter an existing container to the pod
    run       Run an interactive container in the pod
EOF
    ;;
esac

pod_name=$1
shift

case "${verb}" in
    create)
        pod_create "${pod_name}"
    ;;
    add)
        if test "$#" -eq 0; then
            echo "Usage: $0 add ${pod_name} <container_name> [<options>]"
            exit 1
        fi
        container_name=$1
        shift
        pod_add "${pod_name}" "${container_name}" "$@"
    ;;
    remove)
        container_name=$1
        shift
        pod_remove "${pod_name}" "${container_name}"
    ;;
    delete)
        pod_delete "${pod_name}"
    ;;
    list)
        pod_list "${pod_name}"
    ;;
    logs)
        container_name=$1
        shift
        pod_logs "${pod_name}" "${container_name}"
    ;;
    exec)
        if test "$#" -eq 0; then
            echo "Usage: $0 add ${pod_name} <container_name> [<options>]"
            exit 1
        fi
        container_name=$1
        shift
        pod_exec "${pod_name}" "${container_name}" "$@"
    ;;
    run)
        if test "$#" -eq 0; then
            echo "Usage: $0 run ${pod_name} <container_name> [<options>]"
            exit 1
        fi
        container_name=$1
        shift
        pod_run "${pod_name}" "${container_name}" "$@"
    ;;
    *)
        echo "Unknown verb <${verb}>"
        exit 1
    ;;
esac