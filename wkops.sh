#!/bin/bash

fatal() { echo -e "ERROR: $@" 1>&2; exit 1; }

list() {
  if [ -z "$(aws s3 ls ${KOPS_STATE_STORE}| grep k8s)" ]
  then
    echo "No clusters are existing"
  else
    printf "These are the existing clusters:\n`aws s3 ls ${KOPS_STATE_STORE} | grep k8s | awk '{print $2}' | tr -d '/'`\n"
  fi
}

downloadKeys() {
  aws s3 sync ${KOPS_STATE_STORE}/ssh-keys/ ~/.ssh/ > /dev/null 2>&1
  chmod -R 600 ~/.ssh/ > /dev/null 2>&1
}

uploadKeys() {
  aws s3 sync ~/.ssh/ ${KOPS_STATE_STORE}/ssh-keys/ > /dev/null 2>&1
}


downloadPass() {
  aws s3 sync ${KOPS_STATE_STORE}/dashboards-password/$K8S_CLUSTER_NAME.pass ./ > /dev/null 2>&1
}

installServices() {
  if [ "$(ls services)" ]
  then
    kubectl apply -R -f services/ > /dev/null
  fi
}

installIngresses() {
  if [ "$(ls ingresses)" ]
  then
    kubectl apply -R -f ingresses/ > /dev/null
  fi
}

installSecrets() {
  if [ "$(ls secrets)" ]
  then
    kubectl apply -R -f secrets/ > /dev/null
  fi
}

removeServices() {
  if [ "$(ls services)" ]
  then
    kubectl delete -f services/ > /dev/null
  fi
}

removeIngresses() {
  if [ "$(ls ingresses)" ]
  then
    kubectl delete -R -f ingresses/ > /dev/null
  fi
}

removeSecrets() {
  if [ "$(ls secrets)" ]
  then
    kubectl delete -R -f secrets/ > /dev/null
  fi
}

buildDashboard() {
  kubectl create -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/kubernetes-dashboard/v$DASHBOARD_VERSION.yaml

  #save dashboard password to cluster folder in S3
  kops get secrets kube --type secret -oplaintext &> /dev/null > $K8S_CLUSTER_NAME.pass
  aws s3 cp $K8S_CLUSTER_NAME.pass $KOPS_STATE_STORE/dashboards-password/$K8S_CLUSTER_NAME.pass > /dev/null 2>&1
  echo
  echo "Cluster is ready"
  echo
  echo "- K8S dashboard URL: https://api.${K8S_CLUSTER_NAME}/ui"
  echo "- The user for the dashboard is: admin."
  echo "- The password for the dashboard is: `kops get secrets kube --type secret -oplaintext 2>/dev/null`"
  echo "- For future use, the password for the dashboard can be found here: $KOPS_STATE_STORE/dashboards-password/$K8S_CLUSTER_NAME.pass"
  echo "- To connect the envirument using kubectl run the following command: kops export kubecfg --name=${K8S_CLUSTER_NAME} --state=${KOPS_STATE_STORE}"
}

buildMonitoring() {
  kubectl create -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/monitoring-standalone/v$MONITORING_VERSION.yaml
}

exportCfg() {
  kops export kubecfg --name=$K8S_CLUSTER_NAME
}

create() {
  if [ -z "${TEMPLATE}" ]
  then
    export TEMPLATE="default"
  fi

  echo "************************************************************************************"
  echo "Start creating the cluster ${K8S_CLUSTER_NAME} based on ${TEMPLATE} template"
  echo "************************************************************************************"

  kops create -f config/${TEMPLATE}.yml
  # Use for adding ssh key to all cluster's instnaces
  if [ ! -f ~/.ssh/kops.pub ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/kops -q -P ""
  fi
  uploadKeys
  kops create secret --name ${K8S_CLUSTER_NAME} sshpublickey admin -i ~/.ssh/kops.pub
  kops update cluster ${K8S_CLUSTER_NAME} --yes

  STATUS_CODE="000"
  while [ "$STATUS_CODE" == "000" ]; do
    STATUS_CODE=`curl -s -o /dev/null -w "%{http_code}" --insecure https://api.${K8S_CLUSTER_NAME}`
    if [ "$STATUS_CODE" == "401" ]
    then
      installSecrets
      installIngresses
      sleep 3m
      installServices
      buildMonitoring
      buildDashboard
      helm init --kube-context $K8S_CLUSTER_NAME
    else
      echo "Cluster is not ready yet... ( https://api.${K8S_CLUSTER_NAME} curl status code: $STATUS_CODE ) " && sleep 45
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
export DASHBOARD_VERSION=1.8.1
export MONITORING_VERSION=1.7.0

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
  removeIngresses)   removeIngresses ;;
  removeSecrets)   removeSecrets ;;
  installServices)   installServices ;;
  installIngresses)   installIngresses ;;
  installSecrets)   installSecrets ;;
  export)   exportCfg ;;
  *) echo -e "usage: $0 create | teardown | list | downloadKeys | removeServices | removeIngresses | removeSecrets | installServices | installIngresses | installSecrets | export" >&2
      exit 1
      ;;
esac
