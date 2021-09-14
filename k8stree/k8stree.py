import argparse

parser = argparse.ArgumentParser(prog="cve", description='Process CVEs', formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("--all-namespaces", "-A", action="store_true", required=False, help="Process all namespaces")
parser.add_argument("--namespace",      "-n",                      required=False, help="Process one specific namespace")
args = parser.parse_args()

from kubernetes import config, client
import pydot

try:
    config.load_kube_config()
    namespace = config.list_kube_config_contexts()[1]["context"]["namespace"] or "default"
    v1 = client.CoreV1Api()
    v1beta1Api = client.ExtensionsV1beta1Api()
    appsV1Api = client.AppsV1Api()
    batchV1Api = client.BatchV1Api()
    batchV1beta1Api = client.BatchV1beta1Api()
    rbacAuthorizationV1Api = client.RbacAuthorizationV1Api()
    #discoveryV1beta1Api = client.DiscoveryV1beta1Api()
    customObjectApi = client.CustomObjectsApi()
except Exception as e:
    print("Failed to read kube config and communicate with API")
    raise RuntimeError(e)

if args.namespace is not None:
    namespace = args.namespace

try:
    if args.all_namespaces:
        pod_list = v1.list_pod_for_all_namespaces(watch=False)
        service_list = v1.list_service_for_all_namespaces(watch=False)
        #endpoint_list = v1.list_endpoints_for_all_namespaces(watch=False)
        #endpoint_slice_list = discoveryV1beta1Api.list_endpoint_slice_for_all_namespaces(watch=False)
        role_binding_list = rbacAuthorizationV1Api.list_role_binding_for_all_namespaces(watch=False)
        print("Warning: Will not be able to enumerate custom objects on all namespaces")
    else:
        pod_list = v1.list_namespaced_pod(namespace)
        service_list = v1.list_namespaced_service(namespace)
        #endpoint_list = v1.list_namespaced_endpoints(namespace)
        #endpoint_slice_list = discoveryV1beta1Api.list_namespaced_endpoint_slice(namespace)
        role_binding_list = rbacAuthorizationV1Api.list_namespaced_role_binding(namespace)
        ingressroute_list = customObjectApi.list_namespaced_custom_object("traefik.containo.us", "v1alpha1", namespace, "ingressroutes")
        dnsendpoint_list = customObjectApi.list_namespaced_custom_object("externaldns.k8s.io", "v1alpha1", namespace, "dnsendpoints")
        certificate_list = customObjectApi.list_namespaced_custom_object("cert-manager.io", "v1", namespace, "certificates")
    cluster_role_binding_list = rbacAuthorizationV1Api.list_cluster_role_binding(watch=False)
except Exception as e:
    print("Not able to reach Kubernetes cluster check Kubeconfig")
    raise RuntimeError(e)

graph = pydot.Dot("k8stree", graph_type="digraph")

owner_queue = []

for pod in pod_list.items:
    print(f'Pod {pod.metadata.namespace}/{pod.metadata.name}:')
    graph.add_node(pydot.Node(f'Pod {pod.metadata.namespace}/{pod.metadata.name}'))

    if pod.metadata.owner_references is not None:
        # TODO: Get owner references recursively
        for owner in pod.metadata.owner_references:
            print(f'  Owned by {owner.kind}/{owner.name}')
            owner_queue.append({"kind": owner.kind, "name": owner.name, "namespace": pod.metadata.namespace})

    # TODO: initContainers = pod.spec.initContainers

    containers = pod.spec.containers
    for container in containers:
        print(f'  Container {container.name}')

        # TODO: Factor out into function
        if container.env is not None:
            for env in container.env:
                if env.value_from is not None:
                    if env.value_from.secret_key_ref is not None:
                        print(f'    Env value from Secret {env.value_from.secret_key_ref.name}')
                        graph.add_node(pydot.Node(f'Secret {env.value_from.secret_key_ref.name}'))
                        graph.add_edge(pydot.Edge(f'Pod {pod.metadata.namespace}/{pod.metadata.name}', f'Secret {env.value_from.secret_key_ref.name}'))
                    elif env.value_from.config_map_key_ref is not None:
                        print(f'    Env value from ConfigMap {env.value_from.config_map_key_ref.name}')
                        graph.add_node(pydot.Node(f'ConfigMap {env.value_from.config_map_key_ref.name}'))
                        graph.add_edge(pydot.Edge(f'Pod {pod.metadata.namespace}/{pod.metadata.name}', f'ConfigMap {env.value_from.config_map_key_ref.name}'))

        # TODO: Factor out into function
        if container.env_from is not None:
            for env_from in container.env_from:
                if env_from.secret_ref is not None:
                    print(f'    Env from Secret {env_from.secret_ref}')
                    graph.add_node(pydot.Node(f'Secret {env_from.secret_ref}'))
                    graph.add_edge(pydot.Edge(f'Pod {pod.metadata.namespace}/{pod.metadata.name}', f'Secret {env_from.secret_ref}'))
                elif env_from.config_map_ref:
                    print(f'    Env from ConfigMap {env_from.config_map_ref}')
                    graph.add_node(pydot.Node(f'ConfigMap {env_from.config_map_ref}'))
                    graph.add_edge(pydot.Edge(f'Pod {pod.metadata.namespace}/{pod.metadata.name}', f'ConfigMap {env_from.config_map_ref}'))

    # TODO: Factor out into function
    if pod.spec.volumes is not None:
        for volume in pod.spec.volumes:
            if volume.secret is not None:
                print(f'    Volume from Secret {volume.secret.secret_name}')
                graph.add_node(pydot.Node(f'Secret {volume.secret.secret_name}'))
                graph.add_edge(pydot.Edge(f'Pod {pod.metadata.namespace}/{pod.metadata.name}', f'Secret {volume.secret.secret_name}'))
            elif volume.config_map is not None:
                print(f'    Volume from ConfigMap {volume.config_map.name}')
                graph.add_node(pydot.Node(f'ConfigMap {volume.config_map.name}'))
                graph.add_edge(pydot.Edge(f'Pod {pod.metadata.namespace}/{pod.metadata.name}', f'ConfigMap {volume.config_map.name}'))
            elif volume.persistent_volume_claim is not None:
                print(f'    Volume from PVC {volume.persistent_volume_claim.claim_name}')
                graph.add_node(pydot.Node(f'PVC {volume.persistent_volume_claim.claim_name}'))
                graph.add_edge(pydot.Edge(f'Pod {pod.metadata.namespace}/{pod.metadata.name}', f'PVC {volume.persistent_volume_claim.claim_name}'))
                pvc = v1.read_namespaced_persistent_volume_claim(volume.persistent_volume_claim.claim_name, pod.metadata.namespace)
                print(f'      PV {pvc.spec.volume_name}')
                graph.add_node(pydot.Node(f'PV {pvc.spec.volume_name}'))
                graph.add_edge(pydot.Edge(f'PVC {volume.persistent_volume_claim.claim_name}', f'PV {pvc.spec.volume_name}'))
    
    if pod.spec.service_account_name is not None:
        print(f'    ServiceAccount {pod.spec.service_account_name}')
        graph.add_node(pydot.Node(f'ServiceAccount {pod.spec.service_account_name}'))
        graph.add_edge(pydot.Edge(f'Pod {pod.metadata.namespace}/{pod.metadata.name}', f'ServiceAccount {pod.spec.service_account_name}'))
        for role_binding in role_binding_list.items:
            for subject in role_binding.subjects:
                if subject.kind == "ServiceAccount" and subject.name == pod.spec.service_account_name:
                    print(f'      RoleBinding {role_binding.metadata.name}')
                    graph.add_node(pydot.Node(f'RoleBinding {role_binding.metadata.name}'))
                    graph.add_edge(pydot.Edge(f'RoleBinding {role_binding.metadata.name}', f'ServiceAccount {pod.spec.service_account_name}'))
                    print(f'        {role_binding.role_ref.kind} {role_binding.role_ref.name}')
                    graph.add_node(pydot.Node(f'{role_binding.role_ref.kind} {role_binding.role_ref.name}'))
                    graph.add_edge(pydot.Edge(f'RoleBinding {role_binding.metadata.name}', f'{role_binding.role_ref.kind} {role_binding.role_ref.name}'))
        for cluster_role_binding in role_binding_list.items:
            for subject in cluster_role_binding.subjects:
                if subject.kind == "ServiceAccount" and subject.namespace == pod.metadata.namespace and subject.name == pod.spec.service_account_name:
                    print(f'      ClusterRoleBinding {cluster_role_binding.metadata.name}')
                    graph.add_node(pydot.Node(f'ClusterRoleBinding {cluster_role_binding.metadata.name}'))
                    graph.add_edge(pydot.Edge(f'ClusterRoleBinding {cluster_role_binding.metadata.name}', f'ServiceAccount {pod.spec.service_account_name}'))
                    print(f'        {cluster_role_binding.role_ref.kind} {cluster_role_binding.role_ref.name}')
                    graph.add_node(pydot.Node(f'{cluster_role_binding.role_ref.kind} {cluster_role_binding.role_ref.name}'))
                    graph.add_edge(pydot.Edge(f'RoleBinding {role_binding.metadata.name}', f'{cluster_role_binding.role_ref.kind} {cluster_role_binding.role_ref.name}'))

# TODO: Improve by using endpoint slices (https://github.com/kubernetes-client/python/blob/master/kubernetes/docs/DiscoveryV1beta1Api.md)
for service in service_list.items:
    if service.spec.external_name is None:
        print(f'Service {service.metadata.namespace}/{service.metadata.name}:')
        graph.add_node(pydot.Node(f'Service {service.metadata.namespace}/{service.metadata.name}'))

        endpoint = v1.read_namespaced_endpoints(service.metadata.name, service.metadata.namespace)
        if endpoint.subsets is not None:
            for subset in endpoint.subsets:
                for address in subset.addresses:
                    print(f'  {address.target_ref.kind} {address.target_ref.namespace}/{address.target_ref.name}')
                    graph.add_node(pydot.Node(f'{address.target_ref.kind} {address.target_ref.namespace}/{address.target_ref.name}'))
                    graph.add_edge(pydot.Edge(f'Service {service.metadata.namespace}/{service.metadata.name}', f'{address.target_ref.kind} {address.target_ref.namespace}/{address.target_ref.name}'))

for object in owner_queue:
    if object["kind"].lower() == "replicaset":
        replica_set = appsV1Api.read_namespaced_replica_set(object["name"], object["namespace"])
        if replica_set.metadata.owner_references is not None:
            print(f'Owner {object["kind"]}/{object["name"]}')
            # TODO: Factor out info function
            for owner in replica_set.metadata.owner_references:
                print(f'  Owned by {owner.kind}/{owner.name}')
                owner_queue.append({"kind": owner.kind, "name": owner.name, "namespace": pod.metadata.namespace})

    elif object["kind"].lower() == "job":
        job = batchV1Api.read_namespaced_job(object["name"], object["namespace"])
        if job.metadata.owner_references is not None:
            print(f'Owner {object["kind"]}/{object["name"]}')
            # TODO: Factor out info function
            for owner in job.metadata.owner_references:
                print(f'  Owned by {owner.kind}/{owner.name}')
                owner_queue.append({"kind": owner.kind, "name": owner.name, "namespace": pod.metadata.namespace})

    elif object["kind"].lower() == "cronjob":
        cronjob = batchV1beta1Api.read_namespaced_cron_job(object["name"], object["namespace"])
        if cronjob.metadata.owner_references is not None:
            print(f'Owner {object["kind"]}/{object["name"]}')
            # TODO: Factor out info function
            for owner in cronjob.metadata.owner_references:
                print(f'  Owned by {owner.kind}/{owner.name}')
                owner_queue.append({"kind": owner.kind, "name": owner.name, "namespace": pod.metadata.namespace})

    elif object["kind"].lower() == "statefulset":
        stateful_set = appsV1Api.read_namespaced_stateful_set(object["name"], object["namespace"])
        if stateful_set.metadata.owner_references is not None:
            print(f'Owner {object["kind"]}/{object["name"]}')
            # TODO: Factor out info function
            for owner in stateful_set.metadata.owner_references:
                print(f'  Owned by {owner.kind}/{owner.name}')

    elif object["kind"].lower() == "daemonset":
        daemon_set = appsV1Api.read_namespaced_daemon_set(object["name"], object["namespace"])
        if daemon_set.metadata.owner_references is not None:
            print(f'Owner {object["kind"]}/{object["name"]}')
            # TODO: Factor out info function
            for owner in daemon_set.metadata.owner_references:
                print(f'  Owned by {owner.kind}/{owner.name}')

    elif object["kind"].lower() == "deployment":
        deployment = appsV1Api.read_namespaced_deployment(object["name"], object["namespace"])
        if deployment.metadata.owner_references is not None:
            print(f'Owner {object["kind"]}/{object["name"]}')
            # TODO: Factor out info function
            for owner in deployment.metadata.owner_references:
                print(f'  Owned by {owner.kind}/{owner.name}')

    else:
        raise RuntimeError(f'Unknown kind {object["kind"]}')

# TODO: Ingress

if ingressroute_list is not None:
    for ingressroute in ingressroute_list["items"]:
        print(f'IngressRoute {ingressroute["metadata"]["name"]}:')
        graph.add_node(pydot.Node(f'IngressRoute {ingressroute["metadata"]["name"]}'))
        if "tls" in ingressroute["spec"] and "secretName" in ingressroute["spec"]["tls"]:
            print(f'  Secret {ingressroute["spec"]["tls"]["secretName"]}')
            graph.add_node(pydot.Node(f'Secret {ingressroute["spec"]["tls"]["secretName"]}'))
            graph.add_edge(pydot.Edge(f'IngressRoute {ingressroute["metadata"]["name"]}', f'Secret {ingressroute["spec"]["tls"]["secretName"]}'))
        for route in ingressroute["spec"]["routes"]:
            if "middlewares" in route:
                for middleware in route["middlewares"]:
                    print(f'  Middleware {middleware["name"]}')
                    graph.add_node(pydot.Node(f'Middleware {middleware["name"]}'))
                    graph.add_edge(pydot.Edge(f'IngressRoute {ingressroute["metadata"]["name"]}', f'Middleware {middleware["name"]}'))

if dnsendpoint_list is not None:
    for dnsendpoint in dnsendpoint_list["items"]:
        print(f'DNSEndpoint {dnsendpoint["metadata"]["name"]}')
        graph.add_node(pydot.Node(f'DNSEndpoint {dnsendpoint["metadata"]["name"]}'))

if certificate_list is not None:
    for certificate in certificate_list["items"]:
        print(f'Certificate {certificate["metadata"]["name"]}:')
        graph.add_node(pydot.Node(f'Certificate {certificate["metadata"]["name"]}'))
        print(f'  {certificate["spec"]["issuerRef"]["kind"]} {certificate["spec"]["issuerRef"]["name"]}')
        graph.add_node(pydot.Node(f'{certificate["spec"]["issuerRef"]["kind"]} {certificate["spec"]["issuerRef"]["name"]}'))
        graph.add_edge(pydot.Edge(f'Certificate {certificate["metadata"]["name"]}', f'{certificate["spec"]["issuerRef"]["kind"]} {certificate["spec"]["issuerRef"]["name"]}'))
        print(f'  Secret {certificate["spec"]["secretName"]}')
        graph.add_node(pydot.Node(f'Secret {certificate["spec"]["secretName"]}'))
        graph.add_edge(pydot.Edge(f'Certificate {certificate["metadata"]["name"]}', f'Secret {certificate["spec"]["secretName"]}'))

# TODO: prometheus-operator
# TODO: Prometheus
# TODO: ServiceMonitor/PodMonitor

graph.write_svg("k8stree.svg")
