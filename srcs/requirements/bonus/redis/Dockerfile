FROM debian:12

RUN apt-get update && apt-get install redis-server -y && rm -rf /var/lib/apt/lists/*

COPY tools/entrypoint.sh /

RUN chmod +x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
