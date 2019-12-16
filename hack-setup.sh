#!/bin/bash


CLUSTER_NAME=$1
REGION=$2

if [ -z $CLUSTER_NAME ] || [ -z $REGION ]
then
  echo "\nPlease enter cluster name [ ./setup_cluster.sh <CLUSTER_NAME> <AWS_REGION>]"
  exit 1
fi

echo "Create cluster. It will take ~10 minutes"
eksctl create cluster --name ${CLUSTER_NAME} --nodes-min=3  --node-volume-size=50 --nodes-max=5 --region=${REGION} --zones=${REGION}a,${REGION}b,${REGION}c

CURRENT_CLUSTER=$(kubectl config current-context)


if [[ ! $CURRENT_CLUSTER =~ $CLUSTER_NAME ]]
then
  echo "Current Cluster in ~/.kube/config not found"
  exit 1
fi

echo "Install HELM into the cluster"
kubectl create -f /cnab/app/rbac-config.yaml
echo "Initialize HELM with newly created ServiceAccount"
helm init --upgrade --service-account tiller

#TODO: need to find better jq query
ROLE_NAME=$(aws iam list-roles | jq  -r '.[] | .[] | select(.RoleName | contains ("NodeInstanceRole")) | .RoleName')
echo "Role ARN: ${ROLE_NAME}"
if [ -z $ROLE_NAME ]
then
  echo "Role Not found to create EFS"
  exit 1
fi

echo "Attaching arn:aws:iam::aws:policy/AmazonElasticFileSystemReadOnlyAccess to the RoleName: ${ROLE_NAME}"
aws iam attach-role-policy --role-name ${ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonElasticFileSystemReadOnlyAccess

echo "Create EFS file storage"
EFS_ID=$(aws efs create-file-system --creation-token $CLUSTER_NAME --tags Key=Name,Value=$CLUSTER_NAME --region $REGION | jq -r '. | .FileSystemId')


SUBNET_IDS=$(aws eks describe-cluster --name $CLUSTER_NAME  --region $REGION | jq -r '.cluster.resourcesVpcConfig.subnetIds | .[]')
SECURITY_GROUP_ID=$(aws eks describe-cluster --name $CLUSTER_NAME  --region $REGION | jq -r '.cluster.resourcesVpcConfig.securityGroupIds | .[]')


for subnet in $SUBNET_IDS
do
  echo "Creating mount point for subent: $subnet"
  aws efs create-mount-target --file-system-id $EFS_ID --subnet-id $subnet --security-group $SECURITY_GROUP_ID --region $REGION
done

NODEGROUP_SG=$(aws ec2 describe-security-groups --region $REGION | jq -r '.SecurityGroups | .[] | select(.GroupName | contains ("nodegroup")) | .GroupId')
CONTROL_SG=$(aws ec2 describe-security-groups --region $REGION | jq -r '.SecurityGroups | .[] | select(.GroupName | contains ("ControlPlaneSecurityGroup")) | .GroupId')

echo "Add NFS Ingress to both $NODEGROUP_SG and $CONTROL_SG vice versa"
aws ec2 authorize-security-group-ingress --group-id $NODEGROUP_SG --protocol tcp --port 2049 --source-group $CONTROL_SG --region $REGION
aws ec2 authorize-security-group-ingress --group-id $CONTROL_SG --protocol tcp --port 2049 --source-group $NODEGROUP_SG --region $REGION


# Wait to finish tiller
sleep 80


echo "ADD efs provistioner to the cluster"
helm install --name efs stable/efs-provisioner --set efsProvisioner.efsFileSystemId=$EFS_ID,efsProvisioner.awsRegion=$REGION
