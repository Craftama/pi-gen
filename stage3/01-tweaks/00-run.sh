
#!/bin/bash -ex

on_chroot << EOF
groupadd -f -r -g 1001 homeassistant
useradd -u 1001 -g 1001 -rm homeassistant
EOF

install -v -o 1001 -g 1001 -d ${ROOTFS_DIR}/srv/homeassistant
mkdir -p files

on_chroot << EOF
curl -sSL https://get.docker.com | sh
EOF

on_chroot << EOF
sdptool add SP

ssh-keyscan gitlab.com >> ~/.ssh/known_hosts
ssh-keyscan github.com >> ~/.ssh/known_hosts

if cd /srv/craftbox-firmware; then git pull; else git clone https://gitlab.com/craftama/craftbox-firmware.git /srv/craftbox-firmware; fi

echo "cs_CZ.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen cs_CZ
locale-gen en_GB.UTF-8

# enable i2c
echo "i2c-bcm2708" >> /etc/modules
echo "i2c-dev" >> /etc/modules

echo "dtparam=i2c1=on" >> /boot/config.txt
echo "dtparam=i2c_arm=on" >> /boot/config.txt

# pip workaround
wget https://bootstrap.pypa.io/get-pip.py
python get-pip.py
pip3 install -U setuptools
pip3 install PyBluez wifi
pip3 install -r /srv/craftbox-firmware/requirements/default.txt

chmod +x /srv/craftbox-firmware/craftbox/cli.py

cd /srv/craftbox-firmware/
python3 setup.py install

sed -i -- 's/ExecStart=\/usr\/lib\/bluetooth\/bluetoothd/ExecStart=\/usr\/lib\/bluetooth\/bluetoothd -C/g' /lib/systemd/system/bluetooth.service

cat >/etc/systemd/system/craftbox.service <<EOL
[Unit]
Description=Craftbox firmware
After=dbus.socket

[Service]
Type=simple
Restart=always
RestartSec=5s
ExecStart=/usr/local/bin/craftbox run
ExecStop=/bin/kill -TERM $MAINPID

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable craftbox.service

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

# configure bluetooth
echo 'power on\ndiscoverable on\nscan on\t \nquit' | bluetoothctl

# disable bluetooth after 5 minutes
(sleep 300;echo 'power off\ndiscoverable off\nscan off\t \nquit' | bluetoothctl)&

# install hassio
curl -sL https://raw.githubusercontent.com/home-assistant/hassio-build/master/install/hassio_install | bash -s -- -m raspberrypi

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
