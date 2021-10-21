# Description: Test if namespace exists
# Parameters : Namespace
# Returns    : 0 = false, 1 = true
# Example    : if ! test_namespace my_namespace; then echo PANIC; done
test_namespace() {
	local namespace=$1

	return $(( 1 - $(kubectl get namespace -o name | grep -cE "^namespace/${namespace}$") ))
}
alias test_ns=test_namespace

# Description: Test if serviceaccount exists
# Parameters : Namespace, serviceaccount
# Returns    : 0 = false, 1 = true
# Example    : if ! test_serviceaccount my_namespace my_sa; then echo PANIC; done
test_serviceaccount() {
	local namespace=$1
	local serviceaccount=$2

	if ! test_namespace "${namespace}"; then
		echo "ERROR: Namespace ${namespace} does not exist."
		return 1
	fi

	return $(( 1 - $(kubectl --namespace=${namespace} get serviceaccount -o name | grep -cE "^serviceaccount/${serviceaccount}$") ))
}
alias test_sa=test_serviceaccount

# Description: Get ClusterRoleBindings for a ServiceAccount
# Parameters : Namespace, serviceaccount
# Returns    : List of strings
# Example    : get_clusterroles_for_serviceaccount my_namespace my_sa
get_clusterroles_for_serviceaccount() {
	local namespace=$1
	local serviceaccount=$2

	if ! test_namespace "${namespace}"; then
		echo "ERROR: Namespace <${namespace}> does not exist."
		return 1
	fi
	if ! test_serviceaccount "${namespace}" "${serviceaccount}"; then
		echo "ERROR: ServiceAccount <${serviceaccount}> does not exist."
		return 1
	fi

	kubectl get clusterrolebindings -o json | \
		jq --raw-output \
			--arg namespace "${namespace}" \
			--arg serviceaccount "${serviceaccount}" \
			'
			.items[] |
			select(
				.subjects // [] | .[] |
				[.kind,.namespace,.name] == ["ServiceAccount",$namespace,$serviceaccount]
			) |
			.metadata.name
			'
}
alias get_clusterroles_for_sa=get_clusterroles_for_serviceaccount

# Description: Get RoleBindings for a ServiceAccount
# Parameters : Namespace, serviceaccount
# Returns    : List of strings
# Example    : get_roles_for_serviceaccount my_namespace my_sa
get_roles_for_serviceaccount() {
	local namespace=$1
	local serviceaccount=$2

	if ! test_namespace "${namespace}"; then
		echo "ERROR: Namespace <${namespace}> does not exist."
		return 1
	fi
	if ! test_serviceaccount "${namespace}" "${serviceaccount}"; then
		echo "ERROR: ServiceAccount <${serviceaccount}> does not exist."
		return 1
	fi

	kubectl --namespace=${namespace} get rolebindings -o json | \
		jq --raw-output \
			--arg namespace "${namespace}" \
			--arg serviceaccount "${serviceaccount}" \
			'
			.items[] |
			select(
				.subjects // [] | .[] |
				[.kind,.namespace,.name] == ["ServiceAccount",$namespace,$serviceaccount]
			) |
			.metadata.name
			'
}
alias get_roles_for_sa=get_roles_for_serviceaccount
alias get_sa_roles=get_roles_for_serviceaccount

# Description: Get the token for a ServiceAccount
# Parameters : Namespace, serviceaccount
# Returns    : String
# Example    : get_token_for_serviceaccount my_namespace my_sa
get_token_for_serviceaccount() {
	local namespace=$1
	local serviceaccount=$2

	if ! test_namespace "${namespace}"; then
		echo "ERROR: Namespace <${namespace}> does not exist."
		return 1
	fi
	if ! test_serviceaccount "${namespace}" "${serviceaccount}"; then
		echo "ERROR: ServiceAccount <${serviceaccount}> does not exist."
		return 1
	fi

	local secret=$(kubectl --namespace=${namespace} get serviceaccount ${serviceaccount} -o json | jq --raw-output .secrets[].name)
	local token=$(kubectl --namespace=${namespace} get secret ${secret} -o json | jq --raw-output .data.token | base64 -d)
	echo "${token}"
}
alias get_token_for_sa=get_token_for_serviceaccount
alias get_sa_token=get_token_for_serviceaccount

