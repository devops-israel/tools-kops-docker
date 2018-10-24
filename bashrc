#!/bin/bash

if [ -z "$KOPS_STATE_STORE" ]; then
  echo "no kops"
  eks config
else
  wkops export
fi
