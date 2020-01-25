#!/usr/bin/env bash
set -e

source ci/scripts/common-func.sh

REQUIRED_ENV_VARS=(
  HOSTNAME
  GENERATED_NAMESPACE
  TARGET_PLATFORM
)

export_keyval_env

check_skip_testing_condition

check_req_env_vars

setup_kubectl_context


echo "Create QSEFE License"
secretName=qsefe-license
kubectl create secret generic ${secretName} --from-literal=qsefe-license=${QSEFE_LICENSE}

echo "Installing simple oidc chart"
errno=0
chartName=simple-oidc-chart
oidcValuesFile="ci/common/values/${chartName}-values.yaml"
for i in {1..5}; do helm install --tiller-namespace="$GENERATED_NAMESPACE" --wait --name sut-${chartName} qlik/${chartName} -f ${oidcValuesFile} && errno=0 && break || errno=$? && sleep 30; done;
if [[ ${errno} -ne 0 ]]; then
  echo "ERROR: Failure to install ${chartName} chart"
  exit 1
fi
