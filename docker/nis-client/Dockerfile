FROM debian:bookworm-slim

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install NIS client packages and NFS client
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ypbind \
        nss-nis \
        nfs-common \
        net-tools \
        iputils-ping \
        sudo \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create home directory mount point
RUN mkdir -p /home

# Copy NIS client configuration files
COPY config/yp.conf /etc/yp/yp.conf
COPY config/nsswitch.conf /etc/nsswitch.conf

# Entry point: start NIS client, mount NFS, and keep container running
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]