FROM debian:12

RUN apt-get update -y && apt-get install nginx openssl -y && rm -rf /var/lib/apt/lists/*

COPY tools/entrypoint.sh /

RUN chmod +x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
