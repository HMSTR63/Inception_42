#!/bin/bash

set -e 

if [ ! -f /var/www/adminer/adminer.php ]; then
   mkdir -p /var/www/adminer
   wget -O /var/www/adminer/adminer.php https://github.com/vrana/adminer/releases/download/v4.8.1/adminer-4.8.1.php
fi

exec php -S 0.0.0.0:8080 -t /var/www/adminer
