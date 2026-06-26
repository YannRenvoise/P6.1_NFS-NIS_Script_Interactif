FROM debian:bookworm-slim

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install NIS packages (ypserv, ypbind, nis utilities) and make
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ypserv \
        ypbind \
        nis \
        make \
        net-tools \
        iputils-ping \
        sudo \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set NIS domain name
ENV NIS_DOMAIN=localdomain

# Create directories needed by NIS
RUN mkdir -p /var/yp /etc/yp

# Copy NIS configuration files
COPY config/ /etc/yp/

# Expose NIS ports
# 111  - Portmapper (RPC)
# 749  - ypserv
# 811  - ypxfrd
EXPOSE 111/udp 111/tcp 749/tcp 811/udp

# Entry point: start NIS services and keep container running
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]