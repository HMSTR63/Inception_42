#!/bin/bash

set -e 

if [ ! -f /etc/ssl/certs/nginx.crt ]; then
  echo "Generating SSL Certificate..."
  openssl req -x509 -days 365 -newkey rsa:2048 -nodes \
    -out '/etc/ssl/certs/nginx.crt' \
    -keyout '/etc/ssl/private/nginx.key' \
    -subj "/CN=$DOMAIN_NAME" > /dev/null

cat << EOF > /etc/nginx/conf.d/nginx.conf
  server {
      listen 443 ssl;
      server_name $DOMAIN_NAME;
      
      ssl_certificate /etc/ssl/certs/nginx.crt;
      ssl_certificate_key /etc/ssl/private/nginx.key;
      ssl_protocols TLSv1.2 TLSv1.3;
      root /var/www/wordpress;
      index index.php;
      location ~ \.php$ {
        fastcgi_pass wordpress:9000;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
      }
  }

EOF

fi

exec nginx -g 'daemon off;'
