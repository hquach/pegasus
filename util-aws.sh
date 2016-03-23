#!/bin/bash

PEG_ROOT=$(dirname "${BASH_SOURCE}")

AWS_CMD="aws ec2 --region ${REGION:=us-west-2} --output text"

function get_public_dns_with_name_and_role {
  local cluster_name=$1
  local cluster_role=$2
  ${AWS_CMD} describe-instances \
    --filters Name=tag:Name,Values=${cluster_name} \
              Name=tag:Role,Values=${cluster_role} \
              Name=instance-state-name,Values=running \
    --query Reservations[].Instances[].NetworkInterfaces[].Association.PublicDnsName
}

function get_private_dns_with_name_and_role {
  local cluster_name=$1
  local cluster_role=$2
  ${AWS_CMD} describe-instances \
    --filters Name=tag:Name,Values=${cluster_name} \
              Name=tag:Role,Values=${cluster_role} \
              Name=instance-state-name,Values=running \
    --query Reservations[].Instances[].NetworkInterfaces[].PrivateDnsName
}

function get_pemkey_with_name {
  local cluster_name=$1
  ${AWS_CMD} describe-instances \
    --filters Name=tag:Name,Values=${cluster_name} \
              Name=instance-state-name,Values=running \
    --query Reservations[].Instances[].KeyName
}

function get_instance_types_with_name {
  local cluster_name=$1
  ${AWS_CMD} describe-instances \
    --filters Name=tag:Name,Values=${cluster_name} \
              Name=instance-state-name,Values=running \
    --query Reservations[].Instances[].InstanceType
}

function get_instance_ids_with_name_and_role {
  local cluster_name=$1
  local cluster_role=$2

  if [ -z ${cluster_role} ]; then
    ${AWS_CMD} describe-instances \
      --filters Name=tag:Name,Values=${cluster_name} \
      --query Reservations[].Instances[].InstanceId

  else
    ${AWS_CMD} describe-instances \
      --filters Name=tag:Name,Values=${cluster_name} \
                Name=tag:Role,Values=${cluster_role} \
      --query Reservations[].Instances[].InstanceId
  fi
}

function show_all_vpcs {
  ${AWS_CMD} describe-vpcs \
    --output json \
    --query Vpcs[]
}

function get_vpcids_with_name {
  local vpc_name=$1
  ${AWS_CMD} describe-vpcs \
    --filters Name=tag:Name,Values=${vpc_name} \
    --query Vpcs[].VpcId
}

function show_all_subnets_in_vpc {
  local vpc_name=$1
  local vpc_id=$(get_vpcids_with_name ${vpc_name})

  ${AWS_CMD} describe-subnets \
    --output json \
    --filters Name=vpc-id,Values=${vpc_id:?"vpc ${vpc_name} not found"}

}

function show_all_security_groups_in_vpc {
  local vpc_name=$1
  local vpc_id=$(get_vpcids_with_name ${vpc_name})

  ${AWS_CMD} describe-security-groups \
    --output json \
    --filters Name=vpc-id,Values=${vpc_id:?"vpc ${vpc_name} not found"} \
    --query SecurityGroups[]
}

function get_security_groupids_in_vpc_with_name {
  local vpc_name=$1
  local vpc_id=$(get_vpcids_with_name ${vpc_name})
  local security_group_name=$2

  ${AWS_CMD} describe-security-groups \
    --filters Name=vpc-id,Values=${vpc_id:?"vpc ${vpc_name} not found"} \
              Name=group-name,Values=${security_group_name} \
    --query SecurityGroups[].GroupId
}

function run_spot_instances {
  local launch_specification="{\"ImageId\":\"${AWS_IMAGE}\",\"KeyName\":\"${key_name}\",\"InstanceType\":\"${instance_type}\",\"BlockDeviceMappings\":${block_device_mappings},\"SubnetId\":\"${subnet_id}\",\"Monitoring\":${monitoring},\"SecurityGroupIds\":[\"${security_group_ids}\"]}"

  ${AWS_CMD} request-spot-instances \
    --spot-price "${price:?"specify spot price"}" \
    --instance-count ${num_instances:?"specify number of instances"} \
    --type "one-time" \
    --launch-specification ${launch_specification} \
    --query SpotInstanceRequests[].SpotInstanceRequestId

}

