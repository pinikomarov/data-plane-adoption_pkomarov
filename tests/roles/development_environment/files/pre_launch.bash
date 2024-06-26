set -e

# Create Image
IMG=cirros-0.5.2-x86_64-disk.img
URL=http://download.cirros-cloud.net/0.5.2/$IMG
DISK_FORMAT=qcow2
RAW=$IMG
curl -L -# $URL > /tmp/$IMG
if type qemu-img >/dev/null 2>&1; then
    RAW=$(echo $IMG | sed s/img/raw/g)
    qemu-img convert -f qcow2 -O raw /tmp/$IMG /tmp/$RAW
    DISK_FORMAT=raw
fi
${BASH_ALIASES[openstack]} image show cirros || \
    ${BASH_ALIASES[openstack]} image create --container-format bare --disk-format $DISK_FORMAT cirros < /tmp/$RAW

# Create flavor
${BASH_ALIASES[openstack]} flavor show m1.small || \
    ${BASH_ALIASES[openstack]} flavor create --ram 512 --vcpus 1 --disk 1 --ephemeral 1 m1.small

# Create networks
${BASH_ALIASES[openstack]} network show private || ${BASH_ALIASES[openstack]} network create private --share
${BASH_ALIASES[openstack]} subnet show priv_sub || ${BASH_ALIASES[openstack]} subnet create priv_sub --subnet-range 192.168.0.0/24 --network private
${BASH_ALIASES[openstack]} network show public || ${BASH_ALIASES[openstack]} network create public --external --provider-network-type flat --provider-physical-network datacentre
${BASH_ALIASES[openstack]} subnet show pub_sub || \
    ${BASH_ALIASES[openstack]} subnet create pub_sub --subnet-range 192.168.122.0/24 --allocation-pool start=192.168.122.200,end=192.168.122.210 --gateway 192.168.122.1 --no-dhcp --network public
${BASH_ALIASES[openstack]} router show priv_router || {
    ${BASH_ALIASES[openstack]} router create priv_router
    ${BASH_ALIASES[openstack]} router add subnet priv_router priv_sub
    ${BASH_ALIASES[openstack]} router set priv_router --external-gateway public
}

# Create a floating IP
${BASH_ALIASES[openstack]} floating ip show 192.168.122.20 || \
    ${BASH_ALIASES[openstack]} floating ip create public --floating-ip-address 192.168.122.20

# Create a test instance
${BASH_ALIASES[openstack]} server show test || {
    ${BASH_ALIASES[openstack]} server create --flavor m1.small --image cirros --nic net-id=private test --wait
    ${BASH_ALIASES[openstack]} server add floating ip test 192.168.122.20
}

# Create security groups
${BASH_ALIASES[openstack]} security group rule list --protocol icmp --ingress -f json | grep -q '"IP Range": "0.0.0.0/0"' || \
    ${BASH_ALIASES[openstack]} security group rule create --protocol icmp --ingress --icmp-type -1 $(${BASH_ALIASES[openstack]} security group list --project admin -f value -c ID)
${BASH_ALIASES[openstack]} security group rule list --protocol tcp --ingress -f json | grep '"Port Range": "22:22"' || \
    ${BASH_ALIASES[openstack]} security group rule create --protocol tcp --ingress --dst-port 22 $(${BASH_ALIASES[openstack]} security group list --project admin -f value -c ID)

# check connectivity via FIP
# FIXME: defer __network_adoption__ - this doesn't work yet in the adoption procedure
#ping -c4 192.168.122.20

# FIXME: Invalid volume: Volume xxx status must be available, but current status is: backing-up
# Create a Cinder volume, a backup from it, and snapshot it.
#${BASH_ALIASES[openstack]} volume show disk || \
#    ${BASH_ALIASES[openstack]} volume create --image cirros --bootable --size 1 disk
#${BASH_ALIASES[openstack]} volume backup show backup || \
#    ${BASH_ALIASES[openstack]} volume backup create --name backup disk
#${BASH_ALIASES[openstack]} volume snapshot show snapshot || \
#    ${BASH_ALIASES[openstack]} volume snapshot create --volume disk snapshot

# TODO: Add volume to the test VM, after tripleo wallaby (osp 17) isolnet network adoption implemented for storage networks
#${BASH_ALIASES[openstack]} volume show disk -f json | jq -r '.status' | grep -q available && \
#    ${BASH_ALIASES[openstack]} server add volume test disk

export FIP=192.168.122.20