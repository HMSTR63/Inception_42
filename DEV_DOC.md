# Developer Documentation

## Prerequisites

Make sure the following are installed on your machine:

```bash
# check Docker
docker --version

# check Docker Compose
docker compose version

# check make
make --version

# check git
git --version
```

## Environment Setup

### 1. Clone the repository

```bash
git clone git@github.com:HMSTR63/inception.git
cd inception
```

### 2. Create secret files

Secrets are NOT in git. Create them manually:

```bash
mkdir -p secrets

# database user password
echo "your_db_password" > secrets/db_password.txt

# database root password
echo "your_root_password" > secrets/db_root_password.txt

# wordpress admin pass (line 1)
# wordpress user pass (line 2)
# ftp password (line 3)
printf "wp_admin_pass\nwp_user_pass\nftp_pass" > secrets/credentials.txt
```

### 3. Create .env file

Create `srcs/.env` with these variables:

```env
MYSQL_DB=
MYSQL_USER=
DOMAIN_NAME=
WP_PATH=
WP_ADMIN=
WP_ADMIN_EMAIL=
WP_USER=
WP_USER_EMAIL=
FTP_USER=
```

### 4. Create data directories

```bash
mkdir -p $HOME/data/wordpress
mkdir -p $HOME/data/mariadb
```

### 5. Add domain to /etc/hosts

```bash
echo "127.0.0.1 sojammal.42.fr" | sudo tee -a /etc/hosts
```

## Build and Launch

```bash
# build and start everything
make re

# check all containers are running
docker ps
```

## Container Management

### Useful commands

```bash
# see all containers
docker ps

# see all containers including stopped
docker ps -a

# see logs of a service
docker logs <service_name>
docker logs -f <service_name>  # follow logs live

# go inside a container
docker exec -it <service_name> bash

# rebuild one specific service
make re-service service=<service_name>

# stop everything
make down

# full clean (removes containers, images, volumes, data)
make fclean
```

### Service names
```
mariadb
wordpress
nginx
redis
adminer
ftp
portainer
static_website
```

## Data Storage

### Where data lives on host machine

```
$HOME/data/
├── wordpress/    ← WordPress files
│   ├── wp-config.php
│   ├── wp-content/
│   └── ...
└── mariadb/      ← Database files
    ├── wordpress_db/
    └── ...
```

### How data persists

Both volumes use driver_opts with bind mount:
```yaml
volumes:
  wordpress:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${HOME}/data/wordpress
```

Data written inside containers appears on host machine.
Data survives container restarts and rebuilds.
Only `make fclean` removes the data completely.

## Secrets Flow

```
secrets/db_password.txt
        ↓ Docker mounts at startup
/run/secrets/db_password  (inside container)
        ↓ entrypoint reads it
MYSQL_PASSWORD=$(cat /run/secrets/db_password)
```

## Network Architecture

```
internet
    ↓ port 443 (HTTPS)
  nginx
    ↓ port 9000 (FastCGI)
  wordpress ──── port 6379 ──── redis
    ↓ port 3306
  mariadb

bonus services (independent ports):
  adminer   → 8080
  portainer → 9000
  ftp       → 21
  website   → 80
```

All containers are on the `inception` bridge network.
Containers communicate using service names as hostnames.

## Project File Reference

```
.
├── Makefile                          ← build and manage commands
├── secrets/                          ← sensitive files (not in git)
│   ├── credentials.txt               ← wp admin/user/ftp passwords
│   ├── db_password.txt               ← database user password
│   └── db_root_password.txt          ← database root password
└── srcs/
    ├── .env                          ← environment variables (not in git)
    ├── docker-compose.yml            ← all services configuration
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile            ← installs mariadb
        │   └── tools/
        │       └── entrypoint.sh     ← initializes database
        ├── nginx/
        │   ├── Dockerfile            ← installs nginx + openssl
        │   └── tools/
        │       └── entrypoint.sh     ← generates SSL cert + starts nginx
        ├── wordpress/
        │   ├── Dockerfile            ← installs php-fpm + wp-cli
        │   └── tools/
        │       └── entrypoint.sh     ← downloads + configures WordPress
        └── bonus/
            ├── redis/
            │   ├── Dockerfile        ← installs redis-server
            │   └── tools/
            │       └── entrypoint.sh ← configures + starts redis
            ├── adminer/
            │   ├── Dockerfile        ← installs php + wget
            │   └── tools/
            │       └── entrypoint.sh ← downloads adminer + starts php server
            ├── ftp/
            │   ├── Dockerfile        ← installs vsftpd
            │   └── tools/
            │       └── entrypoint.sh ← configures + starts vsftpd
            ├── portainer/
            │   ├── Dockerfile        ← downloads portainer binary
            │   └── tools/
            │       └── entrypoint.sh ← starts portainer
            └── website/
                ├── Dockerfile        ← installs nginx
                ├── html/
                │   └── index.html    ← static website content
                └── tools/
                    └── entrypoint.sh ← starts nginx
```

## Debugging

### Container won't start
```bash
docker logs <service_name>
```

### WordPress not loading
```bash
# check php-fpm is running
docker exec -it wordpress ps aux

# check nginx config
docker exec -it nginx nginx -t
```

### Database connection issues
```bash
# check mariadb is healthy
docker exec -it mariadb mysqladmin ping -h localhost

# check from wordpress container
docker exec -it wordpress mysqladmin ping -h mariadb \
  -uwp_user -p<password>
```

### Redis not caching
```bash
# check connection
docker exec -it redis redis-cli ping

# check WordPress connection
docker exec -it wordpress wp redis status \
  --allow-root --path=/var/www/wordpress

# see cached keys
docker exec -it redis redis-cli keys "*"
```

### FTP login issues
```bash
# test from command line
curl -v "ftp://ftpuser:<password>@127.0.0.1/"

# check vsftpd config
docker exec -it ftp cat /etc/vsftpd.conf
```
