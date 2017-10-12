#!/bin/bash



enableSsh () {
    sudo touch "${bootPath}/ssh"
}



changeHostname () { # changeHostname(string hostname)
    newHostname=$1
    oldHostname=`sudo cat ${rootPath}/etc/hostname`
    sudo echo "${newHostname}" | sudo tee "${rootPath}/etc/hostname" > /dev/null
    sudo sed -i -e "s/${oldHostname}/${newHostname}/g" "${rootPath}/etc/hosts"
}



createUsbEthernet () { # createUsbEthernet()
    echo "
dtoverlay=dwc2" | sudo tee -a "${bootPath}/config.txt" > /dev/null
    sudo sed -i -e 's/rootwait/rootwait modules-load=dwc2,g_ether/g' "${bootPath}/cmdline.txt"
}



setupWifiClient () { # setupWifiClient(string ssid, string password)
    ssid=$1
    password=$2
    echo "
network={
    ssid=\"$1\"
    psk=\"$2\"
}" | sudo tee -a "${rootPath}/etc/wpa_supplicant/wpa_supplicant.conf" > /dev/null
}



setupWifiAp () { # setupWifiAp(bool usbEth, bool eth, string network, string ssid, string password, string channel, string dnsServer, string dhcpLeaseTime) 
    if [ ! -f "${rootPath}/etc/hostapd/hostapd.conf" ] || [ ! -f "${rootPath}/etc/default/hostapd" ] || [ ! -f "${rootPath}/etc/dnsmasq.conf" ]; then # dependencies not installed
        if [ "$rootPath" = "" ]; then # script is running on the raspi
            sudo apt-get install hostapd dnsmasq
        else # script runs on a different system
            echo "Can't set up AP because one or more dependencies are not installed on the raspi system."
            echo "You have to run this script on the Raspi directly or you need to run 'sudo apt-get install hostapd dnsmasq' on the raspi first."
            exit 2;
        fi
    fi
    
    usbEth=$1
    eth=$2
    network=$3
    ssid=$4
    password=$5
    channel=$6
    dnsServer=$7
    dhcpLeaseTime=$8
    usbPlaceHolder1=''
    usbPlaceHolder2=''
    ethPlaceholder1=''
    ethPlaceholder2=''
    if [ "$usbEth" = true ] ; then
        usbPlaceHolder1='auto usb0'
        usbPlaceHolder2='iface usb0 inet dhcp'
    fi
    if [ "$eth" = true ] ; then
        ethPlaceholder1='auto eth0'
        ethPlaceholder2='iface eth0 inet dhcp'
    fi
    ipPrefix=$(echo ${network%.0})
    
    sudo iw dev wlan0 interface add uap0 type __ap
    sudo ip addr add "${ipPrefix}.1/24" dev uap0
    
    sudo rm "${rootPath}/etc/hostapd/hostapd.conf"
    sudo echo "interface=uap0
ssid=${ssid}
hw_mode=g
channel=${channel}
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=${password}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP" | sudo tee -a "${rootPath}/etc/hostapd/hostapd.conf" > /dev/null
    
    sudo echo "DAEMON_CONF=\"/etc/hostapd/hostapd.conf\"" | sudo tee -a "${rootPath}/etc/default/hostapd" > /dev/null
    sudo echo "#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
iw dev wlan0 interface add uap0 type __ap
service dnsmasq restart
sysctl net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -s ${ipPrefix}.0/24 ! -d ${ipPrefix}.0/24 -j MASQUERADE
ifup uap0
hostapd /etc/hostapd/hostapd.conf" | sudo tee -a "${rootPath}/usr/local/bin/hostapdstart" > /dev/null
    
    sudo chmod 775 "${rootPath}/usr/local/bin/hostapdstart"
    sudo rm "${rootPath}/etc/dnsmasq.conf"
    sudo echo "interface=lo,uap0
no-dhcp-interface=lo,wlan0
bind-interfaces
server=${dnsServer}
domain-needed
bogus-priv
dhcp-range=${ipPrefix}.50,${ipPrefix}.150,${dhcpLeaseTime}" | sudo tee -a "${rootPath}/etc/dnsmasq.conf" > /dev/null
    
    sudo service dnsmasq restart
    sudo /etc/init.d/hostapd start
    sudo /etc/init.d/hostapd stop
    sudo /etc/init.d/hostapd restart
    
    #sudo echo "/bin/bash /usr/local/bin/hostapdstart" | sudo tee -a "${rootPath}/etc/rc.local" > /dev/null
    sudo sed -i -e 's/exit 0/\/bin\/bash \/usr\/local\/bin\/hostapdstart\nexit 0/g' "${rootPath}/etc/rc.local"
}



user_changeHostname () {
    echo ""
    read -p "Enter the new hostname: " newHostname
    changeHostname $newHostname
}



user_setupWifiClient () {
    echo ""
    read -p "Enter the ssid (name) of the WiFi netowrk: " ssid 
    read -p "Enter the password of the WiFi netowrk: " password 
    setupWifiClient $ssid $password
}



