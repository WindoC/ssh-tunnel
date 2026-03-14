# ssh-tunnel container

Containerized SSH client for local port forwarding (`ssh -L`) with support for multiple tunnels and env-only configuration.

## Features

- Multiple tunnels in a single SSH session.
- No config file mounts required.
- SSH key supplied via env (`SSH_PRIVATE_KEY` or `SSH_PRIVATE_KEY_BASE64`).
- Interactive helper mode to:
  1. Generate a key pair.
  2. Copy public key to target server.
  3. Verify passwordless SSH.
  4. Print ready-to-use `docker run`, `docker-compose.yaml`, and Kubernetes YAML examples.

## Build

```bash
docker build -t ssh-tunnel:local .
```

## GitHub Actions image build

Workflow file: `.github/workflows/docker-image.yml`

- On push to `main`/`master`: build and push image to GHCR.
- On tag `v*`: build and push tag image.
- On pull request: build only (no push).
- Image name: `ghcr.io/<owner>/<repo>`.

## Runtime mode (`tunnel`)

### Required env

- `SSH_HOST`: target SSH server host/IP.
- `SSH_USER`: SSH username.
- `SSH_TUNNELS`: comma/semicolon separated list of forwards.
- One of:
  - `SSH_PRIVATE_KEY` (multi-line key), or
  - `SSH_PRIVATE_KEY_BASE64`.

### Tunnel formats

- `localPort:remoteHost:remotePort`
- `localPort1:remoteHost1:remotePort1,localPort2:remoteHost2:remotePort2`
- `bindAddress:localPort:remoteHost:remotePort`

Example:

```bash
docker run -d --name ssh-tunnel \
  -p 15432:15432 \
  -p 16379:16379 \
  -e SSH_HOST=10.0.0.5 \
  -e SSH_PORT=22 \
  -e SSH_USER=tunnel-user \
  -e SSH_TUNNELS='15432:127.0.0.1:5432,16379:127.0.0.1:6379' \
  -e SSH_PRIVATE_KEY="$(cat ./id_ed25519)" \
  ssh-tunnel:local
```

### Optional env

- `SSH_PORT` (default `22`)
- `SSH_KNOWN_HOSTS` (known_hosts content)
- `SSH_STRICT_HOST_KEY_CHECKING` (`accept-new` by default)
- `SSH_SERVER_ALIVE_INTERVAL` (default `30`)
- `SSH_SERVER_ALIVE_COUNT_MAX` (default `3`)
- `SSH_EXIT_ON_FORWARD_FAILURE` (default `yes`)
- `SSH_LOCAL_BIND_ADDRESS` (default `0.0.0.0`)

## Helper mode (`helper`)

Run interactive bootstrap:

```bash
docker run --rm -it ssh-tunnel:local helper
```

Flow:

1. Generate a new ed25519 key pair.
2. Show public/private key and base64 private key.
3. Ask for target host/user/port.
4. Run `ssh-copy-id` (password prompt from SSH).
5. Verify passwordless SSH (`ssh ... hostname`).
6. Print complete startup examples for Docker/Compose/Kubernetes YAML.

## docker-compose example

Use [docker-compose.yaml](docker-compose.yaml).

## Kubernetes example

Use [kubernetes.yaml](kubernetes.yaml).
