#!/bin/bash

set -e

if ! grep -q "maxmemory 50mb" /etc/redis/redis.conf; then
    echo "Redis config start..."
    sed -i 's|# maxmemory <bytes>|maxmemory 50mb|g' /etc/redis/redis.conf
    sed -i 's|# maxmemory-policy noeviction|maxmemory-policy allkeys-lru|g' /etc/redis/redis.conf
    echo "Redis configured!"
fi

exec redis-server /etc/redis/redis.conf --protected-mode no --bind 0.0.0.0 --daemonize no
