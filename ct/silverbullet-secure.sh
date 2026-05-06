#!/usr/bin/env bash

# SilverBullet Secure LXC installer for Proxmox VE
# Repo: https://github.com/Jello-de/PMX_Scripts
# Source: https://silverbullet.md
# License: MIT

set -Eeuo pipefail

APP="SilverBullet Secure"
APP_ID="silverbullet-secure"

REPO_BASE="https://raw.githubusercontent.com/Jello-de/PMX_Scripts/main"
INSTALL_SCRIPT_URL="${REPO_BASE}/install/silverbullet-secure-install.sh"

CTID="${CTID:-}"
HOSTNAME="${HOSTNAME:-silverbullet-secure}"
PASSWORD="${PASSWORD:-}"
STORAGE="${STORAGE:-local-lvm}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
BRIDGE="${BRIDGE:-vmbr0}"
DISK_SIZE="${DISK_SIZE:-4}"
CPU_CORES="${CPU_CORES:-1}"
RAM_SIZE="${RAM_SIZE:-512}"
SWAP_SIZE="${SWAP_SIZE:-512}"
NET="${NET:-dhcp}"
GATEWAY="${GATEWAY:-}"
DNS="${DNS:-}"
UNPRIVILEGED="${UNPRIVILEGED:-1}"
TEMPLATE="${TEMPLATE:-debian-13-standard_13.1-2_amd64.tar.zst}"

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

msg_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

msg_ok() {
  echo -e "${GREEN}[OK]${NC} $*"
}

msg_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

msg_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    msg_error "Dieses Script muss als root auf dem Proxmox-Host ausgeführt werden."
    exit 1
  fi
}

require_proxmox() {
  if ! command -v pveversion >/dev/null 2>&1; then
    msg_error "Dieses Script muss auf einem Proxmox-VE-Host ausgeführt werden."
    exit 1
  fi

  if ! command -v pct >/dev/null 2>&1; then
    msg_error "pct wurde nicht gefunden. Läuft das Script wirklich auf dem Proxmox-Host?"
    exit 1
  fi
}

get_next_ctid() {
  if [[ -z "${CTID}" ]]; then
    CTID="$(pvesh get /cluster/nextid)"
  fi
}

confirm_settings() {
  echo
  echo "============================================================"
  echo " ${APP}"
  echo "============================================================"
  echo " CTID:              ${CTID}"
  echo " Hostname:          ${HOSTNAME}"
  echo " Storage:           ${STORAGE}"
  echo " Template Storage:  ${TEMPLATE_STORAGE}"
  echo " Template:          ${TEMPLATE}"
  echo " Bridge:            ${BRIDGE}"
  echo " Network:           ${NET}"
  echo " Disk:              ${DISK_SIZE}G"
  echo " CPU:               ${CPU_CORES}"
  echo " RAM:               ${RAM_SIZE} MiB"
  echo " Swap:              ${SWAP_SIZE} MiB"
  echo " Unprivileged:      ${UNPRIVILEGED}"
  echo " Installer:         ${INSTALL_SCRIPT_URL}"
  echo "============================================================"
  echo

  read -r -p "Container mit diesen Einstellungen erstellen? [y/N]: " answer
  case "${answer,,}" in
    y|yes|j|ja)
      ;;
    *)
      msg_warn "Abgebrochen."
      exit 0
      ;;
  esac
}

download_template_if_missing() {
  local template_path="/var/lib/vz/template/cache/${TEMPLATE}"

  if [[ -f "${template_path}" ]]; then
    msg_ok "Template bereits vorhanden: ${TEMPLATE}"
    return
  fi

  msg_info "Template nicht gefunden, lade Debian-Template herunter..."

  pveam update

  if ! pveam available --section system | awk '{print $2}' | grep -qx "${TEMPLATE}"; then
    msg_error "Template ${TEMPLATE} wurde in pveam nicht gefunden."
    msg_info "Verfügbare Debian-Templates:"
    pveam available --section system | grep debian || true
    exit 1
  fi

  pveam download "${TEMPLATE_STORAGE}" "${TEMPLATE}"
  msg_ok "Template heruntergeladen: ${TEMPLATE}"
}

