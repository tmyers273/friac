#!/bin/bash

LOGFILE='redis-setup.log'

touch $LOGFILE

# Functions

package_installed () {
  return $(dpkg-query -W -f='${Status}' $1 | grep -c "ok installed")
}

setup_multi_redis () {
  port=$1
  spaces=$2

  echo "$spaces Setting up multi redis instance on port $port"

  # Redis Config
  echo -ne "$spaces Setting up new redis config..."

  cp /etc/redis/redis.conf /etc/redis/redis_$port.conf

  sed -i "s/pidfile \/var\/run\/redis\/redis-server.pid/pidfile \/var\/run\/redis\/redis_$port.pid/g" /etc/redis/redis_$port.conf
  sed -i "s/port 6379/port $port/g" /etc/redis/redis_$port.conf
  sed -i "s/logfile \/var\/log\/redis\/redis-server.log/logfile \/var\/log\/redis\/redis_$port.log/g" /etc/redis/redis_$port.conf
  sed -i "s/dir \/var\/lib\/redis/dir \/var\/lib\/redis\/$port/g" /etc/redis/redis_$port.conf

  mkdir /var/lib/redis/$port >/dev/null 2>&1
  chown redis:redis /var/lib/redis/$port
  chown redis:redis /etc/redis/redis_$port.conf

  echo " done"

  # Service Config
  echo -ne "$spaces Setting up service config..."

  cp /etc/systemd/system/redis.service /etc/systemd/system/redis_$port.service

  sed -i "s/ExecStart=\/usr\/bin\/redis-server \/etc\/redis\/redis.conf/ExecStart=\/usr\/bin\/redis-server \/etc\/redis\/redis_$port.conf/g" /etc/systemd/system/redis_$port.service
  sed -i "s/PIDFile=\/var\/run\/redis\/redis-server.pid/PIDFile=\/var\/run\/redis\/redis_$port.pid/g" /etc/systemd/system/redis_$port.service
  sed -i "s/ReadWriteDirectories=-\/var\/lib\/redis/ReadWriteDirectories=-\/var\/lib\/redis\/$port/g" /etc/systemd/system/redis_$port.service
  sed -i "s/Alias=redis.service/Alias=redis_$port.service/g" /etc/systemd/system/redis_$port.service

  echo " done (/etc/systemd/system/redis_$port.service)"

  systemctl daemon-reload
  service redis_$port restart
}

# Init

echo "  ______ _____  _____          _____ "
echo " |  ____|  __ \|_   _|   /\   / ____|"
echo " | |__  | |__) | | |    /  \ | |     "
echo " |  __| |  _  /  | |   / /\ \| |     "
echo " | |    | | \ \ _| |_ / ____ \ |____ "
echo " |_|    |_|  \_\_____/_/    \_\_____|"
echo
echo "Fast Redis Installer and Configurator"
echo "By Tom Myers"
echo

# Setup
echo "Starting redis related stuff"
echo -ne "  Is redis-server already installed? "
redis_installed=$(package_installed redis-server)
if $redis_installed; then
  echo "  Yep. Skipping redis setup."
else
  echo -ne "  Starting redis setup..."
  add-apt-repository ppa:chris-lea/redis-server -y >> $LOGFILE 2>&1
  apt-get update >> $LOGFILE
  apt-get install redis-server -y >> $LOGFILE
  echo " done"
fi

# Config
read -p "  Enter a password for redis auth. Blank for random: " -r -e
if [[ $REPLY == '' ]]
then
    password=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
else
    password=$REPLY
fi
echo "  Password is: $password"

echo -ne "  Setting up configuration file..."
#sed -i ///g /etc/redis/redis.conf
sed -i '/exit 0/d' /etc/rc.local
sed -i "s/requirepass .*/requirepass $password/g" /etc/redis/redis.conf

echo "vm.overcommit_memory = 1" >> /etc/sysctl.conf
sysctl vm.overcommit_memory=1 >> $LOGFILE

echo "sysctl -w net.core.somaxconn=65535" >> /etc/rc.local
sysctl -w net.core.somaxconn=65535 >> $LOGFILE

echo "echo never > /sys/kernel/mm/transparent_hugepage/enabled" >> /etc/rc.local
echo never > /sys/kernel/mm/transparent_hugepage/enabled >> $LOGFILE

echo "exit 0" >> /etc/rc.local

echo " done"

# Bind to private ip

