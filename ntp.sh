#!/usr/bin/env bash
#
# Author:       Seaton Jiang <seaton@vtrois.com>
# Github URL:   https://github.com/vtrois/spacepack
# License:      MIT

export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin

RGB_DANGER='\033[31;1m'
RGB_WAIT='\033[37;2m'
RGB_SUCCESS='\033[32m'
RGB_WARNING='\033[33;1m'
RGB_INFO='\033[36;1m'
RGB_END='\033[0m'

TENCENTCLOUD=$( wget -qO- -t1 -T2 metadata.tencentyun.com )
LOCK=/tmp/spacepack_ntp.log

tool_info() {
    echo -e "========================================================================================="
    echo -e "                                 NTP server for SpacePack                                "
    echo -e "          For more information please visit https://github.com/vtrois/spacepack          "
    echo -e "========================================================================================="
}

check_root(){
    if [[ $EUID -ne 0 ]]; then
       echo -e "${RGB_DANGER}The script must be run as root!${RGB_END}"
       exit 1
    fi
}

check_lock() {
    if [ ! -f "$LOCK" ];then
    touch $LOCK
    fi
}

check_os() {
    if [ -f /etc/redhat-release ]; then
        RELEASE="centos"
    elif cat /etc/issue | grep -Eqi "debian"; then
        RELEASE="debian"
    elif cat /etc/issue | grep -Eqi "ubuntu"; then
        RELEASE="ubuntu"
    elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
        RELEASE="centos"
    elif cat /proc/version | grep -Eqi "debian"; then
        RELEASE="debian"
    elif cat /proc/version | grep -Eqi "ubuntu"; then
        RELEASE="ubuntu"
    elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
        RELEASE="centos"
    else
        RELEASE="unknown"
    fi
    if [ "${RELEASE}" == "ubuntu" ] || [ "${RELEASE}" == "debian" ];then
        apt-get -y update >> ${LOCK} 2>&1
        apt-get -y install ntp >> ${LOCK} 2>&1
    elif [ "${RELEASE}" = "centos" ];then
        yum -y install ntp >> ${LOCK} 2>&1
    else
        echo -e "${RGB_DANGER}The script does not support your OS!${RGB_END}"
        exit 1
    fi
}

public_ip() {
    if [ ! -z "${TENCENTCLOUD}" ]; then
        local IP=$( wget -qO- -t1 -T2 metadata.tencentyun.com/latest/meta-data/public-ipv4 )
    else
        local IP=$( wget -qO- -t1 -T2 ipv4.icanhazip.com )
    fi
    [ -z ${IP} ] && IP=$( wget -qO- -t1 -T2 ipinfo.io/ip )
    [ ! -z "${IP}" ] && echo ${IP} || echo -e "${RGB_DANGER}Unknown${RGB_END}"
}

install_module() {
    echo -e "\n${RGB_INFO}1/4 : Check and install the necessary module${RGB_END}"
    echo -en "${RGB_WAIT}Checking...${RGB_END}"
    check_os
    echo -e "\r${RGB_SUCCESS}Success, the script is ready to be installed!${RGB_END}"
}

ntp_conf() {
    echo -en "\n${RGB_INFO}2/4 : Please input the network address (Default is 0.0.0.0):${RGB_END}"
    read NETWORKADDRESS
    [ -z "${NETWORKADDRESS}" ] && NETWORKADDRESS=0.0.0.0
    echo -e "${RGB_SUCCESS}Success, the network address is setup complete!${RGB_END}"
    echo -en "\n${RGB_INFO}3/4 : Please input the netmask (Default is 0.0.0.0):${RGB_END}"
    read NETMASK
    [ -z "${NETMASK}" ] && NETMASK=0.0.0.0
    echo -e "${RGB_SUCCESS}Success, the netmask is setup complete!${RGB_END}"
    if [ ! -z "${TENCENTCLOUD}" ]; then
        TENCENTSERVER='server ntpupdate.tencentyun.com'
    fi
cat > /etc/ntp.conf <<END
driftfile /var/lib/ntp/drift
logfile /var/log/ntp.log
restrict default kod nomodify notrap nopeer noquery
restrict -6 default kod nomodify notrap nopeer noquery
restrict 127.0.0.1
restrict -6 ::1
restrict ${NETWORKADDRESS} mask ${NETMASK} nomodify notrap
${TENCENTSERVER}
server 0.cn.pool.ntp.org
server 1.cn.pool.ntp.org
server 2.cn.pool.ntp.org
server 3.cn.pool.ntp.org
server 127.127.1.0 iburst local clock
includefile /etc/ntp/crypto/pw
keys /etc/ntp/keys
END
}

start_up() {
    if [ "${RELEASE}" == "ubuntu" ] || [ "${RELEASE}" == "debian" ];then
        /etc/init.d/ntp restart >> ${LOCK} 2>&1
    elif [ "${RELEASE}" = "centos" ];then
        CENTOSVERSION=$( rpm -q centos-release | cut -d- -f3 )
        if [ "${CENTOSVERSION}" == "7" ];then
            systemctl restart ntpd >> ${LOCK} 2>&1
            systemctl enable ntpd >> ${LOCK} 2>&1
        elif [ "${CENTOSVERSION}" == "6" ];then
            service ntpd restart >> ${LOCK} 2>&1
            chkconfig ntpd on >> ${LOCK} 2>&1
        else
            echo -e "${RGB_DANGER}The system version needs to be more than Centos 6.x!${RGB_END}"
            exit 1
        fi
    fi
    local PUBLICIP=$( public_ip )
    echo -e "\n${RGB_WARNING}Client use command [ntpdate -u ${PUBLICIP}]${RGB_END}"
    echo -e "\n${RGB_WARNING}If you use Tencent Cloud or other, please enable [UDP:123] for SecurityGroup!${RGB_END}"
}

clear
check_root
check_lock
tool_info
install_module
ntp_conf
start_up