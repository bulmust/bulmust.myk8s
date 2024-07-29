#!/bin/sh

appName=$1
currDir=$(pwd)

pathInfoYaml="$currDir/$appName/helm/info.yaml"
pathValuesYaml="$currDir/$appName/helm/values.yaml"


chartName=$(cat $pathInfoYaml|yq -r '.chartName' )
repoURL=$(cat $pathInfoYaml|yq -r '.repoURL' )
version=$(cat $pathInfoYaml|yq -r '.version')

deploymentName=$(cat $pathInfoYaml|yq -r '.deployment.name')
deploymentNamespace=$(cat $pathInfoYaml|yq -r '.deployment.namespace')
deploymentProject=$(cat $pathInfoYaml|yq -r '.deployment.project')
deploymentServer=$(cat $pathInfoYaml|yq -r '.deployment.server')

helm repo add tmp $repoURL
helm repo update tmp
helm upgrade --install --debug -n $deploymentNamespace --create-namespace --version $version -f $pathValuesYaml $deploymentName tmp/$chartName
helm repo remove tmp