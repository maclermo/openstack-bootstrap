#!/bin/sh

# Prerequisites
# - Ubuntu 20.04.* with VMX|SVM (CPU)
# - Working networking (192.168.0.91/24, GW 192.168.0.254, DNS 192.168.0.2)
# - Second network card with DHCP disabled and no IP address, connected.
# - Hostname set to kvm1.mclermont.ca
# - Hosts same as config provided (/etc/hosts)

echo "Installing chrony..."

apt-get install chrony -y
systemctl enable chronyd.service
systemctl restart chronyd.service

echo "Enabling repo and dist-upgrade..."

add-apt-repository cloud-archive:victoria -y
apt-get update -y && apt-get dist-upgrade -y
apt-get install python3-openstackclient -y

echo "Installing neutron..."

apt-get install neutron-linuxbridge-agent -y
cp config_node/etc/neutron/neutron.conf /etc/neutron/neutron.conf
cp config_node/etc/neutron/plugins/ml2/linuxbridge_agent.ini /etc/neutron/plugins/ml2/linuxbridge_agent.ini
systemctl enable neutron-linuxbridge-agent

echo "Installing nova..."

apt-get install nova-compute -y
cp config_node/etc/nova/nova.conf /etc/nova/nova.conf
systemctl enable nova-compute
systemctl enable libvirtd
systemctl restart nova-compute
systemctl restart libvirtd
systemctl restart neutron-linuxbridge-agent

echo "Discovering the host..."
sleep 60
source openrc
su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova
openstack compute service list --service nova-compute
