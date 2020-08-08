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

PASSWORD=$( cat /dev/urandom | head -n 10 | md5sum | head -c 10 )
ETH=$( route | grep default | awk '{print $NF}' )
TENCENTCLOUD=$( wget -qO- -t1 -T2 metadata.tencentyun.com )
LOCK=/tmp/spacepack_pptp.log

tool_info() {
    echo -e "========================================================================================="
    echo -e "                                 PPTP tool for SpacePack                                 "
    echo -e "          For more information please visit https://github.com/vtrois/spacepack          "
    echo -e "========================================================================================="
}

show_help() {
    version
    echo -e "\nUsage: $0 [OPTION]"
    echo -e "\nOption:"
    echo -e "  -i,  --install          install the pptp."
    echo -e "  -l,  --list             list of the pptp users."
    echo -e "  -a,  --add              add the user for pptp."
    echo -e "  -d,  --del              delete the user for pptp."
    echo -e "  -m,  --mod              modify the user password."
    echo -e "  -v,  --version          show the version info."
    echo -e "  -h,  --help             print this help."
    echo -e "\nMail bug reports and suggestions to <support@vtrois.com>."
}

version() {
  echo "PPTP tool version 1.1"
}

check_root(){
    if [[ $EUID -ne 0 ]]; then
       echo -e "${RGB_DANGER}The script must be run as root!${RGB_END}"
       exit 1
    fi
}

check_tun(){
    if [[ ! -e /dev/net/tun ]]; then
        echo -e "${RGB_DANGER}TUN/TAP is not available!${RGB_END}"
        exit 1
    fi
}

