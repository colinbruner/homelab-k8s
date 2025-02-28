#!/usr/bin/env bash

TARGET=$1
if [[ -z $TARGET ]]; then
  echo "[ERROR]: Missing target. Rerun: $0 <target>"
  exit 1
fi

ansible-galaxy collection install -r requirements/collections.yml

# https://docs.ansible.com/ansible/latest/inventory_guide/intro_patterns.html#patterns-and-ansible-playbook-flags
# NOTE: must have trailing comma
# TODO: ideally dont use root..
ansible-playbook \
    -u root \
    -i "${TARGET}," \
    --extra-vars @vars/main.yml \
    pxe.yml
