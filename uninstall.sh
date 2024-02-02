#!/bin/sh

msg() {
  printf "%s\n" "$1"
}

error_msg() {
  printf "[!] %s\n" "$1"
}

delete_file() {
  if [ -f "$1" ]; then
    if rm "$1" 2>/dev/null; then
      msg "${2:-"File"} \"${1##*/}\" deleted."
    else
      error_msg "Failed to delete ${3:-"file"} \"${1##*/}\"."
    fi
  else
    msg "${2:-"File"} \"${1##*/}\" not found."
  fi
}

PRJ_DIR="/opt/etc/unblock"

for _tool in ip rm; do
  command -v "$_tool" >/dev/null 2>&1 || {
    error_msg "The script requires \"${_tool}\" to be installed."
    exit 1
  }
done

# https://stackoverflow.com/a/226724
read -p "Proceed with deletion? [y/n] " yn
case "$yn" in
  [Yy]*) ;;
      *) msg "Deletion canceled."; exit 1;;
esac

if ip route flush table 1000; then
  msg "Routing table #1000 cleared."
fi

if ip rule del priority 1995 2>/dev/null; then
  msg "Routing rule deleted."
fi

delete_file "/opt/etc/cron.daily/routing_table_update" "Symlink" "symlink"
delete_file "/opt/etc/ndm/ifstatechanged.d/ip_rule_switch" "Symlink" "symlink"

for _file in \
  config parser.sh start-stop.sh uninstall.sh unblock-list.txt; do
  delete_file "${PRJ_DIR}/${_file}"
done

# https://unix.stackexchange.com/a/615900
if [ -d "${PRJ_DIR}" ] && \
   [ "$(echo "${PRJ_DIR}/"*)" = "${PRJ_DIR}/*" ]; then
  if rm -r "${PRJ_DIR}" 2>/dev/null; then
    msg "Directory \"${PRJ_DIR}\" deleted."
  else
    error_msg "Failed to delete directory \"${PRJ_DIR}\"."
  fi
fi

printf "%s\n" "---" "Deletion completed."

exit 0
