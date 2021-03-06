#!/bin/sh

# Prerequisites
# - Ubuntu 20.04.* with VMX|SVM (CPU)
# - Working networking (192.168.0.100/24, GW 192.168.0.254, DNS 192.168.0.2)
# - Hostname set to controller.mclermont.ca
# - Hosts same as config provided (/etc/hosts)
# - One free disk for Cinder, unformatted, wiped. (/dev/sdb)
# - Four free disks for Swift, unformatted, wiped. (/dev/sd[c-f])

echo "Installing chrony..."

apt-get install chrony -y
systemctl enable chronyd.service
systemctl restart chronyd.service

echo "Enabling repo and dist-upgrade..."

add-apt-repository cloud-archive:victoria -y
apt-get update -y && apt-get dist-upgrade -y
apt-get install python3-openstackclient -y

echo "Installing mariadb..."

apt-get install mariadb-server python3-pymysql -y
cp config_controller/etc/mysql/mariadb.conf.d/99-openstack.cnf /etc/mysql/mariadb.conf.d/99-openstack.cnf
systemctl enable mariadb
systemctl restart mariadb

echo "Installing rabbitmq..."

apt-get install rabbitmq-server -y
rabbitmqctl add_user openstack f45a69dcb4beebe66131
rabbitmqctl set_permissions openstack ".*" ".*" ".*"
systemctl enable rabbitmq-server

echo "Installing memcached..."

apt-get install memcached python3-memcache -y
cp config_controller/etc/memcached.conf /etc/memcached.conf
systemctl enable memcached
systemctl restart memcached

echo "Installing etcd..."

apt-get install etcd -y
cp config_controller/etc/default/etcd /etc/default/etcd
systemctl enable etcd
systemctl restart etcd

echo "Installing keystone..."

mysql -e "CREATE DATABASE keystone"
mysql -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'bf565ef90c2cc471870e'"
mysql -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'bf565ef90c2cc471870e'"
apt-get install keystone -y
cp config_controller/etc/keystone/keystone.conf /etc/keystone/keystone.conf
su -s /bin/sh -c "keystone-manage db_sync" keystone
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
keystone-manage bootstrap --bootstrap-password password --bootstrap-admin-url http://controller:5000/v3/ --bootstrap-internal-url http://controller:5000/v3/ --bootstrap-public-url http://controller:5000/v3/ --bootstrap-region-id RegionOne
cp config_controller/etc/apache2/apache2.conf /etc/apache2/apache2.conf
systemctl enable apache2
systemctl restart apache2
source openrc
openstack project create --domain default --description "Service Project" service

echo "Installing horizon..."

apt-get install openstack-dashboard -y
cp config_controller/etc/openstack-dashboard/local_settings.py /etc/openstack-dashboard/local_settings.py
systemctl reload apache2.service

echo "Installing nova..."

mysql -e "CREATE DATABASE nova_api"
mysql -e "CREATE DATABASE nova"
mysql -e "CREATE DATABASE nova_cell0"
mysql -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY 'b3fdcdf9e449954aca1f'"
mysql -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY 'b3fdcdf9e449954aca1f'"
mysql -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY 'b3fdcdf9e449954aca1f'"
mysql -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY 'b3fdcdf9e449954aca1f'"
mysql -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY 'b3fdcdf9e449954aca1f'"
mysql -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY 'b3fdcdf9e449954aca1f'"
openstack user create --domain default --password 8630154703e207fa9cd6 nova
openstack role add --project service --user nova admin
openstack service create --name nova --description "OpenStack Compute" compute
openstack endpoint create --region RegionOne compute public http://controller:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://controller:8774/v2.1
openstack endpoint create --region RegionOne compute admin http://controller:8774/v2.1
apt-get install nova-api nova-conductor nova-novncproxy nova-scheduler -y
cp config_controller/etc/nova/nova.conf /etc/nova/nova.conf
su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
su -s /bin/sh -c "nova-manage db sync" nova
systemctl enable nova-api
systemctl enable nova-scheduler
systemctl enable nova-conductor
systemctl enable nova-novncproxy
systemctl restart nova-api
systemctl restart nova-scheduler
systemctl restart nova-conductor
systemctl restart nova-novncproxy

echo "Installing placement..."

