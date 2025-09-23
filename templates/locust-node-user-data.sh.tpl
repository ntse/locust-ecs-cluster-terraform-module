#!/bin/bash
set -euo pipefail

sudo dnf -y update
sudo dnf -y install \
  ${python_package} ${python_pip_package}

sudo ${python_bin} -m ensurepip --upgrade || true
sudo ${python_bin} -m pip install --upgrade pip
sudo ${python_bin} -m pip install "locust==${locust_version}"

PRIVATE_IP=$(hostname -I | awk '{print $1}')
echo "PRIVATE_IP=$${PRIVATE_IP}" | sudo tee -a /etc/environment >/dev/null

mkdir -p ~/.ssh
echo 'Host *' > ~/.ssh/config
echo 'StrictHostKeyChecking no' >> ~/.ssh/config

touch /tmp/finished-setup
