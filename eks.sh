#!/bin/bash

fatal() { echo -e "ERROR: $@" 1>&2; exit 1; }

downloadPass() {
  kubectl -n kube-system describe secret "$(kubectl -n kube-system get secret | grep eks-admin | awk '{print $1}')" > /dev/null 2>&1
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

exportCfg() {
  aws eks update-kubeconfig --name $K8S_CLUSTER_NAME
}

#FIRST: check sanity
kubectl >/dev/null || fatal 'The `kubectl` CLI tool is not available.'
aws --version > /dev/null 2>&1 || fatal 'The `aws` CLI tool is not available.'

case "$1" in
  config) exportCfg ;;
  removeServices)   removeServices ;;
  removeIngresses)   removeIngresses ;;
  removeSecrets)   removeSecrets ;;
  installServices)   installServices ;;
  installIngresses)   installIngresses ;;
  installSecrets)   installSecrets ;;
  *) echo -e "usage: $0 removeServices | removeIngresses | removeSecrets | installServices | installIngresses | installSecrets | config" >&2
      exit 1
      ;;
esac
