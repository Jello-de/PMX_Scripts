#!/usr/bin/env bash

# SilverBullet Secure install script
# Runs inside Debian LXC

set -Eeuo pipefail

APP="SilverBullet"

msg_info() {
  echo "[INFO] $*"
}

msg_ok() {
  echo "[OK] $*"
}

msg_warn() {
  echo "[WARN] $*"
}

msg_error() {
  echo "[ERROR] $*" >&2
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    msg_error "Dieses Installationsscript muss als root im Container ausgeführt werden."
    exit 1
  fi
}

install_dependencies() {
  msg_info "Installiere Abhängigkeiten..."

  export DEBIAN_FRONTEND=noninteractive

  apt-get update
  apt-get install -y \
    ca-certificates \
    curl \
    unzip \
    jq \
    openssl

  msg_ok "Abhängigkeiten installiert."
}

create_user_and_dirs() {
  msg_info "Erstelle Benutzer und Verzeichnisse..."

  if ! getent group silverbullet >/dev/null 2>&1; then
    addgroup --system silverbullet
  fi

  if ! id silverbullet >/dev/null 2>&1; then
    adduser \
      --system \
      --home /var/lib/silverbullet \
      --shell /usr/sbin/nologin \
      --no-create-home \
      --gecos "SilverBullet" \
      --ingroup silverbullet \
      --disabled-login \
      --disabled-password \
      silverbullet
  fi

  mkdir -p /opt/silverbullet/bin
  mkdir -p /var/lib/silverbullet/space
  mkdir -p /etc/silverbullet

  chown -R silverbullet:silverbullet /var/lib/silverbullet
  chmod 0750 /var/lib/silverbullet
  chmod 0750 /var/lib/silverbullet/space

  msg_ok "Benutzer und Verzeichnisse erstellt."
}

install_silverbullet() {
  msg_info "Installiere SilverBullet..."

  local tmpdir
  tmpdir="$(mktemp -d)"

  curl -fsSL \
    https://github.com/silverbulletmd/silverbullet/releases/latest/download/silverbullet-server-linux-x86_64.zip \
    -o "${tmpdir}/silverbullet.zip"

  unzip -o "${tmpdir}/silverbullet.zip" -d /opt/silverbullet/bin

  chmod 0755 /opt/silverbullet/bin/silverbullet
  chown root:root /opt/silverbullet/bin/silverbullet

  rm -rf "${tmpdir}"

  msg_ok "SilverBullet installiert."
}

create_config() {
  msg_info "Erstelle sichere Standardkonfiguration..."

  local sb_password
  sb_password="$(openssl rand -base64 36 | tr -d '\n')"

  cat >/etc/silverbullet/silverbullet.env <<EOF
SB_USER=admin:${sb_password}
SB_NAME=Private Notes
SB_LOCKOUT_LIMIT=5
SB_LOCKOUT_TIME=300
SB_REMEMBER_ME_HOURS=12
EOF

  chown root:silverbullet /etc/silverbullet/silverbullet.env
  chmod 0640 /etc/silverbullet/silverbullet.env

  cat >/root/SILVERBULLET-CREDENTIALS.txt <<EOF
SilverBullet wurde installiert.

URL:
  http://$(hostname -I | awk '{print $1}'):3000

Username:
  admin

Password:
  ${sb_password}

Credential file:
  /etc/silverbullet/silverbullet.env

Data directory:
  /var/lib/silverbullet/space

Service commands:
  systemctl status silverbullet --no-pager
  systemctl restart silverbullet
  journalctl -u silverbullet -f
EOF

  chmod 0600 /root/SILVERBULLET-CREDENTIALS.txt

  msg_ok "Konfiguration erstellt."
}

create_systemd_service() {
  msg_info "Erstelle systemd-Service..."

  cat >/etc/systemd/system/silverbullet.service <<'EOF'
[Unit]
Description=SilverBullet
Documentation=https://silverbullet.md/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=silverbullet
Group=silverbullet
WorkingDirectory=/var/lib/silverbullet
EnvironmentFile=/etc/silverbullet/silverbullet.env

ExecStart=/opt/silverbullet/bin/silverbullet /var/lib/silverbullet/space --hostname 0.0.0.0 --port 3000

Restart=on-failure
RestartSec=5
TimeoutStopSec=30
KillSignal=SIGTERM

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/silverbullet
ReadOnlyPaths=/opt/silverbullet /etc/silverbullet
UMask=0027

LockPersonality=true
RestrictRealtime=true
RestrictSUIDSGID=true
ProtectControlGroups=true
ProtectKernelModules=true
ProtectKernelTunables=true
ProtectClock=true
ProtectHostname=true
SystemCallArchitectures=native

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now silverbullet

  msg_ok "systemd-Service erstellt und gestartet."
}

verify_installation() {
  msg_info "Prüfe Installation..."

  if ! systemctl is-active --quiet silverbullet; then
    msg_error "SilverBullet-Service läuft nicht."
    journalctl -u silverbullet -n 80 --no-pager || true
    exit 1
  fi

  if ! ss -tulpn | grep -q ':3000'; then
    msg_error "SilverBullet lauscht nicht auf Port 3000."
    exit 1
  fi

  msg_ok "SilverBullet läuft auf Port 3000."
}

main() {
  require_root
  install_dependencies
  create_user_and_dirs
  install_silverbullet
  create_config
  create_systemd_service
  verify_installation

  echo
  msg_ok "Installation abgeschlossen."
  echo
  cat /root/SILVERBULLET-CREDENTIALS.txt
}

main "$@"
