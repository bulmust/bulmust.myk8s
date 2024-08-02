#!/bin/sh

# App name is in argument 1
appName=$1

# Current directory
currDir=$(pwd)

# Paths of info.yaml and values.yaml
pathInfoYaml="$currDir/$appName/helm/info.yaml"
pathValuesYaml="$currDir/$appName/helm/values.yaml"

# Getting values from info.yaml
chartName=$(cat $pathInfoYaml|yq -r '.chartName' )
repoURL=$(cat $pathInfoYaml|yq -r '.repoURL' )
version=$(cat $pathInfoYaml|yq -r '.version')

deploymentName=$(cat $pathInfoYaml|yq -r '.deployment.name')
deploymentNamespace=$(cat $pathInfoYaml|yq -r '.deployment.namespace')
deploymentProject=$(cat $pathInfoYaml|yq -r '.deployment.project')
deploymentServer=$(cat $pathInfoYaml|yq -r '.deployment.server')

# Helm repo add to tmp name
helm repo add tmp $repoURL
# Helm repo update
helm repo update tmp
# Helm install
helm upgrade --install --debug -n $deploymentNamespace --create-namespace --version $version -f $pathValuesYaml $deploymentName tmp/$chartName
# Helm repo remove tmp
helm repo remove tmp