user_setupWifiAp () {
    echo ""
    read -p "Does your Raspberry Pi have an Ethernet port? [y|N] " eth
    if [ "$eth" = "y" ] || [ "$eth" = "Y" ]; then
        eth=true
    else
        eth=false
    fi
    read -p "You you want to simulate a USB Ethernet device (useful for ssh over USB)? [y|N] " usbEth
    if [ "$usbEth" = "y" ] || [ "$usbEth" = "Y" ]; then
        usbEth=true
    else
        usbEth=false
    fi
    read -p "Enter a valid 24bit network address (e.g.: 192.168.50.0): " network 
    read -p "Enter an SSID (name) for the AP (hotspot) that we are creating: " ssid 
    read -p "Enter a password min. 8 characters for the AP (hotspot) that we are creating: " password 
    read -p "Enter the a channel for example 11. If you use the Raspi as both client and AP, then the channel has to be identical! Channel: " channel 
    read -p "Enter the IP of a dns server (e.g.: 8.8.8.8): " dnsServer 
    read -p "Enter dhcp lease time that you like (e.g.: 12h): " dhcpLeaseTime 
    setupWifiAp $usbEth $eth $network $ssid $password $channel $dnsServer $dhcpLeaseTime
}



echo ""
echo "This script is not capable of undoing any of the changes it makes!"
echo ""
echo "This script expects default configuration files. If you have manually changed certain files, "
echo "you might lose your old configuration or end up with invalid config files."
echo "Please pay attention. The script will tell you which files are affected and ask you if you want to continue."
echo ""
echo "You can run this script on the Raspberry Pi directly or you can mount the SD card with Raspbian on a different device."
echo ""



echo "Enter the path to the boot partition of your Raspberry Pi."
echo "For example '/boot/' if you are running this script form your Raspi directly"
echo "or e.g. '/media/ubuntu/boot/' if you mounted the SD card partitions on another machine."
read -p "Enter boot path: " bootPath



echo "Enter the path to the root directory of your Raspberry Pi's root directory."
echo "For example '/' if you are running this script form your Raspi directly"
echo "or e.g. '/media/ubuntu/4tv3g5vgee6/' if you mounted the SD card partitions on another machine."
read -p "Enter root path: " rootPath 
echo ""



#Remove trailing slashes
length=${#bootPath}
last_char=${bootPath:length-1:1}
[[ $last_char == "/" ]] && bootPath=${bootPath:0:length-1}; :
length=${#rootPath}
last_char=${rootPath:length-1:1}
[[ $last_char == "/" ]] && rootPath=${rootPath:0:length-1}; :
echo "Raspi boot partition path: ${bootPath}/"
echo "Raspi root path: ${rootPath}/"
read -p "Do you wish to continue? [Y|n] " yn
case $yn in
    [Yy]* ) echo "Continuing.";;
    [Nn]* ) exit;;
    * ) echo "Continuing.";;
esac
echo ""


echo "Enableing ssh will create the following file '${bootPath}/ssh' unless it already exists."
read -p "Do you wish to enable ssh? [y|N]" yn
case $yn in
    [Yy]* ) enableSsh;;
    [Nn]* ) echo "Skipped.";;
    * ) echo "Skipped.";;
esac
echo ""


echo "Changing the hostname will "
echo "- overwrite this file '${rootPath}/etc/hostname' "
echo "- and will replace all occourences of the old hostname with the new hostname in '${rootPath}/etc/hosts'"
echo "  (So if your current hostname is e.g. a single letter then this file might get messed up.)"
read -p "Do you wish to change the hostname? [y|N]" yn
case $yn in
    [Yy]* ) user_changeHostname;;
    [Nn]* ) echo "Skipped.";;
    * ) echo "Skipped.";;
esac
echo ""



echo "Creating a USB Ethernet device will add one line to '${bootPath}/config.txt' and it will replace 'rootwait' with 'rootwait modules-load=dwc2,g_ether' in  '${bootPath}/cmdline.txt'."
echo "Please be aware, this can only be done once! If you do this multiple times, your cmdline.txt will most likely be invalid."
echo "If you also would like to make the Raspi act as an AP (hotspot), you have to do this first!"
read -p "Do you wish to create a USB Ethernet device? [y|N] " yn
case $yn in
    [Yy]* ) createUsbEthernet;;
    [Nn]* ) echo "Skipped.";;
    * ) echo "Skipped.";;
esac
echo ""


echo "Setting up the Raspi to auto connect to a WiFi AP will append a few lines to '${rootPath}/etc/wpa_supplicant/wpa_supplicant.conf'."
echo "Every time you do this, another network will be added to the configuration file. Just try to not add the same network twice."
echo "This has only be tested for standard WPA2 networks."
read -p "Do you wish to always automatically connect to a certain WiFi AP? [y|N] " yn
case $yn in
    [Yy]* ) user_setupWifiClient;;
    [Nn]* ) echo "Skipped.";;
    * ) echo "Skipped.";;
esac
echo ""



echo "You can set up the Raspi to act as an AP (hotspot)."
echo "This can be combined with the last option (connecting to another WiFi network). But it will only work, if they both use the same WiFi channel."
echo "Setting up the Raspi as a hotspot will:"
echo "- Overwrite all settings from '${rootPath}/etc/network/interfaces'."
echo "- Overwrite all settings from '${rootPath}/etc/hostapd/hostapd.conf'"
echo "- Add one line to '${rootPath}/etc/default/hostapd'. (Doing this multiple times might make the file invalid.)"
echo "- Create/overwrite a bash script: '${rootPath}/usr/local/bin/hostapdstart'."
echo "- Overwrite all settings from '${rootPath}/etc/dnsmasq.conf'."
echo "- Add one line to '${rootPath}/etc/rc.local'. (Doing this multiple times might cause unexpected behaviour.)"
read -p "Do you wish to set the Raspi up as an AP (hotspot)? [y|N] " yn
case $yn in
    [Yy]* ) user_setupWifiAp;;
    [Nn]* ) echo "Skipped.";;
    * ) echo "Skipped.";;
esac
