#!/bin/bash

CLUSTER_NAME=$1
REGION=$2

if [ -z $CLUSTER_NAME ] || [ -z $REGION ]
then
  echo "\nPlease enter cluster name [ ./setup_cluster.sh <CLUSTER_NAME> <AWS_REGION>]"
  exit 1
fi


echo "waiting to finish helm deletion"
sleep 90

NODEGROUP_SG=$(aws ec2 describe-security-groups --region $REGION | jq -r '.SecurityGroups | .[] | select(.GroupName | contains ("nodegroup")) | .GroupId')
CONTROL_SG=$(aws ec2 describe-security-groups --region $REGION | jq -r '.SecurityGroups | .[] | select(.GroupName | contains ("ControlPlaneSecurityGroup")) | .GroupId')

echo "De-Referencing Security Groups [ $NODEGROUP_SG ] and [ $CONTROL_SG ] vice versa"
aws ec2 revoke-security-group-ingress --group-id $NODEGROUP_SG --source-group $CONTROL_SG --protocol tcp --port 2049 --region $REGION
aws ec2 revoke-security-group-ingress --group-id $CONTROL_SG --source-group $NODEGROUP_SG --protocol tcp --port 2049 --region $REGION


ROLE_NAME=$(aws iam list-roles | jq  -r '.[] | .[] | select(.RoleName | contains ("NodeInstanceRole")) | .RoleName')
echo "Detaching arn:aws:iam::aws:policy/AmazonElasticFileSystemReadOnlyAccess to the RoleName: ${ROLE_NAME}"
aws iam detach-role-policy --role-name ${ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonElasticFileSystemReadOnlyAccess


EFS_ID=$(aws efs describe-file-systems --creation-token $CLUSTER_NAME --region $REGION | jq -r '.FileSystems | .[] | .FileSystemId')
MOUNT_TARGETS=$(aws efs describe-mount-targets --file-system-id $EFS_ID --region $REGION | jq -r '.MountTargets | .[] | .MountTargetId')
for mt in $MOUNT_TARGETS
do
  echo "delete mount target [$mt]"
  aws efs delete-mount-target --mount-target-id $mt --region $REGION
done

echo "Deleting EFS $EFS_ID"
aws efs delete-file-system --file-system-id $EFS_ID --region $REGION

echo "Deleting cluster [ $CLUSTER_NAME ]"
eksctl delete cluster --name $CLUSTER_NAME --region $REGION
