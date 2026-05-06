#!/usr/bin/env bash

# Copyright (c) 2026
# Author: custom
# License: MIT
# Source: https://silverbullet.md
# GitHub: https://github.com/silverbulletmd/silverbullet
#
# Community-Scripts-style LXC entrypoint for SilverBullet Secure

source <(curl -fsSL https://raw.githubusercontent.com/Jello-de/PMX_Scripts/main/misc/build.func)

APP="Silverbullet-Secure"
var_tags="${var_tags:-notes;markdown;pkm}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "${APP}"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -x /opt/silverbullet/bin/silverbullet ]]; then
    msg_error "No ${APP} installation found!"
    exit 1
  fi

  if check_for_gh_release "silverbullet" "silverbulletmd/silverbullet"; then
    msg_info "Stopping SilverBullet"
    systemctl stop silverbullet
    msg_ok "Stopped SilverBullet"

    msg_info "Updating SilverBullet"
    fetch_and_deploy_gh_release \
      "silverbullet" \
      "silverbulletmd/silverbullet" \
      "prebuild" \
      "latest" \
      "/opt/silverbullet/bin" \
      "silverbullet-server-linux-x86_64.zip"
    chmod 0755 /opt/silverbullet/bin/silverbullet
    chown root:root /opt/silverbullet/bin/silverbullet
    msg_ok "Updated SilverBullet"

    msg_info "Starting SilverBullet"
    systemctl start silverbullet
    msg_ok "Started SilverBullet"

    msg_ok "Updated successfully!"
  fi

  exit 0
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
echo -e "${INFO}${YW} Credentials are stored inside the container at:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}/etc/silverbullet/silverbullet.env${CL}"
