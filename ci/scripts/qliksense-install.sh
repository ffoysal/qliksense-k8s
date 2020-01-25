#!/usr/bin/env bash
set -e

source ci/scripts/common-func.sh

REQUIRED_ENV_VARS=(
  GENERATED_NAMESPACE
  TARGET_PLATFORM
)

export_keyval_env

check_skip_testing_condition

check_req_env_vars

setup_kubectl_context

export root_ca=$(cat rootCA.crt)

cat <<EOF > cr.tmpl.yaml
configProfile: manifests/docker-desktop
manifestsRoot: "/root/src"
storageClassName: efs
namespace: "$GENERATED_NAMESPACE"
storageClassName: "efs"
rotateKeys: "None"
configs:
- dataKey: acceptEULA
  values:
    qliksense: "yes"
secrets:
- secretKey: mongoDbUri
  values:
    qliksense: mongodb://qliksense-mongodb:27017/qliksense?ssl=false
- secretKey: caCertificate
  values:
    qliksense: "$root_ca"
EOF
## Substitute namespace in cr.tmpl.yaml
cat cr.tmpl.yaml | envsubst > cr.yaml

export YAML_CONF=$(cat cr.yaml)

# Apply patches using operator
qliksense-operator

## Turn off default simple-oidc in edge-auth
yq w -i /root/src/manifests/base/resources/edge-auth/generators/values.yaml 'values.service.type' ClusterIP
yq w -i /root/src/manifests/base/resources/edge-auth/generators/values.yaml 'values.oidc.enabled' false
# delete the patch for oidc
yq d -i /root/src/manifests/base/resources/edge-auth/patches/deployment.yaml 'spec.template.spec.containers[1]'

cd /root/src/manifests/docker-desktop
kustomize build . | kubectl apply --validate=false -f -

# modify qliksense-elastic-infra-elastic-infra-tls-secret
kubectl apply -f /root/src/tls-secret.yaml --namespace ${GENERATED_NAMESPACE}
## rollout elastic-infra deployment after creating the new tls secret
ELASTIC_INFRA_POD=$(kubectl get pods -o jsonpath="{.items[*].metadata.name}" -l app=elastic-infra)
kubectl delete pod $ELASTIC_INFRA_POD