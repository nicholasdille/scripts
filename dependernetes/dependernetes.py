import sys
import argparse
import logging

parser = argparse.ArgumentParser(prog="cve", description='Process CVEs', formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("--namespace", "-n",                      required=False, help="Process one specific namespace")
parser.add_argument("--dot",       "-d",                      required=False, help="Write DOT to file")
parser.add_argument("--svg",       "-s",                      required=False, help="Write SVG to file")
parser.add_argument("--quiet",     "-q", action="store_true", required=False, help="Supress text output")
args = parser.parse_args()

from kubernetes import config, client
import pydot

log_level = "INFO"
if args.quiet is not None:
    log_level = "WARNING"
logging.basicConfig(level=log_level)

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
    logging.error("Failed to read kube config and communicate with API")
    raise RuntimeError(e)

if args.namespace is not None:
    namespace = args.namespace

try:
    pod_list = v1.list_namespaced_pod(namespace)
    service_list = v1.list_namespaced_service(namespace)
    #endpoint_list = v1.list_namespaced_endpoints(namespace)
    #endpoint_slice_list = discoveryV1beta1Api.list_namespaced_endpoint_slice(namespace)
    role_binding_list = rbacAuthorizationV1Api.list_namespaced_role_binding(namespace)
    ingressroute_list = customObjectApi.list_namespaced_custom_object("traefik.containo.us", "v1alpha1", namespace, "ingressroutes")
    dnsendpoint_list = customObjectApi.list_namespaced_custom_object("externaldns.k8s.io", "v1alpha1", namespace, "dnsendpoints")
    certificate_list = customObjectApi.list_namespaced_custom_object("cert-manager.io", "v1", namespace, "certificates")
    certificate_request_list = customObjectApi.list_namespaced_custom_object("cert-manager.io", "v1", namespace, "certificaterequests")
    cluster_role_binding_list = rbacAuthorizationV1Api.list_cluster_role_binding(watch=False)
except Exception as e:
    logging.error("Not able to reach Kubernetes cluster check Kubeconfig")
    raise RuntimeError(e)

graph = pydot.Dot("dependernetes", graph_type="digraph", strict=True)

def process_owner(kind, name, namespace, object, indentation):
    if type(object) is dict:
        if "ownerReferences" in object["metadata"]:
            for owner in object["metadata"]["ownerReferences"]:
                logging.info(f'{" " * indentation}Owned by {owner["kind"]} {object["metadata"]["namespace"]}/{owner["name"]}')
                graph.add_node(pydot.Node(f'{owner["kind"]} {object["metadata"]["namespace"]}/{owner["name"]}', shape="box"))
                graph.add_edge(pydot.Edge(f'{owner["kind"]} {object["metadata"]["namespace"]}/{owner["name"]}', f'{kind} {namespace}/{name}'))
                resolve_owner(owner["kind"], owner["name"], object["metadata"]["namespace"], indentation + 2)
    else:
        if hasattr(object.metadata, "owner_references") and object.metadata.owner_references is not None:
            for owner in object.metadata.owner_references:
                logging.info(f'{" " * indentation}Owned by {owner.kind}/{owner.name}')
                graph.add_node(pydot.Node(f'{owner.kind} {namespace}/{owner.name}', shape="box"))
                graph.add_edge(pydot.Edge(f'{owner.kind} {namespace}/{owner.name}', f'{kind} {namespace}/{name}'))
                resolve_owner(owner.kind, owner.name, object.metadata.namespace, indentation + 2)

def resolve_owner(kind, name, namespace, indentation=2):
    try:
        if kind.lower() == "pod":
            object = v1.read_namespaced_pod(name, namespace)

        elif kind.lower() == "replicaset":
            object = appsV1Api.read_namespaced_replica_set(name, namespace)

        elif kind.lower() == "deployment":
            object = appsV1Api.read_namespaced_deployment(name, namespace)

        elif kind.lower() == "statefulset":
            object = appsV1Api.read_namespaced_stateful_set(name, namespace)

        elif kind.lower() == "daemonset":
            object = appsV1Api.read_namespaced_daemon_set(name, namespace)

        elif kind.lower() == "job":
            object = batchV1Api.read_namespaced_job(name, namespace)

        elif kind.lower() == "cronjob":
            object = batchV1beta1Api.read_namespaced_cron_job(name, namespace)

        elif kind.lower() == "prometheus":
            object = customObjectApi.get_namespaced_custom_object("monitoring.coreos.com", "v1", namespace, "prometheuses", name)

        elif kind.lower() == "certificaterequest":
            object = customObjectApi.get_namespaced_custom_object("cert-manager.io", "v1", namespace, "certificaterequests", name)

        elif kind.lower() == "certificate":
            object = customObjectApi.get_namespaced_custom_object("cert-manager.io", "v1", namespace, "certificates", name)

        else:
            logging.error(f'Unknown kind {kind}')
            sys.exit(1)

        process_owner(kind, name, namespace, object, indentation)

    except:
        logging.error(f'Unable to retrieve object for {kind} {namespace}/{name}.')

def process_container(pod, container):
    if container.env is not None:
        for env in container.env:
            if env.value_from is not None:
                if env.value_from.secret_key_ref is not None:
                    logging.info(f'    Env value from Secret {env.value_from.secret_key_ref.name}')
                    graph.add_node(pydot.Node(f'Secret {pod.metadata.namespace}/{env.value_from.secret_key_ref.name}', shape="note"))
                    graph.add_edge(pydot.Edge(f'Pod {pod.metadata.namespace}/{pod.metadata.name}', f'Secret {pod.metadata.namespace}/{env.value_from.secret_key_ref.name}'))
                elif env.value_from.config_map_key_ref is not None:
                    logging.info(f'    Env value from ConfigMap {env.value_from.config_map_key_ref.name}')
                    graph.add_node(pydot.Node(f'ConfigMap {pod.metadata.namespace}/{env.value_from.config_map_key_ref.name}', shape="note"))
                    graph.add_edge(pydot.Edge(f'Pod {pod.metadata.namespace}/{pod.metadata.name}', f'ConfigMap {pod.metadata.namespace}/{env.value_from.config_map_key_ref.name}'))

    if container.env_from is not None:
        for env_from in container.env_from:
            if env_from.secret_ref is not None:
                logging.info(f'    Env from Secret {env_from.secret_ref}')
                graph.add_node(pydot.Node(f'Secret {pod.metadata.namespace}/{env_from.secret_ref}', shape="note"))
                graph.add_edge(pydot.Edge(f'Pod {pod.metadata.namespace}/{pod.metadata.name}', f'Secret {pod.metadata.namespace}/{env_from.secret_ref}'))
            elif env_from.config_map_ref:
                logging.info(f'    Env from ConfigMap {env_from.config_map_ref}')
                graph.add_node(pydot.Node(f'ConfigMap {pod.metadata.namespace}/{env_from.config_map_ref}', shape="note"))
                graph.add_edge(pydot.Edge(f'Pod {pod.metadata.namespace}/{pod.metadata.name}', f'ConfigMap {pod.metadata.namespace}/{env_from.config_map_ref}'))

for pod in pod_list.items:
    logging.info(f'Pod {pod.metadata.namespace}/{pod.metadata.name}:')
    graph.add_node(pydot.Node(f'Pod {pod.metadata.namespace}/{pod.metadata.name}', shape="box3d"))

    resolve_owner("Pod", pod.metadata.name, pod.metadata.namespace)

    if pod.spec.init_containers is not None:
        init_containers = pod.spec.init_containers
        for init_container in init_containers:
            logging.info(f'  InitContainer {init_container.name}')
            process_container(pod, init_container)

    containers = pod.spec.containers
    for container in containers:
        logging.info(f'  Container {container.name}')
        process_container(pod, container)        

    if pod.spec.image_pull_secrets is not None:
        for secret in pod.spec.image_pull_secrets:
            logging.info(f'    Secret {pod.metadata.namespace}/{secret.name}')
            graph.add_node(pydot.Node(f'Secret {pod.metadata.namespace}/{secret.name}', shape="note"))
            graph.add_edge(pydot.Edge(f'Pod {pod.metadata.namespace}/{pod.metadata.name}', f'Secret {pod.metadata.namespace}/{secret.name}'))

    if pod.spec.volumes is not None:
        for volume in pod.spec.volumes:
            if volume.secret is not None:
                logging.info(f'    Volume from Secret {volume.secret.secret_name}')
                graph.add_node(pydot.Node(f'Secret {pod.metadata.namespace}/{volume.secret.secret_name}', shape="note"))
                graph.add_edge(pydot.Edge(f'Pod {pod.metadata.namespace}/{pod.metadata.name}', f'Secret {pod.metadata.namespace}/{volume.secret.secret_name}'))
            elif volume.config_map is not None:
                logging.info(f'    Volume from ConfigMap {volume.config_map.name}')
                graph.add_node(pydot.Node(f'ConfigMap {pod.metadata.namespace}/{volume.config_map.name}', shape="note"))
                graph.add_edge(pydot.Edge(f'Pod {pod.metadata.namespace}/{pod.metadata.name}', f'ConfigMap {pod.metadata.namespace}/{volume.config_map.name}'))
            elif volume.persistent_volume_claim is not None:
                logging.info(f'    Volume from PVC {volume.persistent_volume_claim.claim_name}')
                graph.add_node(pydot.Node(f'PVC {pod.metadata.namespace}/{volume.persistent_volume_claim.claim_name}', shape="cylinder"))
                graph.add_edge(pydot.Edge(f'Pod {pod.metadata.namespace}/{pod.metadata.name}', f'PVC {pod.metadata.namespace}/{volume.persistent_volume_claim.claim_name}'))
                pvc = v1.read_namespaced_persistent_volume_claim(volume.persistent_volume_claim.claim_name, pod.metadata.namespace)
                logging.info(f'      PV {pvc.spec.volume_name}')
                graph.add_node(pydot.Node(f'PV {pvc.spec.volume_name}', shape="cylinder"))
                graph.add_edge(pydot.Edge(f'PVC {pod.metadata.namespace}/{volume.persistent_volume_claim.claim_name}', f'PV {pvc.spec.volume_name}'))
    
    if pod.spec.service_account_name is not None:
        logging.info(f'    ServiceAccount {pod.spec.service_account_name}')
        graph.add_node(pydot.Node(f'ServiceAccount {pod.metadata.namespace}/{pod.spec.service_account_name}'))
        graph.add_edge(pydot.Edge(f'Pod {pod.metadata.namespace}/{pod.metadata.name}', f'ServiceAccount {pod.metadata.namespace}/{pod.spec.service_account_name}'))
        for role_binding in role_binding_list.items:
            for subject in role_binding.subjects:
                if subject.kind == "ServiceAccount" and subject.name == pod.spec.service_account_name:
                    logging.info(f'      RoleBinding {role_binding.metadata.name}')
                    graph.add_node(pydot.Node(f'RoleBinding {pod.metadata.namespace}/{role_binding.metadata.name}'))
                    graph.add_edge(pydot.Edge(f'RoleBinding {pod.metadata.namespace}/{role_binding.metadata.name}', f'ServiceAccount {pod.metadata.namespace}{pod.spec.service_account_name}'))
                    logging.info(f'        {role_binding.role_ref.kind} {role_binding.role_ref.name}')
                    graph.add_node(pydot.Node(f'{role_binding.role_ref.kind} {role_binding.role_ref.name}'))
                    graph.add_edge(pydot.Edge(f'RoleBinding {pod.metadata.namespace}/{role_binding.metadata.name}', f'{role_binding.role_ref.kind} {role_binding.role_ref.name}'))
        for cluster_role_binding in role_binding_list.items:
            for subject in cluster_role_binding.subjects:
                if subject.kind == "ServiceAccount" and subject.namespace == pod.metadata.namespace and subject.name == pod.spec.service_account_name:
                    logging.info(f'      ClusterRoleBinding {cluster_role_binding.metadata.name}')
                    graph.add_node(pydot.Node(f'ClusterRoleBinding {cluster_role_binding.metadata.name}'))
                    graph.add_edge(pydot.Edge(f'ClusterRoleBinding {cluster_role_binding.metadata.name}', f'ServiceAccount {pod.metadata.namespace}{pod.spec.service_account_name}'))
                    logging.info(f'        {cluster_role_binding.role_ref.kind} {cluster_role_binding.role_ref.name}')
                    graph.add_node(pydot.Node(f'{cluster_role_binding.role_ref.kind} {cluster_role_binding.role_ref.name}'))
                    role_name = {cluster_role_binding.role_ref.name}
                    if cluster_role_binding.role_ref.kind == "Role":
                        role_name = f'{cluster_role_binding.role_ref.kind}/{role_name}'
                    graph.add_edge(pydot.Edge(f'ClusterRoleBinding {role_binding.metadata.name}', f'{cluster_role_binding.role_ref.kind} {role_name}'))

# TODO: Improve by using endpoint slices (https://github.com/kubernetes-client/python/blob/master/kubernetes/docs/DiscoveryV1beta1Api.md)
for service in service_list.items:
    if service.spec.external_name is None:
        logging.info(f'Service {service.metadata.namespace}/{service.metadata.name}:')
        graph.add_node(pydot.Node(f'Service {service.metadata.namespace}/{service.metadata.name}'))

        endpoint = v1.read_namespaced_endpoints(service.metadata.name, service.metadata.namespace)
        logging.info(f'  Endpoint {endpoint.metadata.namespace}/{endpoint.metadata.name}')
        graph.add_node(pydot.Node(f'Endpoint {endpoint.metadata.namespace}/{endpoint.metadata.name}'))
        graph.add_edge(pydot.Edge(f'Service {service.metadata.namespace}/{service.metadata.name}', f'Endpoint {endpoint.metadata.namespace}/{endpoint.metadata.name}'))
        if endpoint.subsets is not None:
            for subset in endpoint.subsets:
                for address in subset.addresses:
                    if address.target_ref is not None:
                        logging.info(f'    {address.target_ref.kind} {address.target_ref.namespace}/{address.target_ref.name}')
                        graph.add_node(pydot.Node(f'{address.target_ref.kind} {address.target_ref.namespace}/{address.target_ref.name}'))
                        graph.add_edge(pydot.Edge(f'Endpoint {endpoint.metadata.namespace}/{endpoint.metadata.name}', f'{address.target_ref.kind} {address.target_ref.namespace}/{address.target_ref.name}'))

if ingressroute_list is not None:
    for ingressroute in ingressroute_list["items"]:
        logging.info(f'IngressRoute {ingressroute["metadata"]["name"]}:')
        graph.add_node(pydot.Node(f'IngressRoute {ingressroute["metadata"]["namespace"]}/{ingressroute["metadata"]["name"]}', shape="invhouse"))
        if "tls" in ingressroute["spec"] and "secretName" in ingressroute["spec"]["tls"]:
            logging.info(f'  Secret {ingressroute["spec"]["tls"]["secretName"]}')
            graph.add_node(pydot.Node(f'Secret {ingressroute["metadata"]["namespace"]}/{ingressroute["spec"]["tls"]["secretName"]}', shape="note"))
            graph.add_edge(pydot.Edge(f'IngressRoute {ingressroute["metadata"]["namespace"]}/{ingressroute["metadata"]["name"]}', f'Secret {ingressroute["metadata"]["namespace"]}/{ingressroute["spec"]["tls"]["secretName"]}'))
        for route in ingressroute["spec"]["routes"]:
            if "services" in route:
                for service in route["services"]:
                    logging.info(f'  Service {ingressroute["metadata"]["namespace"]}/{service["name"]}')
                    graph.add_node(pydot.Node(f'Service {ingressroute["metadata"]["namespace"]}/{service["name"]}'))
                    graph.add_edge(pydot.Edge(f'IngressRoute {ingressroute["metadata"]["namespace"]}/{ingressroute["metadata"]["name"]}', f'Service {ingressroute["metadata"]["namespace"]}/{service["name"]}'))
            if "middlewares" in route:
                for middleware in route["middlewares"]:
                    logging.info(f'  Middleware {ingressroute["metadata"]["namespace"]}/{middleware["name"]}')
                    graph.add_node(pydot.Node(f'Middleware {ingressroute["metadata"]["namespace"]}/{middleware["name"]}', shape="tab"))
                    graph.add_edge(pydot.Edge(f'IngressRoute {ingressroute["metadata"]["namespace"]}/{ingressroute["metadata"]["name"]}', f'Middleware {ingressroute["metadata"]["namespace"]}/{middleware["name"]}'))

if dnsendpoint_list is not None:
    for dnsendpoint in dnsendpoint_list["items"]:
        logging.info(f'DNSEndpoint {dnsendpoint["metadata"]["name"]}')
        graph.add_node(pydot.Node(f'DNSEndpoint {dnsendpoint["metadata"]["namespace"]}/{dnsendpoint["metadata"]["name"]}', shape="hexagon"))

if certificate_list is not None:
    for certificate in certificate_list["items"]:
        logging.info(f'Certificate {certificate["metadata"]["name"]}:')
        graph.add_node(pydot.Node(f'Certificate {certificate["metadata"]["namespace"]}/{certificate["metadata"]["name"]}'))
        logging.info(f'  {certificate["spec"]["issuerRef"]["kind"]} {certificate["spec"]["issuerRef"]["name"]}')
        issuer_name = certificate["spec"]["issuerRef"]["name"]
        if certificate["spec"]["issuerRef"]["kind"] == "Issuer":
            issuer_name = f'{certificate["metadata"]["namespace"]}/{issuer_name}'
        graph.add_node(pydot.Node(f'{certificate["spec"]["issuerRef"]["kind"]} {issuer_name}', shape="house"))
        graph.add_edge(pydot.Edge(f'Certificate {certificate["metadata"]["namespace"]}/{certificate["metadata"]["name"]}', f'{certificate["spec"]["issuerRef"]["kind"]} {certificate["spec"]["issuerRef"]["name"]}'))
        logging.info(f'  Secret {certificate["spec"]["secretName"]}')
        graph.add_node(pydot.Node(f'Secret {certificate["metadata"]["namespace"]}/{certificate["spec"]["secretName"]}', shape="note"))
        graph.add_edge(pydot.Edge(f'Certificate {certificate["metadata"]["namespace"]}/{certificate["metadata"]["name"]}', f'Secret {certificate["metadata"]["namespace"]}/{certificate["spec"]["secretName"]}'))
if certificate_request_list is not None:
    for certificate_request in certificate_request_list["items"]:
        logging.info(f'CertificateRequest {certificate_request["metadata"]["namespace"]}/{certificate_request["metadata"]["name"]}')
        resolve_owner("CertificateRequest", certificate_request["metadata"]["name"], certificate_request["metadata"]["namespace"])

# TODO: Ingress
# TODO: prometheus-operator
# TODO: Prometheus
# TODO: ServiceMonitor/PodMonitor

if args.dot is not None:
    graph.write_dot(args.dot)
if args.svg is not None:
    graph.write_svg(args.svg)
