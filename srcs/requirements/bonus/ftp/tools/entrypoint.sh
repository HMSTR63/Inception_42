#!/bin/bash

set -e 

FTP_PASS=$(sed -n '3p' /run/secrets/credentials)
CONF_PATH=/etc/vsftpd.conf

mkdir -p /var/run/vsftpd/empty

if ! id "$FTP_USER" &>/dev/null; then
    useradd -m $FTP_USER
    echo -e "$FTP_USER:$FTP_PASS" | chpasswd
    chown -R $FTP_USER:$FTP_USER /var/www/wordpress
fi

if ! grep -q "local_root" $CONF_PATH; then
    sed -i "s|#write_enable=YES|write_enable=YES|g" $CONF_PATH
    sed -i "s|#local_enable=YES|local_enable=YES|g" $CONF_PATH
    sed -i "s|#chroot_local_user=YES|chroot_local_user=YES|g" $CONF_PATH
    echo "allow_writeable_chroot=YES" >> $CONF_PATH
    echo "pasv_address=127.0.0.1" >> $CONF_PATH
    echo "local_root=/var/www/wordpress" >> $CONF_PATH
    echo "pasv_enable=YES" >> $CONF_PATH
    echo "pasv_min_port=21100" >> $CONF_PATH
    echo "pasv_max_port=21110" >> $CONF_PATH
fi

exec vsftpd $CONF_PATH

