# User Documentation

## What is this project?

This project runs a complete WordPress website infrastructure
using Docker containers. The following services are available:

| Service | URL | Description |
|---------|-----|-------------|
| WordPress | https://sojammal.42.fr | Main website |
| WordPress Admin | https://sojammal.42.fr/wp-admin | Admin panel |
| Adminer | http://sojammal.42.fr:8080/adminer.php | Database GUI |
| Static Website | http://sojammal.42.fr | Portfolio page |
| Portainer | http://sojammal.42.fr:9000 | Docker manager |
| FTP | ftp://sojammal.42.fr | File transfer |

## Start and Stop

### Start the project
```bash
make
```

### Stop the project
```bash
make down
```

### Full rebuild
```bash
make re
```

### Full clean (removes everything including data)
```bash
make fclean
```

## Access the website

Open Firefox and go to:
```
https://sojammal.42.fr
```

Accept the SSL certificate warning (self-signed certificate).
You will see the WordPress website.

## Access the admin panel

Go to:
```
https://sojammal.42.fr/wp-admin
```

Login with admin credentials from `secrets/credentials.txt`:
- Username: sojammal
- Password: line 1 of credentials.txt

## Access the database (Adminer)

Go to:
```
http://sojammal.42.fr:8080/adminer.php
```

Login with:
- System: MySQL
- Server: mariadb
- Username: wp_user
- Password: content of secrets/db_password.txt
- Database: wordpress_db

## Access Docker management (Portainer)

Go to:
```
http://sojammal.42.fr:9000
```

Create admin account on first visit.

## Access files via FTP (FileZilla)

Open FileZilla and connect:
```
Host:     sojammal.42.fr
Username: ftpuser
Password: line 3 of secrets/credentials.txt
Port:     21
```

## Locate credentials

All credentials are stored in the `secrets/` folder:

```
secrets/
├── db_password.txt      ← database user password
├── db_root_password.txt ← database root password
└── credentials.txt      ← line 1: wp admin password
                            line 2: wp user password
                            line 3: ftp password
```

## Check services are running

```bash
# see all running containers
docker ps

# check specific service logs
docker logs nginx
docker logs wordpress
docker logs mariadb
docker logs redis
docker logs adminer
docker logs ftp
docker logs portainer
docker logs static_website

# check Redis is working
docker exec -it redis redis-cli ping

# check WordPress Redis connection
docker exec -it wordpress wp redis status \
  --allow-root --path=/var/www/wordpress

# check mariadb is healthy
docker exec -it mariadb mysqladmin ping -h localhost
```

## WordPress users

| Username | Role | Email |
|----------|------|-------|
| sojammal | Administrator | admin@example.com |
| hms7rx | Author | user@example.com |