mysql -e "CREATE DATABASE placement"
mysql -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '9a9edae60ab9c4518fb5'"
mysql -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '9a9edae60ab9c4518fb5'"
openstack user create --domain default --password c500612adcc8bedf1c64 placement
openstack role add --project service --user placement admin
openstack service create --name placement --description "Placement API" placement
openstack endpoint create --region RegionOne placement public http://controller:8778
openstack endpoint create --region RegionOne placement internal http://controller:8778
openstack endpoint create --region RegionOne placement admin http://controller:8778
apt-get install placement-api -y
cp config_controller/etc/placement/placement.conf /etc/placement/placement.conf
su -s /bin/sh -c "placement-manage db sync" placement
systemctl restart apache2

echo "Installing neutron..."

mysql -e "CREATE DATABASE neutron"
mysql -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '7a99148fa4c3815213a2'"
mysql -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '7a99148fa4c3815213a2'"
openstack user create --domain default --password fdcd112fbb12bcd0c963 neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron --description "OpenStack Networking" network
openstack endpoint create --region RegionOne network public http://controller:9696
openstack endpoint create --region RegionOne network internal http://controller:9696
openstack endpoint create --region RegionOne network admin http://controller:9696
apt-get install neutron-server neutron-plugin-ml2 neutron-linuxbridge-agent neutron-dhcp-agent neutron-metadata-agent -y
cp config_controller/etc/neutron/neutron.conf /etc/neutron/neutron.conf
cp config_controller/etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini
cp config_controller/etc/neutron/plugins/ml2/linuxbridge_agent.ini /etc/neutron/plugins/ml2/linuxbridge_agent.ini
cp config_controller/etc/neutron/dhcp_agent.ini /etc/neutron/dhcp_agent.ini
cp config_controller/etc/neutron/metadata_agent.ini /etc/neutron/metadata_agent.ini
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
systemctl restart nova-api
systemctl enable neutron-server
systemctl enable neutron-linuxbridge-agent
systemctl enable neutron-dhcp-agent
systemctl enable neutron-metadata-agent
systemctl restart neutron-server
systemctl restart neutron-linuxbridge-agent
systemctl restart neutron-dhcp-agent
systemctl restart neutron-metadata-agent
openstack network create --share --external --provider-physical-network provider --provider-network-type flat provider
openstack subnet create --network provider --allocation-pool start=192.168.0.20,end=192.168.0.40 --dns-nameserver 192.168.0.2 --gateway 192.168.0.254 --subnet-range 192.168.0.0/24 provider

echo "Installing glance..."

mysql -e "CREATE DATABASE glance"
mysql -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '0e530eca9e80263a3881'"
mysql -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '0e530eca9e80263a3881'"
openstack user create --domain default --password 5279b1202390a0e6ae81 glance
openstack role add --project service --user glance admin
openstack service create --name glance --description "OpenStack Image" image
openstack endpoint create --region RegionOne image public http://controller:9292
openstack endpoint create --region RegionOne image internal http://controller:9292
openstack endpoint create --region RegionOne image admin http://controller:9292
apt-get install glance -y
cp config_controller/etc/glance/glance-api.conf /etc/glance/glance-api.conf
su -s /bin/sh -c "glance-manage db_sync" glance
systemctl enable glance-api
systemctl restart glance-api

echo "Installing swift..."

