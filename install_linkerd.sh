#!/bin/bash

# Creates three k3d clusters: dev, east, & west.
#

set -eu
set -x

ORG_DOMAIN="${ORG_DOMAIN:-k3d.example.com}"
LINKERD="${LINKERD:-linkerd}"

#CA_DIR=$(mktemp --tmpdir="${TMPDIR:-/tmp}" -d k3d-ca.XXXXX)
CA_DIR=cert

if ! command -v linkerd >/dev/null 2>&1 ; then
    echo "linkerd not found in PATH" >&2
    exit 1
fi

if ! command -v linkerd-smi >/dev/null 2>&1 ; then
    echo "linkerd-smi not found in PATH" >&2
    exit 1
fi

# Generate the trust roots. These never touch the cluster. In the real world
# we'd squirrel these away in a vault.
step certificate create \
    "identity.linkerd.${ORG_DOMAIN}" \
    "$CA_DIR/ca.crt" "$CA_DIR/ca.key" \
    --profile root-ca \
    --no-password  --insecure --force

for cluster in east west ; do
    # Check that the cluster is up and running.
    while ! $LINKERD --context="$cluster" check --pre ; do :; done

    # Create issuing credentials. These end up on the cluster (and can be
    # rotated from the root).
    crt="${CA_DIR}/${cluster}-issuer.crt"
    key="${CA_DIR}/${cluster}-issuer.key"
    domain="${cluster}.${ORG_DOMAIN}"
    step certificate create "identity.linkerd.${domain}" \
        "$crt" "$key" \
        --ca="$CA_DIR/ca.crt" \
        --ca-key="$CA_DIR/ca.key" \
        --profile=intermediate-ca \
        --not-after 8760h --no-password --insecure

    $LINKERD --context="$cluster" install --crds |
        kubectl --context="$cluster" apply -f -

    # Install Linkerd into the cluster.
    $LINKERD --context="$cluster" install \
            --proxy-log-level="linkerd=debug,trust_dns=debug,info" \
            --cluster-domain="$domain" \
            --identity-trust-domain="$domain" \
            --identity-trust-anchors-file="$CA_DIR/ca.crt" \
            --identity-issuer-certificate-file="${crt}" \
            --identity-issuer-key-file="${key}" |
        kubectl --context="$cluster" apply -f -

    # Wait some time and check that the cluster has started properly.
    sleep 30
    while ! $LINKERD --context="$cluster" check ; do :; done

    linkerd smi --context="$cluster" install --set="clusterDomain=$domain" |
        kubectl --context="$cluster" apply -f -

    kubectl --context="$cluster" create ns linkerd-multicluster
    kubectl --context="$cluster" annotate ns/linkerd-multicluster \
        config.linkerd.io/proxy-log-level='linkerd=info,warn'
    sleep 2

    # Setup the multicluster components on the server
    $LINKERD --context="$cluster" multicluster install |
        kubectl --context="$cluster" apply -f -
done
