FROM debian:bookworm-slim

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install NFS server packages and utilities
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nfs-kernel-server \
        portmap \
        net-tools \
        iputils-ping \
        sudo \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create NFS export directories
RUN mkdir -p /srv/nfs/home

# Copy NFS configuration files
COPY config/exports /etc/exports

# Expose NFS port
EXPOSE 2049/tcp 2049/udp

# Entry point: start NFS services and keep container running
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]