# Description: Get cluster name for a context from kubeconfig
# Parameters : Context
# Returns    : String
# Example    : get_cluster_name_from_context my_context
get_cluster_name_from_context() {
	local context=$1

	local cluster=$(kubectl config get-contexts --no-headers | tr -s ' ' | tr -d '*' | grep -E "^\s${context}\s" | cut -d' ' -f3)
	echo "${cluster}"
}

# Description: Get cluster name for the current context from kubeconfig
# Parameters : None
# Returns    : String
# Example    : get_cluster_name_from_current_context
get_cluster_name_from_current_context() {
	local context=$(kubectl config current-context)

	local cluster=$(get_cluster_name_from_context "${context}")
	echo "${cluster}"
}
alias get_cluster_name=get_cluster_name_from_current_context

# Description: Get api-server for a context from kubeconfig
# Parameters : Context
# Returns    : String
# Example    : get_apiserver_from_context my_context
get_apiserver_from_context() {
	local context=$1

	local cluster_name=$(get_cluster_name_from_context "${context}")

	local cluster=$(
		kubectl config view --raw -o json \
		| jq --raw-output --arg cluster_name "${cluster_name}" '
			.clusters[] | select(.name == $cluster_name) | .cluster.server
			'
	)
	echo "${cluster}"
}

# Description: Get api-server for the current context from kubeconfig
# Parameters : None
# Returns    : String
# Example    : get_apiserver_from_current_context
get_apiserver_from_current_context() {
	local context=$(kubectl config current-context)

	local cluster=$(get_apiserver_from_context "${context}")
	echo "${cluster}"
}
alias get_apiserver=get_apiserver_from_current_context

# Description: Get certificate for a context from kubeconfig
# Parameters : Context
# Returns    : String
# Example    : get_certificate_from_context my_context
get_certificate_from_context() {
	local context=$1

	local cluster_name=$(get_cluster_name_from_context "${context}")

	local certificate=$(
		kubectl config view --raw -o json \
		| jq --raw-output --arg cluster_name "${cluster_name}" '
			.clusters[] | select(.name == $cluster_name) | .cluster."certificate-authority-data"
			' \
		| base64 -d
	)
	echo "${certificate}"
}

# Description: Get certificate for the current context from kubeconfig
# Parameters : None
# Returns    : String
# Example    : get_certificate_from_current_context
get_certificate_from_current_context() {
	local context=$(kubectl config current-context)

	local certificate=$(get_certificate_from_context "${context}")
	echo "${certificate}"
}
alias get_certificate=get_certificate_from_current_context

# Description: Get user for a context from kubeconfig
# Parameters : Context
# Returns    : String
# Example    : get_user_from_context my_context
get_user_from_context() {
	local context=$1

	local user=$(
		kubectl config view --raw -o json \
		| jq --raw-output --arg context "${context}" '
			.contexts[] | select(.name == $context) | .context.user
			'
	)

	echo "${user}"
}

# Description: Get user for a context from kubeconfig
# Parameters : Context
# Returns    : String
# Example    : get_user_from_context
get_user_from_current_context() {
	local context=$(kubectl config current-context)

	local user=$(get_user_from_context "${context}")
	echo "${user}"
}
alias get_user=get_user_from_current_context

# Description: Get token for a user in a context from kubeconfig
# Parameters : Context
# Returns    : String
# Example    : get_user_from_context
get_token_for_context() {
	local context=$1

	local user=$(get_user_from_context "${context}")

	local token=$(
		kubectl config view --raw -o json \
		| jq --raw-output --arg user "${user}" '
			.users[] | select(.name == $user) | .user.token
			'
	)
	echo "${token}"
}

