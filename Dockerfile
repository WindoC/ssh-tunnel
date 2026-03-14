FROM debian:bookworm-slim

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
