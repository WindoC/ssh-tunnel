#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ssh-tunnel"
STATE_DIR="${STATE_DIR:-/tmp/ssh-tunnel}"
KEY_FILE="${STATE_DIR}/id_key"
KNOWN_HOSTS_FILE="${STATE_DIR}/known_hosts"

log() {
  printf '[%s] %s\n' "${APP_NAME}" "$*" >&2
}

fail() {
  log "ERROR: $*"
  exit 1
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

is_port() {
  local value="$1"
  [[ "${value}" =~ ^[0-9]+$ ]] || return 1
  (( value >= 1 && value <= 65535 ))
}

usage() {
  cat <<'EOF'
Usage:
  ssh-tunnel tunnel    Start SSH tunnel client (default mode)
  ssh-tunnel helper    Interactive helper for key generation and bootstrap
  ssh-tunnel help      Show this help

Tunnel env:
  SSH_HOST                        Required SSH server host/IP
  SSH_USER                        Required SSH username
  SSH_PORT                        SSH port (default: 22)
  SSH_PRIVATE_KEY                 Private key content (multi-line)
  SSH_PRIVATE_KEY_BASE64          Alternative base64 encoded private key
  SSH_KNOWN_HOSTS                 Optional known_hosts content
  SSH_STRICT_HOST_KEY_CHECKING    yes|no|accept-new (default: accept-new)
  SSH_SERVER_ALIVE_INTERVAL       SSH keepalive interval seconds (default: 30)
  SSH_SERVER_ALIVE_COUNT_MAX      SSH keepalive count (default: 3)
  SSH_EXIT_ON_FORWARD_FAILURE     yes|no (default: yes)
  SSH_LOCAL_BIND_ADDRESS          Default local bind address (default: 0.0.0.0)
  SSH_TUNNELS                     Required list, comma/semicolon separated
                                  Entry format:
                                  - localPort:remoteHost:remotePort
                                  - bindAddress:localPort:remoteHost:remotePort

Examples:
  SSH_HOST=10.0.0.5 SSH_USER=tunnel SSH_PRIVATE_KEY="$(cat id_ed25519)" \
  SSH_TUNNELS="15432:127.0.0.1:5432,16379:127.0.0.1:6379" ssh-tunnel tunnel

  ssh-tunnel helper
EOF
}

ensure_state_dir() {
  mkdir -p "${STATE_DIR}"
  chmod 700 "${STATE_DIR}"
}

write_private_key() {
  ensure_state_dir
  if [[ -n "${SSH_PRIVATE_KEY:-}" ]]; then
    printf '%s\n' "${SSH_PRIVATE_KEY}" > "${KEY_FILE}"
  elif [[ -n "${SSH_PRIVATE_KEY_BASE64:-}" ]]; then
    printf '%s' "${SSH_PRIVATE_KEY_BASE64}" | base64 -d > "${KEY_FILE}"
  else
    fail "Set SSH_PRIVATE_KEY or SSH_PRIVATE_KEY_BASE64"
  fi
  chmod 600 "${KEY_FILE}"
}

write_known_hosts() {
  ensure_state_dir
  : > "${KNOWN_HOSTS_FILE}"
  chmod 600 "${KNOWN_HOSTS_FILE}"
  if [[ -n "${SSH_KNOWN_HOSTS:-}" ]]; then
    printf '%s\n' "${SSH_KNOWN_HOSTS}" > "${KNOWN_HOSTS_FILE}"
  fi
}

parse_tunnel_entry() {
  local entry="$1"
  local default_bind="$2"
  local a b c d extra
  IFS=':' read -r a b c d extra <<< "${entry}"
  [[ -z "${extra:-}" ]] || fail "Invalid tunnel entry '${entry}'"

  local bind local_port remote_host remote_port
  if [[ -n "${d:-}" ]]; then
    bind="$(trim "${a}")"
    local_port="$(trim "${b}")"
    remote_host="$(trim "${c}")"
    remote_port="$(trim "${d}")"
  else
    bind="${default_bind}"
    local_port="$(trim "${a}")"
    remote_host="$(trim "${b}")"
    remote_port="$(trim "${c}")"
  fi

  [[ -n "${bind}" ]] || fail "Invalid bind address in '${entry}'"
  [[ -n "${remote_host}" ]] || fail "Invalid remote host in '${entry}'"
  is_port "${local_port}" || fail "Invalid local port in '${entry}'"
  is_port "${remote_port}" || fail "Invalid remote port in '${entry}'"

  printf '%s:%s:%s:%s' "${bind}" "${local_port}" "${remote_host}" "${remote_port}"
}

run_tunnel() {
  [[ -n "${SSH_HOST:-}" ]] || fail "SSH_HOST is required"
  [[ -n "${SSH_USER:-}" ]] || fail "SSH_USER is required"
  [[ -n "${SSH_TUNNELS:-}" ]] || fail "SSH_TUNNELS is required"

  local ssh_port="${SSH_PORT:-22}"
  local strict_checking="${SSH_STRICT_HOST_KEY_CHECKING:-accept-new}"
  local alive_interval="${SSH_SERVER_ALIVE_INTERVAL:-30}"
  local alive_count="${SSH_SERVER_ALIVE_COUNT_MAX:-3}"
  local exit_on_forward_failure="${SSH_EXIT_ON_FORWARD_FAILURE:-yes}"
  local default_bind="${SSH_LOCAL_BIND_ADDRESS:-0.0.0.0}"
  local tunnel_spec="${SSH_TUNNELS//;/,}"

  is_port "${ssh_port}" || fail "SSH_PORT must be a valid TCP port"

  write_private_key
  write_known_hosts

  local -a forwards=()
  local -a tunnel_entries=()
  IFS=',' read -r -a tunnel_entries <<< "${tunnel_spec}"

  local raw_entry parsed
  for raw_entry in "${tunnel_entries[@]}"; do
    raw_entry="$(trim "${raw_entry}")"
    [[ -n "${raw_entry}" ]] || continue
    parsed="$(parse_tunnel_entry "${raw_entry}" "${default_bind}")"
    forwards+=("${parsed}")
  done

  (( ${#forwards[@]} > 0 )) || fail "No valid tunnel entries in SSH_TUNNELS"

  local -a cmd=(
    ssh
    -NT
    -p "${ssh_port}"
    -i "${KEY_FILE}"
    -o "IdentitiesOnly=yes"
    -o "ServerAliveInterval=${alive_interval}"
    -o "ServerAliveCountMax=${alive_count}"
    -o "ExitOnForwardFailure=${exit_on_forward_failure}"
    -o "StrictHostKeyChecking=${strict_checking}"
  )

  if [[ "${strict_checking}" == "no" ]]; then
    cmd+=(-o "UserKnownHostsFile=/dev/null")
  else
    cmd+=(-o "UserKnownHostsFile=${KNOWN_HOSTS_FILE}")
  fi

  local forward
  for forward in "${forwards[@]}"; do
    cmd+=(-L "${forward}")
  done

  cmd+=("${SSH_USER}@${SSH_HOST}")

  log "Starting tunnel to ${SSH_USER}@${SSH_HOST}:${ssh_port}"
  log "Forwards: ${forwards[*]}"
  exec "${cmd[@]}"
}

prompt_default() {
  local question="$1"
  local default_value="$2"
  local answer
  read -r -p "${question} [${default_value}]: " answer
  if [[ -z "${answer}" ]]; then
    printf '%s' "${default_value}"
  else
    printf '%s' "${answer}"
  fi
}

ports_from_tunnels() {
  local spec="$1"
  local default_bind="$2"
  local -a entries=()
  IFS=',' read -r -a entries <<< "${spec//;/,}"
  local entry parsed
  for entry in "${entries[@]}"; do
    entry="$(trim "${entry}")"
    [[ -n "${entry}" ]] || continue
    parsed="$(parse_tunnel_entry "${entry}" "${default_bind}")"
    IFS=':' read -r _bind local_port _remote_host _remote_port <<< "${parsed}"
    printf '%s\n' "${local_port}"
  done
}

print_helper_examples() {
  local host="$1"
  local user="$2"
  local port="$3"
  local tunnel_spec="$4"
  local private_key="$5"
  local private_key_b64="$6"
  local -a local_ports=()
  mapfile -t local_ports < <(ports_from_tunnels "${tunnel_spec}" "0.0.0.0")

  echo
  echo "========================================"
  echo "Step 4/4 - Runtime setup examples"
  echo "========================================"
  echo
  echo "docker run example:"
  echo
  local p
  local docker_port_lines=""
  for p in "${local_ports[@]}"; do
    printf -v docker_port_lines '%s  -p %s:%s \\\n' "${docker_port_lines}" "${p}" "${p}"
  done
  cat <<EOF
export SSH_PRIVATE_KEY_BASE64=${private_key_b64}

docker run -d --name ssh-tunnel \\
${docker_port_lines}  -e SSH_HOST='${host}' \\
  -e SSH_PORT='${port}' \\
  -e SSH_USER='${user}' \\
  -e SSH_TUNNELS='${tunnel_spec}' \\
  -e SSH_PRIVATE_KEY_BASE64="\$SSH_PRIVATE_KEY_BASE64" \\
  ghcr.io/windoc/ssh-tunnel:latest
EOF

  echo
  echo "docker-compose.yaml example:"
  echo
  cat <<EOF
services:
  ssh-tunnel:
    image: ghcr.io/windoc/ssh-tunnel:latest
    restart: unless-stopped
    ports:
EOF
  for p in "${local_ports[@]}"; do
    printf "      - \"%s:%s\"\n" "${p}" "${p}"
  done
  cat <<EOF
    environment:
      SSH_HOST: "${host}"
      SSH_PORT: "${port}"
      SSH_USER: "${user}"
      SSH_TUNNELS: "${tunnel_spec}"
      SSH_PRIVATE_KEY: |
EOF
  while IFS= read -r line; do
    printf '        %s\n' "${line}"
  done <<< "${private_key}"

  echo
  echo "k8s manifest example (Deployment + Service):"
  echo
  cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ssh-tunnel
  labels:
    app: ssh-tunnel
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ssh-tunnel
  template:
    metadata:
      labels:
        app: ssh-tunnel
    spec:
      containers:
        - name: ssh-tunnel
          image: ghcr.io/windoc/ssh-tunnel:latest
          args: ["tunnel"]
          env:
            - name: SSH_HOST
              value: "${host}"
            - name: SSH_PORT
              value: "${port}"
            - name: SSH_USER
              value: "${user}"
            - name: SSH_TUNNELS
              value: "${tunnel_spec}"
            - name: SSH_PRIVATE_KEY
              value: |
EOF
  while IFS= read -r line; do
    printf '                %s\n' "${line}"
  done <<< "${private_key}"
  cat <<EOF
          ports:
EOF
  local idx=1
  local local_port
  for local_port in "${local_ports[@]}"; do
    cat <<EOF
            - name: tunnel-${idx}
              containerPort: ${local_port}
              protocol: TCP
EOF
    idx=$((idx + 1))
  done
  cat <<EOF
---
apiVersion: v1
kind: Service
metadata:
  name: ssh-tunnel
  labels:
    app: ssh-tunnel
spec:
  type: ClusterIP
  selector:
    app: ssh-tunnel
  ports:
EOF
  idx=1
  for local_port in "${local_ports[@]}"; do
    cat <<EOF
    - name: tunnel-${idx}
      port: ${local_port}
      targetPort: ${local_port}
      protocol: TCP
EOF
    idx=$((idx + 1))
  done
}

run_helper() {
  ensure_state_dir
  local helper_key="${STATE_DIR}/helper_id_ed25519"
  rm -f "${helper_key}" "${helper_key}.pub"

  local comment
  comment="ssh-tunnel-helper-$(date -u +%Y%m%dT%H%M%SZ)"

  echo "========================================"
  echo "Step 1/4 - Generating SSH key pair"
  echo "========================================"
  ssh-keygen -q -t ed25519 -N "" -C "${comment}" -f "${helper_key}"

  local private_key public_key private_key_b64
  private_key="$(cat "${helper_key}")"
  public_key="$(cat "${helper_key}.pub")"
  private_key_b64="$(base64 -w 0 < "${helper_key}")"

  echo
  echo "Public key:"
  echo "${public_key}"
  echo
  echo "Private key (use as SSH_PRIVATE_KEY):"
  printf '%s\n' "${private_key}"
  echo
  echo "Private key base64 (use as SSH_PRIVATE_KEY_BASE64):"
  echo "${private_key_b64}"
  echo

  local host user port tunnel_spec
  read -r -p "Target SSH server host/IP: " host
  [[ -n "${host}" ]] || fail "Host/IP is required"

  read -r -p "Target SSH username: " user
  [[ -n "${user}" ]] || fail "Username is required"

  port="$(prompt_default "Target SSH port" "22")"
  is_port "${port}" || fail "Invalid SSH port '${port}'"

  echo
  echo "========================================"
  echo "Step 2/4 - Copy public key to server"
  echo "========================================"
  echo "Enter the remote account password when prompted."
  ssh-copy-id -i "${helper_key}.pub" -p "${port}" -o StrictHostKeyChecking=accept-new "${user}@${host}"

  echo
  echo "========================================"
  echo "Step 3/4 - Confirm passwordless SSH"
  echo "========================================"
  local remote_hostname
  remote_hostname="$(ssh -i "${helper_key}" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -p "${port}" "${user}@${host}" hostname)"
  echo "Passwordless SSH works. Remote hostname: ${remote_hostname}"

  tunnel_spec="$(prompt_default "Tunnel list (csv localPort:remoteHost:remotePort)" "15432:127.0.0.1:5432")"
  local -a helper_ports=()
  mapfile -t helper_ports < <(ports_from_tunnels "${tunnel_spec}" "0.0.0.0")
  (( ${#helper_ports[@]} > 0 )) || fail "At least one valid tunnel is required"

  print_helper_examples "${host}" "${user}" "${port}" "${tunnel_spec}" "${private_key}" "${private_key_b64}"
}

main() {
  local mode="${1:-tunnel}"
  case "${mode}" in
    tunnel)
      run_tunnel
      ;;
    helper)
      run_helper
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      fail "Unknown mode '${mode}'. Use 'help' to list options."
      ;;
  esac
}

main "${1:-tunnel}"
