#!/bin/sh

FILE="$1"
TEMP_FILE="$2"
DNS_IP="$3"
TEMP_FILE_PREFIX="$4"
NUM_DNS="$5"

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

DNSCONFIG="/opt/etc/unblock-srv/dns-list.txt"

while read -r line || [ -n "$line" ]; do
  [ -z "$line" ] && continue
  [ "${line:0:1}" = "#" ] && continue

  if check_ip "$line"; then
    add_ip "$line"
  else
    dig_host=$(dig +short "$line" @"$DNS_IP" 2>&1 | grep -vE '[a-z]+' | cut_special)
    if [ -n "$dig_host" ]; then
      for i in $dig_host; do check_ip "$i" && add_ip "$i"; done
    else
      logger_msg "Failed to resolve the domain name using DNS server ${DNS_IP}: line \"${line}\" ignored."
    fi
  fi
done < "$FILE"

logger_msg "Parsing complete for DNS server ${DNS_IP}. Parsed IPs written to ${TEMP_FILE}."

exit 0

