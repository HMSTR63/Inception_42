FROM debian:12

RUN apt-get update && apt-get install nginx -y && rm -rf /var/lib/apt/lists/*

COPY html/index.html /var/www/html/

COPY tools/entrypoint.sh /

RUN chmod +x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
