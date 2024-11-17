#!/bin/bash
set -eu
API_PORT=6440
HTTP_PORT=80
HTTPS_PORT=443
ORG_DOMAIN=cluster.local
CLUSTERS="east west"
LINKERD="${LINKERD:-linkerd}"

createCluster (){
for cluster in ${CLUSTERS} ; do \
    echo "Creating cluster $cluster..." ;\
    if k3d cluster get "$cluster" >/dev/null 2>&1; then \
        echo "Cluster $cluster already exists" >&2 ;\
    else \
        k3d cluster create $cluster  \
            --api-port="$((API_PORT++))" \
	        --network="multicluster-example" \
            --k3s-arg='--disable=local-storage,metrics-server@server:*' \
            --k3s-arg="--cluster-domain=${ORG_DOMAIN}@server:*" \
            --kubeconfig-update-default \
            --kubeconfig-switch-context=false ;\
    fi ;\
done

for ctx in $CLUSTERS; do \
    if kubectl config get-contexts k3d-$ctx >/dev/null 2>&1; then \
        echo "renaming k3d-$ctx to $ctx" ;\
        kubectl config delete-context $ctx >/dev/null 2>&1 || true ;\
        kubectl config rename-context k3d-$ctx $ctx ;\
    fi ;\
done

for cluster in ${CLUSTERS} ; do \
    echo "  ...waiting for cluster $cluster to start..." ;\
    while true; do \
        count=$(kubectl --context="$cluster" get pods -n kube-system -l k8s-app=kube-dns -o json | jq '.items | length') ;\
        if [ $count -gt 0 ]; then break; fi ;\
    done ;\
done

for cluster in ${CLUSTERS} ; do \
    echo "  ...waiting for cluster $cluster to be ready..." ;\
    kubectl --context="$cluster" wait pod --for=condition=ready \
            --namespace=kube-system --selector=k8s-app=kube-dns \
            --timeout=1m ;\
    \
    echo "  ...done" ;\
done
}

# Generate the trust roots. These never touch the cluster. In the real world
# we'd squirrel these away in a vault.
installLInkerd ( ){
step certificate create \
    "identity.linkerd.${ORG_DOMAIN}" \
    cert/ca.crt cert/ca.key \
    --profile root-ca \
    --no-password  --insecure --force

for cluster in ${CLUSTERS} ; do
    # Check that the cluster is up and running.
    while ! $LINKERD --context="$cluster" check --pre ; do :; done

    # Create issuing credentials. These end up on the cluster (and can be
    # rotated from the root).
    crt="cert/${cluster}-issuer.crt"
    key="cert/${cluster}-issuer.key"
    domain="${ORG_DOMAIN}"
    step certificate create "identity.linkerd.${domain}" \
        "$crt" "$key" \
        --ca=cert/ca.crt \
        --ca-key=cert/ca.key \
        --profile=intermediate-ca \
        --not-after 8760h --no-password --insecure -f

    # Install crds
    $LINKERD --context="$cluster" install --crds |
        kubectl --context="$cluster" apply -f -
    sleep 10
#    # Install Linkerd into the cluster.
    $LINKERD --context="$cluster" install \
            --proxy-log-level="linkerd=debug,trust_dns=debug,info" \
            --cluster-domain="$domain" \
            --identity-trust-domain="$domain" \
            --identity-trust-anchors-file=cert/ca.crt \
            --identity-issuer-certificate-file="${crt}" \
            --identity-issuer-key-file="${key}" |
        kubectl --context="$cluster" apply -f -

    # Wait some time and check that the cluster has started properly.
    sleep 30
done
}

installViz () {
    
    for cluster in ${CLUSTERS}; do
    domain="${ORG_DOMAIN}"
    while ! $LINKERD --context="$cluster" check ; do :; done

    $LINKERD --context="$cluster" viz install --set clusterDomain="${domain}" |
        kubectl --context="$cluster" apply -f -

    sleep 10
    while ! $LINKERD --context="$cluster" viz check ; do :; done

done
}
installsmi () {
   for cluster in ${CLUSTERS}; do
       while ! $LINKERD --context="$cluster" check ; do :; done
       $LINKERD  smi install --context=$cluster| kubectl --context="$cluster" apply -f - 
       done

}
installmc () {
    for cluster in ${CLUSTERS}; do
        while ! $LINKERD --context="$cluster" check ; do :; done
        $LINKERD --context="$cluster" multicluster install  |
            kubectl --context="$cluster" apply -f -
    done
    linkerd multicluster check --context="$cluster"

}

installemojivoto () {
for ctx in west east; do
    kubectl --context="$ctx" apply -f https://run.linkerd.io/emojivoto.yml
    kubectl get deploy -n emojivoto --context="$ctx" -oyaml | 
        linkerd --context="$ctx" inject - | 
        kubectl apply --context="$ctx" -f -
done
}
uninstallemojivoto () {
for ctx in west east; do
    kubectl --context="$ctx" delete -f https://run.linkerd.io/emojivoto.yml
done
}

fetch_credentials() {
    
    cluster="$1"
    # Grab the LB IP of cluster's API server & replace it in the secret blob:
    lb_ip=$(kubectl --context="$cluster" get svc -n kube-system traefik \
        -o 'go-template={{ (index .status.loadBalancer.ingress 0).ip }}')

    linkerd multicluster --context="$cluster" link  \
            --cluster-name="$cluster" \
            --api-server-address="https://${lb_ip}:6443"
}

link () {
    # East & West get access to each other.
    fetch_credentials east | kubectl --context=west apply  -f -
    fetch_credentials east
    fetch_credentials west | kubectl --context=east apply -f -

    sleep 10
    for c in east west ; do
        $LINKERD --context="$c" mc check
    done
}

deleteCluster () {
for cluster in ${CLUSTERS} ; do \
    echo "Deleting cluster $cluster..." ;\
    if k3d cluster get "$cluster" >/dev/null 2>&1; then \
        k3d cluster delete $cluster ;\
    else \
        echo "Cluster $cluster does not exist" >&2 ;\
    fi ;\
done
}

stop () {
    for cluster in ${CLUSTERS} ; do \
        echo "Stopping cluster $cluster..." ;\
        if k3d cluster get "$cluster" >/dev/null 2>&1; then \
            k3d cluster stop $cluster ;\
        else \
            echo "Cluster $cluster does not exist" >&2 ;\
        fi ;\
    done
}
start () {
    for cluster in ${CLUSTERS} ; do \
        echo "Starting cluster $cluster..." ;\
        if k3d cluster get "$cluster" >/dev/null 2>&1; then \
            k3d cluster start $cluster ;\
        else \
            echo "Cluster $cluster does not exist" >&2 ;\
        fi ;\
    done
}
unlink () {
   $LINKERD --context=west multicluster unlink --cluster-name=east | kubectl delete -f - --context=west
   $LINKERD --context=east multicluster unlink --cluster-name=west | kubectl delete -f - --context=east
}
lmcuninstall () {
    for cluster in ${CLUSTERS}; do
	$LINKERD --context="$cluster" multicluster uninstall |
	    kubectl --context="$cluster" delete -f -
    done
}

# Verifica se foi fornecido um argumento
if [ $# -ne 1 ]; then
    echo "Usage: $0 <function>"
    exit 1
fi

# Chama a função especificada pelo argumento
if declare -F "$1" > /dev/null; then
    "$1"
else
    echo "Function '$1' not found"
    exit 1
fi
