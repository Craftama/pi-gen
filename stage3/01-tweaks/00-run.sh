
#!/bin/bash -ex

on_chroot << EOF
groupadd -f -r -g 1001 homeassistant
#useradd -u 1001 -g 1001 -rm homeassistant
EOF

install -v -o 1001 -g 1001 -d ${ROOTFS_DIR}/srv/homeassistant
mkdir -p files
wget -O ./files/hassbian-scripts-0.6.deb https://github.com/home-assistant/hassbian-scripts/releases/download/v0.6/hassbian-scripts_0.6.deb
install -v -m 600 ./files/hassbian-scripts-0.6.deb ${ROOTFS_DIR}/srv/homeassistant/

on_chroot << EOF
dpkg -i /srv/homeassistant/hassbian-scripts-0.6.deb
EOF

# install MQTT
on_chroot << EOF
wget http://repo.mosquitto.org/debian/mosquitto-repo.gpg.key
sudo apt-key add mosquitto-repo.gpg.key -y
apt-get update
apt-get install mosquitto
systemctl enable mosquitto
EOF

on_chroot << EOF
sdptool add SP

ssh-keyscan gitlab.com >> ~/.ssh/known_hosts
ssh-keyscan github.com >> ~/.ssh/known_hosts

if cd /srv/homeassistant/craftbox-wifi-conf; then git pull; else git clone https://github.com/Craftama/rpi3-wifi-conf.git /srv/homeassistant/craftbox-wifi-conf; fi
if cd /srv/craftbox-firmware; then git pull; else git clone https://gitlab.com/craftama/craftbox-firmware.git /srv/craftbox-firmware; fi

echo "cs_CZ.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen cs_CZ
locale-gen en_GB.UTF-8

# enable i2c
echo "i2c-bcm2708" >> /etc/modules
echo "i2c-dev" >> /etc/modules

echo "dtparam=i2c1=on" >> /boot/config.txt
echo "dtparam=i2c_arm=on" >> /boot/config.txt

pip3 install -U pip setuptools
pip3 install -r /srv/craftbox-firmware/requirements/default.txt

if cat /etc/systemd/system/install_homeassistant.service; then echo "OK"; else dpkg -i /srv/homeassistant/hassbian-scripts-0.6.deb; fi

chmod +x /srv/craftbox-firmware/craftbox/cli.py
chmod +x /srv/homeassistant/craftbox-wifi-conf/run.py
pip3 install PyBluez wifi

#sed -i -- 's/ExecStart=\/usr\/lib\/bluetooth\/bluetoothd/ExecStart=\/usr\/lib\/bluetooth\/bluetoothd -C/g' /etc/systemd/system/dbus-org.bluez.service
#sed -i -- 's/ExecStart=\/usr\/lib\/bluetooth\/bluetoothd/ExecStart=\/usr\/lib\/bluetooth\/bluetoothd -C/g' /etc/systemd/system/bluetooth.target.wants/bluetooth.service
sed -i -- 's/ExecStart=\/usr\/lib\/bluetooth\/bluetoothd/ExecStart=\/usr\/lib\/bluetooth\/bluetoothd -C/g' /lib/systemd/system/bluetooth.service

systemctl daemon-reload

cat >/etc/rc.local <<EOL
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

# start wifi configurator
(sleep 10;PYTHONPATH=/srv/craftbox-firmware/ /srv/craftbox-firmware/craftbox/cli.py)&
(sleep 10;/srv/homeassistant/craftbox-wifi-conf/run.py)&
# configure bluetooth
echo 'power on\ndiscoverable on\nscan on\t \nquit' | bluetoothctl

# Print the IP address
_IP=$(hostname -I) || true
if [ "$_IP" ]; then
  printf "My IP address is %s\n" "$_IP"
fi

# sdptool add SP
sdptool add SP
exit 0
EOL

EOF

on_chroot << \EOF
for GRP in dialout gpio spi i2c video; do
        adduser homeassistant $GRP
done
for GRP in homeassistant; do
  adduser pi $GRP
done
EOF

on_chroot << EOF
/opt/hassbian/suites/install_homeassistant.sh
EOF
