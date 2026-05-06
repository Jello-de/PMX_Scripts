#!/usr/bin/env bash

# Copyright (c) 2026
# Author: custom
# License: MIT
# Source: https://silverbullet.md
# GitHub: https://github.com/silverbulletmd/silverbullet
#
# Community-Scripts-style install script for SilverBullet Secure

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing dependencies"
$STD apt-get install -y \
  ca-certificates \
  curl \
  unzip \
  jq \
  openssl
msg_ok "Installed dependencies"

msg_info "Creating SilverBullet user and directories"
$STD addgroup --system silverbullet
$STD adduser \
  --system \
  --home /var/lib/silverbullet \
  --shell /usr/sbin/nologin \
  --no-create-home \
  --gecos "SilverBullet" \
  --ingroup silverbullet \
  --disabled-login \
  --disabled-password \
  silverbullet

mkdir -p \
  /opt/silverbullet/bin \
  /var/lib/silverbullet/space \
  /etc/silverbullet

chown -R silverbullet:silverbullet /var/lib/silverbullet
chmod 0750 /var/lib/silverbullet
chmod 0750 /var/lib/silverbullet/space
msg_ok "Created SilverBullet user and directories"

msg_info "Installing SilverBullet"
fetch_and_deploy_gh_release \
  "silverbullet" \
  "silverbulletmd/silverbullet" \
  "prebuild" \
  "latest" \
  "/opt/silverbullet/bin" \
  "silverbullet-server-linux-x86_64.zip"

chmod 0755 /opt/silverbullet/bin/silverbullet
chown root:root /opt/silverbullet/bin/silverbullet
msg_ok "Installed SilverBullet"

msg_info "Creating secure default configuration"
SB_PASSWORD="$(openssl rand -base64 36 | tr -d '\n')"

cat >/etc/silverbullet/silverbullet.env <<EOF
SB_USER=admin:${SB_PASSWORD}
SB_NAME=Private Notes
SB_LOCKOUT_LIMIT=5
SB_LOCKOUT_TIME=300
SB_REMEMBER_ME_HOURS=12
EOF

chown root:silverbullet /etc/silverbullet/silverbullet.env
chmod 0640 /etc/silverbullet/silverbullet.env
msg_ok "Created secure default configuration"

msg_info "Creating systemd service"
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
systemctl enable -q --now silverbullet
msg_ok "Created systemd service"

msg_info "Writing credential note"
cat >/root/SILVERBULLET-CREDENTIALS.txt <<EOF
SilverBullet has been installed.

URL:
  http://${LOCAL_IP}:3000

Username:
  admin

Password:
  ${SB_PASSWORD}

Credential file:
  /etc/silverbullet/silverbullet.env

Data directory:
  /var/lib/silverbullet/space

Service commands:
  systemctl status silverbullet
  systemctl restart silverbullet
  journalctl -u silverbullet -f
EOF

chmod 0600 /root/SILVERBULLET-CREDENTIALS.txt
msg_ok "Wrote credential note"

motd_ssh
customize
cleanup_lxc
