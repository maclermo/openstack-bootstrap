#!/bin/sh

echo "Installing chrony..."

apt-get install chrony -y
systemctl enable chronyd.service
systemctl restart chronyd.service

echo "Enabling repo and dist-upgrade..."

add-apt-repository cloud-archive:victoria -y
apt-get update -y && apt-get dist-upgrade -y
apt-get install python3-openstackclient -y
