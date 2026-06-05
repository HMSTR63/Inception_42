#!/bin/bash

set -e

MYSQL_PASSWORD=$(cat /run/secrets/db_password)
WP_ADMIN_PASS=$(sed -n '1p' /run/secrets/credentials)
WP_USER_PASS=$(sed -n '2p' /run/secrets/credentials)

echo "Waiting for Mariadb..."
while ! mysqladmin ping -h mariadb -u$MYSQL_USER -p$MYSQL_PASSWORD --silent; do 
  sleep 1
done
echo "Mariadb is ready"

if [ ! -f "$WP_PATH"/wp-config.php ]; then
  mkdir -p $WP_PATH
  wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
  chmod +x wp-cli.phar
  mv wp-cli.phar /usr/local/bin/wp

  wp core download --path=$WP_PATH --allow-root
  wp config create --path=$WP_PATH --dbname=$MYSQL_DB --dbuser=$MYSQL_USER --dbpass=$MYSQL_PASSWORD --dbhost=mariadb --allow-root
  wp core install --path=$WP_PATH --url=$DOMAIN_NAME --title="Inception" --admin_user=$WP_ADMIN --admin_password=$WP_ADMIN_PASS --admin_email=$WP_ADMIN_EMAIL --allow-root
  wp user create $WP_USER $WP_USER_EMAIL --role=author --user_pass=$WP_USER_PASS --path=$WP_PATH --allow-root
  wp config set WP_REDIS_HOST redis --path="$WP_PATH" --allow-root
  wp config set WP_REDIS_PORT 6379 --path="$WP_PATH" --allow-root
  wp config set WP_REDIS_PREFIX inception --path="$WP_PATH" --allow-root
  wp plugin install redis-cache --activate --path="$WP_PATH" --allow-root
  wp redis enable --path="$WP_PATH" --allow-root
  chown -R www-data:www-data $WP_PATH
fi
sed -i "s|listen = /run/php/php8.2-fpm.sock|listen = 9000|g" /etc/php/8.2/fpm/pool.d/www.conf
echo "Wordpress is on"
exec php-fpm8.2 -F
