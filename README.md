*This project has been created as part of the 42 curriculum by sojammal.*

# Inception

## Description

Inception is a system administration project from the 42 curriculum.
The goal is to learn containerization by building a complete
infrastructure using Docker and Docker Compose.

The project sets up a fully functional WordPress website running
in an isolated multi-container environment. Each service runs in
its own dedicated container, built from scratch using custom
Dockerfiles based on Debian 12.

The infrastructure can run on any machine that has Docker Engine
installed, without any other dependencies.

### Mandatory services
- **Nginx** — reverse proxy with SSL/TLS, the only entry point
- **WordPress** — CMS with php-fpm, serves the website
- **MariaDB** — database storing all WordPress data

### Bonus services
- **Redis** — object cache to improve WordPress performance
- **FTP** — file transfer access to WordPress volume
- **Adminer** — web GUI to manage the database
- **Portainer** — web GUI to manage Docker containers
- **Static website** — simple portfolio page

## Project Structure

```
.
├── Makefile
├── secrets/          ← sensitive files
│   ├── credentials.txt
│   ├── db_password.txt
│   └── db_root_password.txt
└── srcs/
    ├── .env          ← environment variables
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   └── tools/entrypoint.sh
        ├── nginx/
        │   ├── Dockerfile
        │   └── tools/entrypoint.sh
        ├── wordpress/
        │   ├── Dockerfile
        │   └── tools/entrypoint.sh
        └── bonus/
            ├── redis/
            │   ├── Dockerfile
            │   └── tools/entrypoint.sh
            ├── adminer/
            │   ├── Dockerfile
            │   └── tools/entrypoint.sh
            ├── ftp/
            │   ├── Dockerfile
            │   └── tools/entrypoint.sh
            ├── portainer/
            │   ├── Dockerfile
            │   └── tools/entrypoint.sh
            └── website/
                ├── Dockerfile
                ├── html/index.html
                └── tools/entrypoint.sh
```
## Architecture

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                             HOST MACHINE                                     ║
║                                                                              ║
║  $HOME/data/mariadb   ◄──────────────────────────────┐                       ║
║  $HOME/data/wordpress ◄──────────────────────────┐   │                       ║
║  /var/run/docker.sock ◄──────────────────────┐   │   │                       ║
║                                              │   │   │                       ║
║ ┌────────────────────────────────────────────│───│───│────────────────────┐  ║
║ │              DOCKER NETWORK (inception bridge)                          │  ║
║ │                                            │   │   │                    │  ║
║ │                           ┌────────────────┘   │   │                    │  ║
║ │                           │                    │   │                    │  ║
║ │              ┌────────────┴──┐                 │   │                    │  ║
║ │              │   PORTAINER   │                 │   │                    │  ║
║ │              │ docker manager│                 │   │                    │  ║
║ │              │   port 9000   │                 │   │                    │  ║
║ │              └───────────────┘                 │   │                    │  ║
║ │          ┌─────────────────────────────────────────┘                    │  ║
║ │ ┌────────┴────┐   ┌─────────────┐   ┌──────────┴─────┐                  │  ║
║ │ │   MARIADB   │   │  WORDPRESS  │   │     NGINX      │◄── internet      │  ║
║ │ │             │◄──│   php-fpm   │◄──│    SSL/TLS     │    port 443      │  ║
║ │ │  port 3306  │   │  port 9000  │   │    port 443    │                  │  ║
║ │ └──────┬──────┘   └──────┬──────┘   └────────────────┘                  │  ║
║ │        │                 │                                              │  ║
║ │        │                 ▼                                              │  ║
║ │        │          ┌─────────────┐                                       │  ║
║ │        │          │    REDIS    │                                       │  ║
║ │        │          │    cache    │                                       │  ║
║ │        │          │  port 6379  │                                       │  ║
║ │        │          └─────────────┘                                       │  ║
║ │        │                                                                │  ║
║ │ ┌──────┴──────┐   ┌─────────────┐   ┌─────────────┐                     │  ║
║ │ │   ADMINER   │   │   WEBSITE   │   │     FTP     │                     │  ║
║ │ │  database   │   │   static    │   │    file     │                     │  ║
║ │ │    GUI      │   │    page     │   │  transfer   │                     │  ║
║ │ │  port 8080  │   │   port 80   │   │  port  21   │                     │  ║
║ │ └─────────────┘   └─────────────┘   └─────────────┘                     │  ║
║ │                                                                         │  ║
║ └─────────────────────────────────────────────────────────────────────────┘  ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

## Instructions

### Prerequisites
- Docker Engine
- Docker Compose plugin
- make
- Git

### Setup

1. Clone the repository:
```bash
git clone git@github.com:HMSTR63/inception.git
cd inception
```

2. Create secrets files (see DEV_DOC.md)

3. Create srcs/.env file (see DEV_DOC.md)

4. Add to /etc/hosts:
```
127.0.0.1 sojammal.42.fr
```

5. Run:
```bash
make re
```

### Makefile commands

| Command | Description |
|---------|-------------|
| make | Build and start all containers |
| make down | Stop all containers |
| make clean | Remove unused resources |
| make fclean | Full clean including volumes |
| make re | Full rebuild from scratch |
| make re-service service=name | Rebuild one service |

## Resources

### Documentation & Books

- [Docker Deep Dive - Nigel Poulton](https://reader.z-lib.gd/read/72fb60f09a68bc7ef4d3d5db387ecb88666c54470e78d8f0508ac5f78dbeeb2e/117959992/c24fe3/docker-deep-dive-zero-to-docker-in-a-single-book.html)
  → Main book used to understand Docker fundamentals,
    images, containers, networking and volumes

- [Docker documentation by oussama-elhadraoui](https://dexter-13.gitbook.io/oussama-elhadraoui/docker-doc)
  → Used to understand Docker concepts in a structured way

### AI Usage

This project was developed with AI assistance (Claude by Anthropic).

AI was used to:
- Understand Docker concepts deeply (networking, volumes, secrets)
- Debug entrypoint scripts and configuration issues
- Understand nginx, php-fpm, Redis and FTP under the hood
- Explain SSL/TLS, FastCGI and caching mechanisms
- Review bash scripts and Docker Compose configuration
- Help understanding concepts for writing documentation
  (README, USER_DOC, DEV_DOC)


## Project Description

### Virtual Machines vs Docker

A Virtual Machine runs a full operating system on top of a
hypervisor, requiring gigabytes of storage and minutes to start.
Docker containers share the host OS kernel, making them
lightweight (megabytes) and fast to start (seconds). In this
project, each service runs in its own container instead of a
separate VM, making the infrastructure efficient and portable.

### Secrets vs Environment Variables

Environment variables store configuration in plain text and are
visible via docker inspect, making them risky for sensitive data.
Docker secrets store sensitive information in files mounted as
read-only inside containers at /run/secrets/, never appearing in
inspect output or logs. In this project, all passwords are stored
in secrets files and read by entrypoint scripts at runtime.

### Docker Network vs Host Network

Host network mode shares the host machine's network stack with
containers, removing isolation and risking port conflicts. Docker
bridge network creates an isolated private network where containers
communicate using service names as hostnames. In this project, all
containers are on the inception bridge network, with only nginx
exposing port 443 to the outside world.

### Docker Volumes vs Bind Mounts

Bind mounts directly map a host path into a container with no
Docker management. Named volumes are managed by Docker and can be
configured with driver options to control where data is stored.
This project uses named volumes with driver_opts to store WordPress
files and database data at /home/sojammal/data/ on the host,
making data persistent and accessible to multiple containers
simultaneously.
