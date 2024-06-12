#!/bin/bash
component=$1
environment=$2
app_Version=$3
dnf install ansible -y
pip3.9 install botocore boto3 # to connect aws
ansible-pull -i localhost, -U https://github.com/sriramulasrinath/cicd-ansible-roles.git  main.yml -e component=$component -e env=$environment -e appVersion=$3