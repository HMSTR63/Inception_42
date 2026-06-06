FROM debian:12

RUN apt-get update && apt-get install curl -y && rm -rf /var/lib/apt/lists/*

COPY tools/entrypoint.sh /

RUN curl -L https://github.com/portainer/portainer/releases/download/2.21.0/portainer-2.21.0-linux-arm64.tar.gz | tar -xz -C /

RUN chmod +x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