build_net_config() {
  NET_CONFIG="name=eth0,bridge=${BRIDGE},ip=${NET}"

  if [[ -n "${GATEWAY}" ]]; then
    NET_CONFIG="${NET_CONFIG},gw=${GATEWAY}"
  fi
}

create_container() {
  if pct status "${CTID}" >/dev/null 2>&1; then
    msg_error "CTID ${CTID} existiert bereits."
    exit 1
  fi

  local template_ref="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"

  msg_info "Erstelle LXC Container ${CTID}..."

  pct create "${CTID}" "${template_ref}" \
    --hostname "${HOSTNAME}" \
    --storage "${STORAGE}" \
    --rootfs "${STORAGE}:${DISK_SIZE}" \
    --cores "${CPU_CORES}" \
    --memory "${RAM_SIZE}" \
    --swap "${SWAP_SIZE}" \
    --net0 "${NET_CONFIG}" \
    --unprivileged "${UNPRIVILEGED}" \
    --features nesting=1,keyctl=1 \
    --onboot 1 \
    --start 0

  if [[ -n "${DNS}" ]]; then
    pct set "${CTID}" --nameserver "${DNS}"
  fi

  msg_ok "Container ${CTID} erstellt."
}

start_container() {
  msg_info "Starte Container ${CTID}..."
  pct start "${CTID}"

  for i in {1..60}; do
    if pct status "${CTID}" | grep -q "status: running"; then
      msg_ok "Container läuft."
      return
    fi
    sleep 1
  done

  msg_error "Container wurde nicht gestartet."
  exit 1
}

wait_for_network() {
  msg_info "Warte auf Netzwerk im Container..."

  for i in {1..90}; do
    CONTAINER_IP="$(pct exec "${CTID}" -- bash -c "hostname -I | awk '{print \$1}'" 2>/dev/null || true)"

    if [[ -n "${CONTAINER_IP}" ]]; then
      msg_ok "Container-IP: ${CONTAINER_IP}"
      return
    fi

    sleep 2
  done

  msg_error "Container hat keine IP-Adresse erhalten."
  exit 1
}

install_base_tools() {
  msg_info "Installiere Basiswerkzeuge im Container..."

  pct exec "${CTID}" -- bash -lc "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ca-certificates curl bash
  "

  msg_ok "Basiswerkzeuge installiert."
}

run_installer() {
  msg_info "Lade und starte SilverBullet Installer aus deinem Repo..."

  pct exec "${CTID}" -- bash -lc "curl -fsSL '${INSTALL_SCRIPT_URL}' -o /root/silverbullet-secure-install.sh"
  pct exec "${CTID}" -- chmod +x /root/silverbullet-secure-install.sh
  pct exec "${CTID}" -- bash /root/silverbullet-secure-install.sh

  msg_ok "Installer abgeschlossen."
}

show_result() {
  CONTAINER_IP="$(pct exec "${CTID}" -- bash -c "hostname -I | awk '{print \$1}'" 2>/dev/null || true)"

  echo
  msg_ok "${APP} wurde installiert."
  echo
  echo "URL:"
  echo "  http://${CONTAINER_IP}:3000"
  echo
  echo "Credentials im Container:"
  echo "  pct exec ${CTID} -- cat /root/SILVERBULLET-CREDENTIALS.txt"
  echo
  echo "Service prüfen:"
  echo "  pct exec ${CTID} -- systemctl status silverbullet --no-pager"
  echo
  echo "Logs:"
  echo "  pct exec ${CTID} -- journalctl -u silverbullet -f"
  echo
}

main() {
  require_root
  require_proxmox
  get_next_ctid
  confirm_settings
  download_template_if_missing
  build_net_config
  create_container
  start_container
  wait_for_network
  install_base_tools
  run_installer
  show_result
}

main "$@"