private_ip=$(curl -sS http://169.254.169.254/metadata/v1/interfaces/private/0/ipv4/address) 
public_ip=$(curl -sS http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)

read -p "  Do you want to expose this instance's private ip address? ($private_ip) (Y/n): " -r -e
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo -ne "  Binding private ip..."
    sed -i "s/bind 127\.0\.0\.1/bind 127\.0\.0\.1 $private_ip/g" /etc/redis/redis.conf
    echo " done"
fi

# Bind to public ip
read -p "  Do you want to expose this instance's PUBLIC ip address? ($public_ip) (Y/n): " -r -e
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo -ne "  Binding public ip..."
    sed -i "s/bind 127\.0\.0\.1/bind 127\.0\.0\.1 $public_ip/g" /etc/redis/redis.conf
    echo " done"
fi

# Restart Redis
echo -ne "  Restarting redis..."
service redis restart
echo " done"
echo

# Additional Instances
count=0
echo "Moving onto additional redis instances."
while 
  read -p "  Do you want to setup additional redis instances? (Y/n): " -r -e response &&
    [[ $response =~ ^[Yy]$ ]] 
do
  read -p "    Okay. What port do you want this new instance to run on? " -r -e
  echo "    Got it. Setting up another redis instance on port $REPLY..."
  setup_multi_redis $REPLY "     "
  Ports[$count]=$REPLY
  echo "    Setup complete on port $REPLY"
  ((count++))
done
echo

# Twemproxy
read -p "Do you want to install twemproxy now? (Y/n): " -r -e
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo "  Starting twemproxy setup"
    
    twemproxy_installed=$(package_installed twemproxy)
    if $twemproxy_installed; then
        echo "  Looks like twemproxy is already installed. Skipping installation."
    else
        echo -ne "  Adding repository..."
        add-apt-repository ppa:twemproxy/stable -y >> $LOGFILE 2>&1
        echo " done"
        echo -ne "  Updating packages..."
        apt-get update >> $LOGFILE
        echo " done"
        echo -ne "  Installing twemproxy..."
        apt-get install twemproxy -y >> $LOGFILE
        echo " done"
    fi

    echo -ne "  Setting up config..."
    mkdir /etc/nutcracker >/dev/null 2>&1
    rm /etc/nutcracker/nutcracker.yml
    touch /etc/nutcracker/nutcracker.yml
    touch /var/log/nutcracker.log

    echo "alpha:" >> /etc/nutcracker/nutcracker.yml
    echo "  listen: $public_ip:22121" >> /etc/nutcracker/nutcracker.yml
    echo "  hash: fnv1a_64" >> /etc/nutcracker/nutcracker.yml
    echo "  distribution: ketama" >> /etc/nutcracker/nutcracker.yml
    echo "  redis: true" >> /etc/nutcracker/nutcracker.yml
    echo "  redis_auth: $password" >> /etc/nutcracker/nutcracker.yml
    echo "  servers:" >> /etc/nutcracker/nutcracker.yml
    echo "   - 127.0.0.1:6379:1" >> /etc/nutcracker/nutcracker.yml
    for i in "${Ports[@]}"
    do
        echo "   - 127.0.0.1:$i:1" >> /etc/nutcracker/nutcracker.yml
    done
    echo " done"

    rm /etc/systemd/system/nutcracker.service
    touch /etc/systemd/system/nutcracker.service
    echo -ne "  Setting up service..."
    echo "[Unit]" >> /etc/systemd/system/nutcracker.service
    echo "Description=Twemproxy" >> /etc/systemd/system/nutcracker.service
    echo "After=network.target" >> /etc/systemd/system/nutcracker.service
    echo "Documentation=https://github.com/twitter/twemproxy, man:twemproxy(1)" >> /etc/systemd/system/nutcracker.service
    echo "[Service]" >> /etc/systemd/system/nutcracker.service
    echo "Type=forking" >> /etc/systemd/system/nutcracker.service
    echo "ExecStart=/usr/sbin/nutcracker -c /etc/nutcracker/nutcracker.yml -d -o /var/log/nutcracker.log -p /var/run/nutcracker.pid" >> /etc/systemd/system/nutcracker.service
    echo "PIDFile=/var/run/nutcracker.pid" >> /etc/systemd/system/nutcracker.service
    echo "TimeoutStopSec=0" >> /etc/systemd/system/nutcracker.service
    echo "TimeoutStartSec=1" >> /etc/systemd/system/nutcracker.service
    echo "Restart=always" >> /etc/systemd/system/nutcracker.service
    echo "User=root" >> /etc/systemd/system/nutcracker.service
    echo "Group=root" >> /etc/systemd/system/nutcracker.service
    echo "RuntimeDirectory=nutcracker" >> /etc/systemd/system/nutcracker.service
    echo "RuntimeDirectoryMode=2755" >> /etc/systemd/system/nutcracker.service
    echo "" >> /etc/systemd/system/nutcracker.service
    echo "ExecStop=/bin/kill -s TERM $MAINPID" >> /etc/systemd/system/nutcracker.service
    echo "" >> /etc/systemd/system/nutcracker.service
    echo "UMask=007" >> /etc/systemd/system/nutcracker.service
    echo "PrivateTmp=yes" >> /etc/systemd/system/nutcracker.service
    echo "LimitNOFILE=65535" >> /etc/systemd/system/nutcracker.service
    echo "PrivateDevices=yes" >> /etc/systemd/system/nutcracker.service
    echo "ProtectHome=yes" >> /etc/systemd/system/nutcracker.service
    echo "ReadOnlyDirectories=/" >> /etc/systemd/system/nutcracker.service
    echo "ReadWriteDirectories=/var/run" >> /etc/systemd/system/nutcracker.service
    echo "ReadWriteDirectories=-/var/log/" >> /etc/systemd/system/nutcracker.service
    echo "CapabilityBoundingSet=~CAP_SYS_PTRACE" >> /etc/systemd/system/nutcracker.service
    echo "" >> /etc/systemd/system/nutcracker.service
    echo "[Install]" >> /etc/systemd/system/nutcracker.service
    echo "WantedBy=multi-user.target" >> /etc/systemd/system/nutcracker.service
    echo "Alias=nutcracker.service" >> /etc/systemd/system/nutcracker.service
    echo " done"

    systemctl daemon-reload
    systemctl restart nutcracker

    echo "  Successfully finished twemproxy setup. Config file can be found at /etc/nutcracker/nutcracker.yml"
fi

# Cleanup
updatedb
