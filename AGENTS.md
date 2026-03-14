# Project Memory

## Scope

This repo builds an SSH tunnel client container with:

- env-only configuration (no mounted ssh config/key files),
- multiple local forwards in one SSH process,
- interactive helper mode for SSH key bootstrap and onboarding output.

## Core files

- `Dockerfile`: runtime image.
- `scripts/ssh-tunnel.sh`: app entrypoint (`tunnel` and `helper` modes).
- `docker-compose.yaml`: compose example for multi-tunnel setup.
- `kubernetes.yaml`: Kubernetes Deployment + Service example.
- `helm/ssh-tunnel/*`: Helm chart for Kubernetes deployment.
- `.github/workflows/docker-image.yml`: GitHub Actions build/push workflow for container image.
- `README.md`: usage and setup instructions.

## Behavior details

- `tunnel` mode expects `SSH_HOST`, `SSH_USER`, `SSH_TUNNELS`, and key env.
- `SSH_TUNNELS` supports both:
  - `localPort:remoteHost:remotePort`
  - `localPort1:remoteHost1:remotePort1,localPort2:remoteHost2:remotePort2`
  - `bindAddress:localPort:remoteHost:remotePort`
- Key env priority:
  1. `SSH_PRIVATE_KEY`
  2. `SSH_PRIVATE_KEY_BASE64`

## Helper flow

- `helper` mode runs:
  1. `ssh-keygen` (ed25519),
  2. `ssh-copy-id` with interactive password prompt,
  3. passwordless SSH verification (`ssh ... hostname`),
  4. prints Docker, Compose, and Kubernetes YAML snippets with collected values.
