FROM debian:12

RUN apt-get update && apt-get install -y php8.2-fpm php8.2-mysql wget curl mariadb-client && rm -rf /var/lib/apt/lists/*

COPY tools/entrypoint.sh /

RUN chmod +x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
