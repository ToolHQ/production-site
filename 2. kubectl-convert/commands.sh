#!/bin/bash
# Tested in 2024-03-24
# From: https://pet2cattle.com/2022/06/kubectl-convert

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl-convert"
sudo install -o root -g root -m 0755 kubectl-convert /usr/local/bin/kubectl-convert