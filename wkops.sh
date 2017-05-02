#!/bin/bash

fatal() { echo -e "ERROR: $@" 1>&2; exit 1; }

list() {
  if [ -z "$(aws s3 ls ${KOPS_STATE_STORE}| grep k8s)" ]
  then
    echo "No clusters are existing"
  else
    printf "These are the existing clusters:\n`aws s3 ls ${KOPS_STATE_STORE}| grep k8s |awk '{print $2}' | tr -d '/'`\n"
  fi
}

downloadKeys() {
  aws s3 sync ${KOPS_STATE_STORE}/ssh-keys/ ~/.ssh/ > /dev/null 2>&1
  chmod -R 600 ~/.ssh/ > /dev/null 2>&1
}

installServices() {
  if [ "$(ls services)" ]
  then
    kubectl apply -R -f services/ > /dev/null
  fi
}

removeServices() {
  if [ "$(ls services)" ]
  then
    kubectl delete -f services/ > /dev/null
  fi
}

buildDashboard() {
  #install dashboard
  kubectl create -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/kubernetes-dashboard/v$DASHBOARD_VERSION.yaml > /dev/null && sleep 60
  #install basic monitoring
  kubectl create -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/monitoring-standalone/v$MONITORING_VERSION.yaml > /dev/null
  echo
  echo "Cluster is ready"
  echo
  echo "- K8S dashboard URL: https://api.${K8S_CLUSTER_NAME}/ui"
  echo "- The user for the dashboard is: admin."
  echo "- The password for the dashboard is: `kops get secrets kube --type secret -oplaintext 2>/dev/null`"
  echo "- For future use, the password for the dashboard can be found here: $KOPS_STATE_STORE/dashboards-password/$K8S_CLUSTER_NAME.pass"
  echo "- To connect the envirument using kubectl run the following command: kops export kubecfg --name=${K8S_CLUSTER_NAME} --state=${KOPS_STATE_STORE}"
  #save dashboard password to cluster folder in S3
  kops get secrets kube --type secret -oplaintext &> /dev/null > $K8S_CLUSTER_NAME.pass
  aws s3 cp $K8S_CLUSTER_NAME.pass $KOPS_STATE_STORE/dashboards-password/$K8S_CLUSTER_NAME.pass > /dev/null 2>&1
}

create() {

  if [ -z "${TEMPLATE}" ]
  then
    export TEMPLATE="default"
  fi

  echo "************************************************************************************"
  echo "Start creating the cluster ${K8S_CLUSTER_NAME} based on ${TEMPLATE} template"
  echo "************************************************************************************"

  downloadKeys

  kops create -f config/${TEMPLATE}.yml
  #Use for adding ssh key to all cluster's instnaces
  kops create secret --name ${K8S_CLUSTER_NAME} sshpublickey admin -i ~/.ssh/kops.pub
  kops update cluster ${K8S_CLUSTER_NAME} --yes

  OUTPUT=''
  while [ -z "$OUTPUT" ]; do
    OUTPUT=`curl -s --insecure https://api.${K8S_CLUSTER_NAME}`
    if [ "$OUTPUT" == "Unauthorized" ]
    then
      installServices
      buildDashboard
    else
      echo "Cluster is not ready yet" && sleep 45
    fi
  done
}

teardown() {
  echo "****************************************************"
  echo "Start tearing down the cluster ${K8S_CLUSTER_NAME}"
  echo "****************************************************"
  kops export kubecfg --name=$K8S_CLUSTER_NAME
  kops delete cluster --name=$K8S_CLUSTER_NAME --yes
  aws s3 rm $KOPS_STATE_STORE/dashboards-password/$K8S_CLUSTER_NAME.pass > /dev/null 2>&1
}

#addons versions
export DASHBOARD_VERSION=1.5.0
export MONITORING_VERSION=1.2.0

#FIRST: check sanity
kops version >/dev/null || fatal 'The `kops` CLI tool is not available.'
kubectl >/dev/null || fatal 'The `kubectl` CLI tool is not available.'
aws --version > /dev/null 2>&1 || fatal 'The `aws` CLI tool is not available.'

case "$1" in
  create)  create ;;
  teardown) teardown ;;
  list)   list ;;
  downloadKeys)   downloadKeys ;;
  removeServices)   removeServices ;;
  *) echo -e "usage: $0 create | teardown | list | downloadKeys | removeServices" >&2
      exit 1
      ;;
esac