check_lock() {
    if [ -f "$LOCK" ];then
    echo -e "\n${RGB_DANGER}The PPTP has been installed, please use $0 -h to consult the help.${RGB_END}"
    exit 1
    else
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
    if [ "${RELEASE}" = "ubuntu" ] || [ "${RELEASE}" = "debian" ];then
        for PACKAGE in wget pptpd ppp iptables
        do
        apt-get -y update >> ${LOCK} 2>&1
        apt-get -y install ${PACKAGE} >> ${LOCK} 2>&1
        done
    elif [ "${RELEASE}" = "centos" ];then
        CENTOSVERSION=$( rpm -q centos-release | cut -d- -f3 )
        if [ "${CENTOSVERSION}" == "7" ];then
            for PACKAGE in wget ppp pptpd firewalld
            do
                yum -y update >> ${LOCK} 2>&1
                yum -y install ${PACKAGE} >> ${LOCK} 2>&1
            done
        elif [ "${CENTOSVERSION}" == "6" ];then
            for PACKAGE in wget ppp iptables
            do
                yum -y update >> ${LOCK} 2>&1
                yum -y install ${PACKAGE} >> ${LOCK} 2>&1
            done
            rpm -Uvh http://poptop.sourceforge.net/yum/stable/rhel6/pptp-release-current.noarch.rpm >> ${LOCK} 2>&1
            yum -y install pptpd >> ${LOCK} 2>&1
        else
            echo -e "${RGB_DANGER}The system version needs to be more than Centos 6.x!${RGB_END}"
            exit 1
        fi
    else
        echo -e "${RGB_DANGER}The tool does not support your OS!${RGB_END}"
        exit 1
    fi
    sed -i 's@^net.ipv4.tcp_syncookies.*@#net.ipv4.tcp_syncookies = 1@g' /etc/sysctl.conf >> ${LOCK} 2>&1
    sed -i 's@^net.ipv4.ip_forward.*@#net.ipv4.ip_forward = 0@g' /etc/sysctl.conf >> ${LOCK} 2>&1
    echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf >> ${LOCK} 2>&1
    sysctl -p >> ${LOCK} 2>&1
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

iptables_centos() {
    iptables -t nat -A POSTROUTING -o ${ETH} -j MASQUERADE
    iptables -A FORWARD -p tcp --syn -s 176.16.0.0/16 -j TCPMSS --set-mss 1356
    service iptables save
    service iptables restart
    chkconfig iptables on
}

iptables_ubuntu() {
    iptables -I INPUT -p tcp --dport 1723 -j ACCEPT
    iptables -I INPUT  --protocol 47 -j ACCEPT
    iptables -t nat -A POSTROUTING -o ${ETH} -j MASQUERADE
    iptables -I FORWARD -s 176.16.0.0/16 -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -j TCPMSS --set-mss 1356
    iptables-save >/etc/iptables-rules
    echo 'iptables-restore /etc/iptables-rules' >> /etc/rc.local
    chmod +x /etc/rc.local
}

firewall_centos() {
    systemctl restart firewalld.service
    systemctl enable firewalld.service
    firewall-cmd --set-default-zone=public
    firewall-cmd --add-interface=${ETH}
    firewall-cmd --add-port=1723/tcp --permanent
    firewall-cmd --add-port=47/tcp --permanent
    firewall-cmd --add-masquerade --permanent
    firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -i ${ETH} -p gre -j ACCEPT
    firewall-cmd --reload
}

install_pptp() {
    echo -e "\n${RGB_INFO}1/4 : Check and install the PPTP module${RGB_END}"
    echo -en "${RGB_WAIT}Checking...${RGB_END}"
    check_os
    echo -e "\r${RGB_SUCCESS}Success, the script is ready to be installed!${RGB_END}"
}

userpass_conf() {
    echo -en "\n${RGB_INFO}2/4 : Please input a username (Default is spacepack):${RGB_END}"
    read USERNAME
    [ -z ${USERNAME} ] && USERNAME="spacepack"
    echo -e "${RGB_SUCCESS}Success, the username is setup complete!${RGB_END}"
    echo -en "\n${RGB_INFO}3/4 : Please input a password (Default is ${PASSWORD}):${RGB_END}"
    read NPASSWORD
    [ -z ${NPASSWORD} ] && NPASSWORD=${PASSWORD}
    echo -e "${RGB_SUCCESS}Success, the password is setup complete!${RGB_END}"
}

pptp_conf() {
    echo -e "\n${RGB_INFO}4/4 : Configure the PPTP settings${RGB_END}"
    echo -en "${RGB_WAIT}Configuring...${RGB_END}"
    echo "${USERNAME} pptpd ${NPASSWORD} *" >> /etc/ppp/chap-secrets
cat >/etc/pptpd.conf <<END
option /etc/ppp/options.pptpd
localip 172.16.0.1
remoteip 172.16.0.100-200
END
cat >/etc/ppp/options.pptpd <<END
name pptpd
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
require-mppe-128
ms-dns 119.29.29.29
ms-dns 223.5.5.5
ms-dns 1.1.1.1
proxyarp
lock
nobsdcomp 
novj
novjccomp
nologfd
END
    if [ "${RELEASE}" != "centos" ];then
        iptables_ubuntu >> ${LOCK} 2>&1
        /etc/init.d/pptpd restart >> ${LOCK} 2>&1
    else
        if [ "${CENTOSVERSION}" == "7" ];then
            firewall_centos >> ${LOCK} 2>&1
            systemctl restart pptpd.service >> ${LOCK} 2>&1
            systemctl enable pptpd.service >> ${LOCK} 2>&1
        elif [ "${CENTOSVERSION}" == "6" ];then
            iptables_centos >> ${LOCK} 2>&1
            service pptpd restart >> ${LOCK} 2>&1
            chkconfig pptpd on >> ${LOCK} 2>&1
        fi
    fi
    echo -e "\r${RGB_SUCCESS}Success, configuration completion!${RGB_END}\n"
}

finish_conf() {
    PUBLICIP=$( public_ip )
    echo -e "${RGB_WARNING}PPTP Overview (Contains the Username, Password and IP address)${RGB_END}"
    echo -e "Public IP      : ${PUBLICIP}"
    echo -e "Username       : ${USERNAME}"
    echo -e "Password       : ${NPASSWORD}"
}

list_users() {
    if [ ! -f /etc/ppp/chap-secrets ];then
        echo -e "${RGB_DANGER}Please confirm whether to install PPTP!${RGB_END}"
        exit 1
    fi
    clear
    tool_info
    echo -e "\n${RGB_WARNING}The user list (Contains the Username and Password)${RGB_END}"
    grep -v "^#" /etc/ppp/chap-secrets | awk '{printf "\033[36mUsername:\033[0m  %-20s \t \033[36mPassword:\033[0m  %-20s\n",$1,$3}'
}

add_user() {
    clear
    tool_info
    echo -en "\n${RGB_INFO}1/2 : Please input a username (Default is spacepack):${RGB_END}"
    read USERNAME
    [ -z ${USERNAME} ] && USERNAME="spacepack"
    echo -e "${RGB_SUCCESS}Success, the username is setup complete!${RGB_END}"
    echo -en "\n${RGB_INFO}2/2 : Please input a password (Default is ${PASSWORD}):${RGB_END}"
    read NPASSWORD
    [ -z ${NPASSWORD} ] && NPASSWORD=${PASSWORD}
    echo -e "${RGB_SUCCESS}Success, the password is setup complete!${RGB_END}\n"
    echo "${USERNAME} pptpd ${NPASSWORD} *" >> /etc/ppp/chap-secrets
    finish_conf
}

del_user(){
    clear
    tool_info
    while :
    do
        echo -en "\n${RGB_INFO}Please input the username you want to delete:${RGB_END}"
        read USERNAME
        if [ -z ${USERNAME} ]; then
            echo -e "${RGB_DANGER}Username can not be empty!${RGB_END}"
        else
            grep -w "${USERNAME}" /etc/ppp/chap-secrets >/dev/null 2>&1
            if [ $? -eq 0 ];then
                break
            else
                echo -e "${RGB_DANGER}The user name does not exist, please enter again!${RGB_END}"
            fi
        fi
    done
    sed -i "/^\<${USERNAME}\>/d" /etc/ppp/chap-secrets
    echo -e "${RGB_SUCCESS}Success, the username is delete completed!${RGB_END}"
}

mod_user(){
    clear
    tool_info
    while :
    do
        echo -en "\n${RGB_INFO}Please input the username you want to change password:${RGB_END}"
        read USERNAME
        if [ -z ${USERNAME} ]; then
            echo -e "${RGB_DANGER}Username can not be empty!${RGB_END}"
        else
            grep -w "${USERNAME}" /etc/ppp/chap-secrets >/dev/null 2>&1
            if [ $? -eq 0 ];then
                break
            else
                echo -e "${RGB_DANGER}The user name does not exist, please enter again!${RGB_END}"
            fi
        fi
    done
    echo -en "\n${RGB_INFO}Please input a password (Default is ${PASSWORD}):${RGB_END}"
    read NPASSWORD
    [ -z ${NPASSWORD} ] && NPASSWORD=${PASSWORD}
    sed -i "/^\<${USERNAME}\>/d" /etc/ppp/chap-secrets
    echo "${USERNAME} pptpd ${NPASSWORD} *" >> /etc/ppp/chap-secrets
    echo -e "${RGB_SUCCESS}Success, the password has been changed!${RGB_END}"
}

install() {
    clear
    tool_info
    check_root
    check_tun
    check_lock
    install_pptp
    userpass_conf
    pptp_conf
    finish_conf
    echo -e "\n${RGB_WARNING}If you use Tencent Cloud or other, please enable [TCP:1723,47] for SecurityGroup!${RGB_END}"
}

ACTION=$1
[ -z $1 ] && ACTION=install
case ${ACTION} in
    install)
        install
        ;;
    -i|--install)
        install
        ;;
    -l|--list)
        list_users
        ;;
    -a|--add)
        add_user
        ;;
    -d|--del)
        del_user
        ;;
    -m|--mod)
        mod_user
        ;;
    -v|--version)
        version
        ;;
    -h|--help)
        show_help
        ;;
    *)
        echo -e "Unknown option: $1"
        echo -e "\nUsage: [-i,--install] [-l,--list] [-a,--add] [-d,--del]"
        echo -e "         [-m,--mod] [-v,--version] [-h,--help]"
        exit 1
        ;;
esac