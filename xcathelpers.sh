# Copyright 2015-2016 University of Warwick
# Published under ASL-2: https://www.apache.org/licenses/LICENSE-2.0.html

# logs to xcat and stderr
log() {
    local level="$1"
    shift
    logger -t xcat -p "local4.${level}" "$@"
    echo "$@" >&2
}

# build newline separated list of interfaces
IFLIST="$(echo ${NICIPS} |tr -d '|' |tr ',' '\n')"

get_nic_ip() {
    local if="$1"
    echo $(echo -e "${IFLIST}" | grep -w "${if}" |head -n 1 | cut -d '!' -f2)
}

# Takes an attribute from nics(5) and interface name
# the attribute must be in uppercase variable form.
# ex: get_nic_attribute $NICHOSTNAMESUFFIXES br0
get_nic_attribute() {
    local if="$2"
    local attr="$1"
    echo "${attr}" | awk -F "${if}\!" '{print $2}' 2>/dev/null \
        | awk -F',' '{print $1}'
}

# Takes an attribute from networks(5) and interface name
# The attribute must be passed in lowercase.
# ex: get_nic_network gateway eth0
get_nic_network() {
    local if="$2"
    local query="$1"
    local netname="$(get_nic_attribute ${NICNETWORKS} ${if})"
    if [ -z "${netname}" ]; then
        log err "Could not get network name for ${if}"
        return
    fi
    for num in $(seq 1 $NETWORKS_LINES); do
        eval local net="\$NETWORKS_LINE${num}"
        if echo $net|grep -q "netname=${netname}"; then
            echo $net | awk -F"${query}=" '{ print $2 }' |cut -d \| -f1
            break
        else
            continue
        fi
    done
}

# Takes file name and a space separated list of VARIABLE=value
# strings that will be added or changed as required.
# ex: add_or_modify /etc/default/grub GRUB_TIMEOUT=5 GRUB_DISABLE_RECOVERY=false
add_or_modify() {
    local file="$1"
    shift
    for arg in "$@"; do
        local var="$(echo $arg|cut -d= -f1)"
        local val="$(echo $arg|cut -d= -f2-)"
        if grep -qs "^${var}=" "${file}"; then
            sed -i "/^${var}=/ s/=.*/=\"${val}\"/" "${file}"
        else
            echo "${var}=\"${val}\"" >> "${file}"
        fi
        log info "${file}: ${var}=${val}"
    done
}

# populates network configuration scripts from xCAT data (if present)
# and/or enables the given interfaces for next boot
# ex: persistent_if_rhel eth0 br0
persistent_if_rhel() {
    for dev in "$@"; do
        local nwconfig="/etc/sysconfig/network-scripts/ifcfg-${dev}"
        local nicip="$(get_nic_ip ${dev})"
        local nicextrap="$(get_nic_attribute ${NICEXTRAPARAMS} ${dev})"
        local gateway="$(get_nic_network gateway ${dev})"
        local netmask="$(get_nic_network mask ${dev})"

        add_or_modify "${nwconfig}" \
            "DEVICE=${dev}" ONBOOT=yes BOOTPROTO=none

        if [ -n "${nicip}" ]; then
            add_or_modify "${nwconfig}" "IPADDR=${nicip}"
        fi
        if [ -n "${nicextrap}" ]; then
            add_or_modify "${nwconfig}" $nicextrap # Don't quote
        fi
        if [ -n "${gateway}" ]; then
            add_or_modify "${nwconfig}" "GATEWAY=${gateway}"
        fi
        if [ -n "${netmask}" ]; then
            add_or_modify "${nwconfig}" "NETMASK=${netmask}"
        fi
        #ifup $dev
    done
}

persistent_if() {
    if grep -qE '(CentOS|Red Hat)' /etc/redhat-release; then
        persistent_if_rhel $@
    else
        log err "Only RHEL supported."
        exit 0
    fi
}

# vim: set expandtab ts=4 sw=4
