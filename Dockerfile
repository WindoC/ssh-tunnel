FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="ssh-tunnel" \
      org.opencontainers.image.description="Containerized SSH client for multi-port SSH tunneling with env-only configuration and interactive key bootstrap helper." \
      org.opencontainers.image.source="https://github.com/WindoC/ssh-tunnel" \
      org.opencontainers.image.url="https://github.com/WindoC/ssh-tunnel" \
      org.opencontainers.image.documentation="https://github.com/WindoC/ssh-tunnel/blob/main/README.md"

COPY scripts/ssh-tunnel.sh /usr/local/bin/ssh-tunnel

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates openssh-client tini \
 && rm -rf /var/lib/apt/lists/* \
 && chmod +x /usr/local/bin/ssh-tunnel \
 && mkdir -p /root/.ssh && chmod 700 /root/.ssh

WORKDIR /app

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/ssh-tunnel"]
CMD ["tunnel"]
