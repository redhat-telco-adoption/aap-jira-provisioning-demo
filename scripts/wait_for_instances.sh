#!/usr/bin/env bash
# Wait until the Zabbix server EC2 instance is SSH-reachable.
# Reads the IP from Terraform outputs. Timeout: 5 minutes.

set -euo pipefail

TERRAFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)"
SSH_KEY="${AWS_PRIVATE_KEY_PATH:-keys/demo-key.pem}"
SSH_KEY="${SSH_KEY/#\~/$HOME}"
TIMEOUT=300   # 5 minutes
INTERVAL=10   # seconds between retries

get_ip() {
  terraform -chdir="${TERRAFORM_DIR}" output -raw "$1" 2>/dev/null
}

wait_for_ssh() {
  local name="$1"
  local ip="$2"
  local elapsed=0

  echo "Waiting for SSH on ${name} (${ip})..."
  while ! ssh -o StrictHostKeyChecking=no \
              -o ConnectTimeout=5 \
              -o BatchMode=yes \
              -i "${SSH_KEY}" \
              "ec2-user@${ip}" "echo ok" &>/dev/null; do
    if [[ ${elapsed} -ge ${TIMEOUT} ]]; then
      echo "ERROR: Timeout waiting for ${name} (${ip})"
      exit 1
    fi
    echo "  ${name}: not ready yet, retrying in ${INTERVAL}s (${elapsed}/${TIMEOUT}s)..."
    sleep "${INTERVAL}"
    elapsed=$((elapsed + INTERVAL))
  done

  echo "  ${name}: SSH ready!"
}

echo "=== Fetching Terraform outputs ==="
ZABBIX_IP=$(get_ip zabbix_public_ip)

echo "Zabbix: ${ZABBIX_IP}"
echo ""

wait_for_ssh "zabbix-server" "${ZABBIX_IP}"

echo ""
echo "=== Zabbix server is SSH-reachable ==="
