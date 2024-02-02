#!/bin/sh

add_ip() {
  echo "$1" >> "$TEMP_FILE"
}

check_ip() {
  # https://stackoverflow.com/a/36760050
  if echo "$1" | grep -qP \
  '^((25[0-5]|(2[0-4]|1[0-9]|[1-9]|)[0-9])(\.(?!$)|(\/(3[0-2]|[12][0-9]|[0-9]))?$)){4}$'; then
    return 0
  else
    return 1
  fi
}

cut_special() {
  grep -vE -e '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' \
           -e '^(0\.|127\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.|255\.255\.255\.255)'
}

logger_msg() {
  logger -s -t parser "$1"
}

logger_failure() {
  logger_msg "Error: ${1}"
  exit 1
}

combine_temp_files() {
  cat "$@" > "$TEMP_FILE"
}

CONFIG="/opt/etc/unblock/config"
if [ -f "$CONFIG" ]; then
  . "$CONFIG"
else
  logger_failure "Failed to detect the \"config\" file."
fi

for _tool in dig grep ip rm seq sleep; do
  command -v "$_tool" >/dev/null 2>&1 || \
  logger_failure "The script requires \"${_tool}\" to run."
done

PIDFILE="${PIDFILE:-/tmp/parser.sh.pid}"
[ -e "$PIDFILE" ] && logger_failure "Detected \"${PIDFILE}\" file."
( echo $$ > "$PIDFILE" ) 2>/dev/null || logger_failure "Failed to create the \"${PIDFILE}\" file."
trap 'rm -f "$PIDFILE" "$TEMP_FILE" "$TEMP_FILE_PREFIX"*' EXIT
trap 'exit 2' INT TERM QUIT HUP

[ -f "$FILE" ] || logger_failure "Missing \"${FILE}\" file."

if ! ip address show dev "$IFACE" >/dev/null 2>&1; then
  logger_failure "Failed to detect the \"${IFACE}\" interface."
elif [ -z "$(ip link show "${IFACE}" up 2>/dev/null)" ]; then
  logger_failure "The interface \"${IFACE}\" is disabled."
fi

for _attempt in $(seq 0 10); do
  if dig +short +tries=1 ripe.net @localhost 2>/dev/null | grep -qvE '^$|^;'; then
    break
  elif [ "$_attempt" -eq 10 ]; then
    logger_failure "Failed to resolve the verification domain name."
  fi
  sleep 1
done

TEMP_FILE_PREFIX="/tmp/parser_temp_"
TEMP_FILE="${TEMP_FILE_PREFIX}$(date +'%Y%m%d%H%M%S')"
if [ -f "$TEMP_FILE" ]; then
  logger_failure "Failed to create temporary file."
fi

logger_msg "Parsing $(grep -c "" "$FILE") line(s) in the file \"${FILE}\"..."

DNSCONFIG="/opt/etc/unblock/dnsconfig"
NUM_DNS=$(wc -l < "$DNSCONFIG")

# Run parsing process for each DNS server in a separate script
while read -r dns_ip || [ -n "$dns_ip" ]; do
  TEMP_FILE_DNS="${TEMP_FILE_PREFIX}$(date +'%Y%m%d%H%M%S')_${dns_ip}"
  sh "/opt/etc/unblock/parse_dns.sh" "$FILE" "$TEMP_FILE_DNS" "$dns_ip" "$TEMP_FILE_DNS" "$NUM_DNS" &
done < "$DNSCONFIG"

# Wait for all child processes to complete
wait

# Combine all temporary files into one
combine_temp_files ${TEMP_FILE_PREFIX}*

if ip route flush table 1000; then
  logger_msg "Routing table #1000 has been cleared."
else
  logger_failure "Failed to clear routing table #1000."
fi

# Add routes to table 1000 from the combined temporary file
while read -r ip || [ -n "$ip" ]; do
  ip route add table 1000 "$ip" dev "$IFACE" 2>/dev/null
done < "$TEMP_FILE"

# Clean up temporary files
rm -f "$TEMP_FILE" "${TEMP_FILE_PREFIX}"*

logger_msg "Parsing complete. #1000: $(ip route list table 1000 | wc -l)."

exit 0

