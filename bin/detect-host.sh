#!/usr/bin/env bash
set +e -E -u -o pipefail

if   ip link show | grep link/ether | awk '{print $2}' | grep -q ^60:a4:4c:41:3b:87$; then
  echo gla
elif ip link show | grep link/ether | awk '{print $2}' | grep -q ^10:bf:48:e1:e8:cd$; then
  echo bud
elif ip link show | grep link/ether | awk '{print $2}' | grep -q ^28:d2:44:cc:8f:c1$; then
  echo laptop
else
  echo "ERROR: Unkown host" >&2
  exit 1
fi