# Description: Get token for a user in the current context from kubeconfig
# Parameters : None
# Returns    : String
# Example    : get_user_from_current_context
get_token_for_current_context() {
	local context=$(kubectl config current-context)

	local token=$(get_token_for_context "$context")
	echo "${token}"
}

# Description: Add a new context using the server from the current context
# Parameters : Namespace, serviceaccount
# Example    : add_context my_namespace my_serviceaccount
add_context() {
	local namespace=$1
	local serviceaccount=$2

	local token=$(get_token_for_serviceaccount "${namespace}" "${serviceaccount}")
	kubectl config set-credentials "${namespace}-${serviceaccount}" --token=${token}

	local cluster=$(get_cluster_name_from_current_context)
	kubectl config set-context "${namespace}-${serviceaccount}" --cluster=${cluster} --namespace=${namespace} --user=${namespace}-${serviceaccount}
}

# Description: Get TokenReview for a token
# Parameters : Token
# Returns    : JSON
# Example    : get_tokenreview my_token
get_tokenreview() {
	#TODO: Test for proper token
	local token=$1

	local cluster=$(get_apiserver_from_current_context)
	local certificate=$(get_certificate_from_current_context)
	local auth_token=$(get_token_for_current_context)

	#TODO: Remove -k
	curl "${cluster}/apis/authentication.k8s.io/v1/tokenreviews" \
		--silent \
		--cacert <(printf "%s" "${certificate}") \
		--header "Authorization: Bearer ${auth_token}" \
		--header 'Content-Type: application/json; charset=utf-8' \
		--request POST \
		--data "{\"kind\":\"TokenReview\",\"apiVersion\":\"authentication.k8s.io/v1\",\"spec\":{\"token\":\"${token}\"}}"
}

# Description: Get the username for a token
# Parameters : Token
# Returns    : String
# Example    : get_username_from_token my_token
get_username_from_token() {
	#TODO: Check for proper token
	local token=$1

	get_tokenreview "${token}" | jq --raw-output '.status.user.username'
}

# Description: Get roles for the user in a context
# Parameters : Context
# Returns    : List of strings
# Example    : get_roles_from_context my_context
get_roles_from_context() {
	local context=$1
	local token=$(get_token_for_context "${context}")
	local username=$(get_username_from_token "${token}")
	local namespace=$(echo "${username}" | cut -d: -f3)
	local serviceaccount=$(echo "${username}" | cut -d: -f4)

	get_roles_for_serviceaccount "${namespace}" "${serviceaccount}"
}

# Description: Get roles for the user in the current context
# Parameters : None
# Returns    : List of strings
# Example    : get_roles_from_current_context
get_roles_from_current_context() {
	local context=$(kubectl config current-context)

	get_roles_from_context "${context}"
}

# Description: Get data about token
# Parameters : Token
# Returns    : Formatted output
# Example    : get_info_for_token my_token
get_info_for_token() {
	local token=$1

	local username=$(get_username_from_token "${token}")
	echo "username:       ${username}"
	local namespace=$(echo "${username}" | cut -d: -f3)
	local serviceaccount=$(echo "${username}" | cut -d: -f4)
	echo "namespace:      ${namespace}"
	echo "serviceaccount: ${serviceaccount}"

	echo "rolebindings:"
	get_roles_for_serviceaccount "${namespace}" "${serviceaccount}" \
	| while read; do
		echo "  ${REPLY}"
	done

	echo "clusterrolebindings:"
	get_clusterroles_for_serviceaccount "${namespace}" "${serviceaccount}" \
	| while read; do
		echo "  ${REPLY}"
	done
}

# Description: Get data about a ServiceAccount
# Parameters : Serviceaccount
# Returns    : Formatted output
# Example    : get_info_for_serviceaccount my_sa
get_info_for_serviceaccount() {
	local namespace=$1
	local serviceaccount=$2

	local token=$(get_token_for_serviceaccount "${namespace}" "${serviceaccount}")
	get_info_for_token "${token}"
}
alias get_info_for_sa=get_info_for_serviceaccount