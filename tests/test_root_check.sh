#!/bin/bash
scripts=("k8s-master-setup.sh" "k8s-node-setup.sh")
cd "$(dirname "$0")/.."
for script in "${scripts[@]}"; do
  sudo -u nobody bash "$script" >/dev/null 2>&1
  status=$?
  if [ "$status" -ne 1 ]; then
    echo "$script exited with $status, expected 1" >&2
    exit 1
  fi
done
echo "Root check scripts exit with status 1 as expected."
