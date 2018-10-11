#!/bin/bash

if [ -z "$KOPS_STATE_STORE" ]; then
  echo "no kops"
else
  wkops export
fi

eks config