openstack user create --domain default --password e7879e43e99725492165 swift
openstack role add --project service --user swift admin
openstack service create --name swift --description "OpenStack Object Storage" object-store
openstack endpoint create --region RegionOne object-store public http://controller:8080/v1/AUTH_%\(project_id\)s
openstack endpoint create --region RegionOne object-store internal http://controller:8080/v1/AUTH_%\(project_id\)s
openstack endpoint create --region RegionOne object-store admin http://controller:8080/v1
apt-get install swift swift-proxy xfsprogs rsync python3-swiftclient python3-keystoneclient python3-keystonemiddleware -y
cp config_controller/etc/swift/proxy-server.conf /etc/swift/proxy-server.conf
mkfs.xfs /dev/sdc -f
mkfs.xfs /dev/sdd -f
mkfs.xfs /dev/sde -f
mkfs.xfs /dev/sdf -f
mkdir -p /srv/node/sdc
mkdir -p /srv/node/sdd
mkdir -p /srv/node/sde
mkdir -p /srv/node/sdf
echo "$(blkid | grep "/dev/sdc" | awk '{print $2}') /srv/node/sdc xfs noatime 0 2" >> /etc/fstab
echo "$(blkid | grep "/dev/sdd" | awk '{print $2}') /srv/node/sdd xfs noatime 0 2" >> /etc/fstab
echo "$(blkid | grep "/dev/sde" | awk '{print $2}') /srv/node/sde xfs noatime 0 2" >> /etc/fstab
echo "$(blkid | grep "/dev/sdf" | awk '{print $2}') /srv/node/sdf xfs noatime 0 2" >> /etc/fstab
mount -a
cp config_controller/etc/rsyncd.conf /etc/rsyncd.conf
cp config_controller/etc/default/rsync /etc/default/rsync
apt-get install swift-account swift-container swift-object -y
cp config_controller/etc/swift/account-server.conf /etc/swift/account-server.conf
cp config_controller/etc/swift/container-server.conf /etc/swift/container-server.conf
cp config_controller/etc/swift/object-server.conf /etc/swift/object-server.conf
chown -R swift:swift /srv/node
mkdir -p /var/cache/swift
chown -R root:swift /var/cache/swift
chmod -R 775 /var/cache/swift
swift-ring-builder account.builder create 10 3 1
swift-ring-builder account.builder add --region 1 --zone 1 --ip 192.168.0.100 --port 6202 --device sdc --weight 100
swift-ring-builder account.builder add --region 1 --zone 1 --ip 192.168.0.100 --port 6202 --device sdd --weight 100
swift-ring-builder account.builder add --region 1 --zone 1 --ip 192.168.0.100 --port 6202 --device sde --weight 100
swift-ring-builder account.builder add --region 1 --zone 1 --ip 192.168.0.100 --port 6202 --device sdf --weight 100
swift-ring-builder account.builder rebalance
swift-ring-builder container.builder create 10 3 1
swift-ring-builder container.builder add --region 1 --zone 1 --ip 192.168.0.100 --port 6201 --device sdc --weight 100
swift-ring-builder container.builder add --region 1 --zone 1 --ip 192.168.0.100 --port 6201 --device sdd --weight 100
swift-ring-builder container.builder add --region 1 --zone 1 --ip 192.168.0.100 --port 6201 --device sde --weight 100
swift-ring-builder container.builder add --region 1 --zone 1 --ip 192.168.0.100 --port 6201 --device sdf --weight 100
swift-ring-builder container.builder rebalance
swift-ring-builder object.builder create 10 3 1
swift-ring-builder object.builder add --region 1 --zone 1 --ip 192.168.0.100 --port 6200 --device sdc --weight 100
swift-ring-builder object.builder add --region 1 --zone 1 --ip 192.168.0.100 --port 6200 --device sdd --weight 100
swift-ring-builder object.builder add --region 1 --zone 1 --ip 192.168.0.100 --port 6200 --device sde --weight 100
swift-ring-builder object.builder add --region 1 --zone 1 --ip 192.168.0.100 --port 6200 --device sdf --weight 100
swift-ring-builder object.builder rebalance
mv *.builder /etc/swift/
mv *.gz /etc/swift/
cp config_controller/etc/swift/swift.conf /etc/swift/swift.conf
chown -R root:swift /etc/swift
systemctl restart memcached
systemctl enable swift-proxy
swift-init all start

echo "Installing cinder..."

mysql -e "CREATE DATABASE cinder"
mysql -e "GRANT ALL PRIVILEGES ON glance.* TO 'cinder'@'localhost' IDENTIFIED BY '19bec285257296906109'"
mysql -e "GRANT ALL PRIVILEGES ON glance.* TO 'cinder'@'%' IDENTIFIED BY '19bec285257296906109'"
openstack user create --domain default --password c4e3a467213dd23bbf2a cinder
openstack role add --project service --user cinder admin
openstack service create --name cinderv2 --description "OpenStack Block Storage" volumev2
openstack service create --name cinderv3 --description "OpenStack Block Storage" volumev3
openstack endpoint create --region RegionOne volumev2 public http://controller:8776/v2/%\(project_id\)s
openstack endpoint create --region RegionOne volumev2 internal http://controller:8776/v2/%\(project_id\)s
openstack endpoint create --region RegionOne volumev2 admin http://controller:8776/v2/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 public http://controller:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 internal http://controller:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 admin http://controller:8776/v3/%\(project_id\)s
apt-get install cinder-api cinder-scheduler cinder-volume cinder-backup install lvm2 thin-provisioning-tools -y
cp config_controller/etc/cinder/cinder.conf /etc/cinder/cinder.conf
su -s /bin/sh -c "cinder-manage db sync" cinder
wipefs /dev/sdb -a
pvcreate /dev/sdb
vgcreate cinder-volumes /dev/sdb
cp config_controller/etc/lvm/lvm.conf /etc/lvm/lvm.conf
systemctl restart nova-api
systemctl enable tgt
systemctl enable cinder-scheduler
systemctl enable cinder-volume
systemctl enable cinder-backup
systemctl restart tgt
systemctl restart cinder-scheduler
systemctl restart cinder-volume
systemctl restart apache2
systemctl restart cinder-backup
