#!/bin/bash

MYSQL_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)
MYSQL_PASSWORD=$(cat /run/secrets/db_password)

set -e 

if [ ! -d "/run/mysqld" ]; then
  mkdir -p /run/mysqld
  chown -R mysql:mysql /run/mysqld
fi 

if [ ! -d "/var/lib/mysql/${MYSQL_DB}" ]; then
  echo "First time setup: Initializing MariaDB..."
  chown -R mysql:mysql /var/lib/mysql
  mysql_install_db --basedir=/usr --datadir=/var/lib/mysql --user=mysql > /dev/null
  TMP_FILE=/tmp/init.sql
  echo "FLUSH PRIVILEGES;" > ${TMP_FILE}
  echo "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';" >> ${TMP_FILE}
  echo "CREATE DATABASE IF NOT EXISTS \`${MYSQL_DB}\`;" >> ${TMP_FILE}
  echo "CREATE USER IF NOT EXISTS \`${MYSQL_USER}\`@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';" >> ${TMP_FILE}
  echo "GRANT ALL PRIVILEGES ON \`${MYSQL_DB}\`.* TO \`${MYSQL_USER}\`@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';" >> ${TMP_FILE}
  echo "FLUSH PRIVILEGES;" >> ${TMP_FILE}
  /usr/sbin/mysqld --user=mysql --bootstrap < ${TMP_FILE}
  rm -rf ${TMP_FILE}
fi 

sed -i "s|.*bind-address\s*=.*|bind-address=0.0.0.0|g" /etc/mysql/mariadb.conf.d/50-server.cnf

exec /usr/sbin/mysqld --user=mysql --console

