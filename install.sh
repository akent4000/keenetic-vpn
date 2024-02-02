#!/bin/sh

check_command() {
  command -v "$1" >/dev/null 2>&1
}

msg() {
  printf "%s\n" "$1"
}

error_msg() {
  printf "[!] %s\n" "$1"
}

failure() {
  error_msg "$1"
  exit 1
}

pkg_install() {
  msg "Installing package \"${1}\"..."
  if opkg install "$1" >/dev/null 2>&1; then
    msg "Package \"${1}\" installed."
  else
    failure "Error installing package \"${1}\"."
  fi
}

download() {
  check_command curl || failure "curl is required for file downloads."
  if curl -sfL --connect-timeout 7 "$1" -o "$2"; then
    msg "File \"${2##*/}\" downloaded."
  else
    failure "Failed to download file \"${2##*/}\"."
  fi
}

mk_file_exec() {
  check_command chmod || failure "chmod is required for changing file permissions."
  if [ -f "$1" ] && chmod +x "$1" 2>/dev/null; then
    msg "Execution permissions set for file \"${1}\"."
  else
    failure "Failed to set execution permissions for file \"${1}\"."
  fi
}

crt_symlink() {
  check_command ln || failure "ln is required for creating symlinks."
  if ln -sf "$1" "$2" 2>/dev/null; then
    msg "Symlink \"${2##*/}\" created in directory \"${2%/*}\"."
  else
    failure "Failed to create symlink \"${2##*/}\"."
  fi
}

msg "Installing keenetic-traffic..."

INSTALL_DIR="/opt/etc/unblock-srv"
REPO_URL="https://raw.githubusercontent.com/akent4000/keenetic-vpn/main"

check_command opkg || failure "opkg is required for package installation."
opkg update >/dev/null 2>&1 || failure "Failed to update Entware package list."

for pkg in bind-dig cron grep; do
  if opkg status "${pkg}" >/dev/null 2>&1; then
    continue
  fi

  pkg_install "$pkg"
  sleep 1

  if [ "$pkg" = "cron" ]; then
    sed -i 's/^ARGS="-s"$/ARGS=""/' /opt/etc/init.d/S10cron && \
    msg "Disabled cron log flooding in router logs."
    /opt/etc/init.d/S10cron restart >/dev/null
  fi
done

if [ ! -d "$INSTALL_DIR" ]; then
  if mkdir -p "$INSTALL_DIR"; then
    msg "Directory \"${INSTALL_DIR}\" created."
  else
    failure "Failed to create directory \"${INSTALL_DIR}\"."
  fi
fi

[ ! -f "${INSTALL_DIR}/config" ] && download "${REPO_URL}/config" "${INSTALL_DIR}/config"

for _file in parser.sh start-stop.sh uninstall.sh parse-dns.sh; do
  download "${REPO_URL}/${_file}" "${INSTALL_DIR}/${_file}"
  mk_file_exec "${INSTALL_DIR}/${_file}"
done

crt_symlink "${INSTALL_DIR}/parser.sh" "/opt/etc/cron.daily/routing_table_update"
crt_symlink "${INSTALL_DIR}/start-stop.sh" "/opt/etc/ndm/ifstatechanged.d/ip_rule_switch"

if [ ! -f "${INSTALL_DIR}/unblock-list.txt" ]; then
  if touch "${INSTALL_DIR}/unblock-list.txt" 2>/dev/null; then
    msg "File \"${INSTALL_DIR}/unblock-list.txt\" created."
  else
    error_msg "Failed to create file \"${INSTALL_DIR}/unblock-list.txt\"."
  fi
fi

DNS_LIST_FILE="${INSTALL_DIR}/dns-list.txt"
DNS_LIST_CONTENT="8.8.8.8
8.8.4.4
1.1.1.1
1.0.0.1
208.67.222.222
208.67.220.220
9.9.9.9
149.112.112.112
77.88.8.8
77.88.8.1"

if [ ! -f "${DNS_LIST_FILE}" ]; then
  if touch "${DNS_LIST_FILE}" 2>/dev/null; then
    echo "${DNS_LIST_CONTENT}" > "$DNS_LIST_FILE"
  else
    error_msg "Failed to create file \"${DNS_LIST_FILE}\"."
  fi
  msg "File \"${DNS_LIST_FILE}\" created and filled."
fi

printf "%s\n" "---" "Installation completed."
msg "Don't forget to enter the VPN interface name in the config file, and also fill in the unblock-list.txt file."

exit 0