function run_on_demand_instances {
  ${AWS_CMD} run-instances \
    --count ${num_instances:?"specify number of instances"} \
    --image-id ${AWS_IMAGE} \
    --key-name ${key_name:?"specify pem key to use"} \
    --security-group-ids ${security_group_ids:?"specify security group ids"} \
    --instance-type ${instance_type:?"specify instance type"} \
    --subnet-id ${subnet_id:?"specify subnet id to launch"} \
    --block-device-mappings ${block_device_mappings} \
    --monitoring ${monitoring} \
    --query Instances[].InstanceId
}

function get_image_id_from_instances {
  local instance_ids="$@"
  ${AWS_CMD} describe-instances \
    --instance-ids ${instance_ids} \
    --query Reservations[].Instances[].ImageId
}

function get_pem_key_from_instances {
  local instance_ids="$@"
  ${AWS_CMD} describe-instances \
    --instance-ids ${instance_ids} \
    --query Reservations[].Instances[].KeyName
}

function get_security_group_ids_from_instances {
  local instance_ids="$@"
  ${AWS_CMD} describe-instances \
    --instance-ids ${instance_ids} \
    --query Reservations[].Instances[].SecurityGroups[].GroupId
}

function get_instance_type_from_instances {
  local instance_ids="$@"
  ${AWS_CMD} describe-instances \
    --instance-ids ${instance_ids} \
    --query Reservations[].Instances[].InstanceType
}

function get_subnet_id_from_instances {
  local instance_ids="$@"
  ${AWS_CMD} describe-instances \
    --instance-ids ${instance_ids} \
    --query Reservations[].Instances[].SubnetId
}

function get_public_dns_from_instances {
  local instance_ids="$@"
  ${AWS_CMD} describe-instances \
    --instance-ids ${instance_ids} \
    --query Reservations[].Instances[].PublicDnsName
}

function get_volume_size_from_instances {
  local instance_ids="$@"
  local volume_id=$(${AWS_CMD} describe-instances \
                      --instance-ids ${instance_ids} \
                      --query Reservations[].Instances[].BlockDeviceMappings[0].Ebs.VolumeId)
  ${AWS_CMD} describe-volumes \
    --volume-ids ${volume_id} \
    --query Volumes[0].Size
}

function tag_resources {
  local key=$1; shift
  local val=$1; shift
  local resource_ids="$@"
  ${AWS_CMD} create-tags \
    --resources ${resource_ids} \
    --tags Key=${key},Value=${val}
}

function wait_for_instances_status_ok {
  local instance_ids="$@"
  ${AWS_CMD} wait instance-status-ok \
    --instance-ids ${instance_ids}
}

function wait_for_spot_requests {
  local spot_request_ids="$@"
  ${AWS_CMD} wait spot-instance-request-fulfilled \
    --spot-instance-request-ids ${spot_request_ids}
}

function get_instance_ids_of_spot_request_ids {
  local spot_request_ids="$@"
  ${AWS_CMD} describe-spot-instance-requests \
    --spot-instance-request-ids ${spot_request_ids} \
    --query SpotInstanceRequests[].InstanceId
}

function get_price_of_spot_request_ids {
  local spot_request_ids="$@"
  ${AWS_CMD} describe-spot-instance-requests \
    --spot-instance-request-ids ${spot_request_ids} \
    --query SpotInstanceRequests[].SpotPrice
}

function get_spot_request_ids_of_instance_ids {
  local instance_ids="$@"
  ${AWS_CMD} describe-instances \
    --instance-ids ${instance_ids} \
    --query Reservations[].Instances[].SpotInstanceRequestId
}

function retag_instance_with_name {
  local cluster_name=$1
  local new_cluster_name=$2
  local instance_ids=$(get_instance_ids_with_name_and_role ${cluster_name})

  ${AWS_CMD} create-tags \
    --resources ${instance_ids} \
    --tags Key=Name,Value=${new_cluster_name}
}

function start_instance {
  local cluster_name=$1
  local instance_ids=$(get_instance_ids_with_name_and_role ${cluster_name})

  ${AWS_CMD} start-instances \
    --instance-ids ${instance_ids}
}

function stop_instance {
  local cluster_name=$1
  local instance_ids=$(get_instance_ids_with_name_and_role ${cluster_name})

  ${AWS_CMD} stop-instances \
    --instance-ids ${instance_ids}
}
