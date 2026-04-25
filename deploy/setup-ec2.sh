#!/usr/bin/env bash
# One-time bootstrap for a fresh Ubuntu EC2 instance (22.04 / 24.04).
# Run as the default ubuntu user after SSH'ing in. Idempotent.
#
#   curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/deploy/setup-ec2.sh | sudo bash
# or copy this file over and: sudo bash setup-ec2.sh

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

APP_USER="ubuntu"

# --- Apt prerequisites ------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg

# --- Docker -----------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "[setup] Installing Docker..."
  apt-get install -y docker.io
  systemctl enable --now docker
fi

# Add ubuntu to docker group so future SSH sessions can run docker without sudo.
if ! id -nG "${APP_USER}" | grep -qw docker; then
  usermod -aG docker "${APP_USER}"
  echo "[setup] Added ${APP_USER} to docker group (re-login required)."
fi

# --- Docker compose plugin --------------------------------------------------
# Ubuntu's docker.io package doesn't ship the compose plugin, so install the
# official compose binary into the docker CLI plugin directory.
if ! docker compose version >/dev/null 2>&1; then
  echo "[setup] Installing docker compose plugin..."
  COMPOSE_VERSION="v2.29.7"
  mkdir -p /usr/local/lib/docker/cli-plugins
  curl -fsSL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi

# --- App directory ----------------------------------------------------------
mkdir -p /opt/app
chown "${APP_USER}:${APP_USER}" /opt/app
chmod 750 /opt/app

# --- Postgres data dir ------------------------------------------------------
# /data is intended as a mount point. If a separate EBS volume is attached,
# mount it here BEFORE the first deploy so postgres data lives on it.
mkdir -p /data/postgres
# Postgres in the alpine image runs as uid 70.
chown -R 70:70 /data/postgres
chmod 700 /data/postgres

# --- Placeholder compose file so the first deploy can find the directory ----
if [[ ! -f /opt/app/docker-compose.yml ]]; then
  echo "[setup] No docker-compose.yml yet; the GHA deploy will scp it on first run."
fi

# --- Firewall sanity --------------------------------------------------------
# Cloudflare Tunnel is outbound-only; no inbound except SSH. EC2 SG handles this.
# We do NOT touch iptables / ufw here.

echo
echo "[setup] Done."
echo
echo "Next steps:"
echo "  1) Add your GitHub Actions deploy public key to ~${APP_USER}/.ssh/authorized_keys"
echo "  2) Run the GHA 'Deploy' workflow on main; it will scp docker-compose.yml + .env"
echo "  3) Verify with: docker compose -f /opt/app/docker-compose.yml ps"
