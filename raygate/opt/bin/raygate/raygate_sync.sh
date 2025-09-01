#!/bin/sh
# === RayGate Sync Script ===
# Пересобирает ipset vpn_domains по списку доменов в vpn_domains.meta

SET="vpn_domains"
META_FILE="/opt/etc/vpn_domains.meta"
TIMEOUT=300

# Создаём ipset если нет
ipset create "$SET" hash:ip timeout $TIMEOUT -exist

# Если meta нет — выходим
[ ! -f "$META_FILE" ] && exit 0

# Для каждого домена из meta
while IFS=, read -r DOMAIN TAG; do
    [ -z "$DOMAIN" ] && continue

    for ip in $(dig +short @"127.0.0.1" -p __SYSDNS__ "$DOMAIN" A); do
        ipset add -! "$SET" "$ip" timeout $TIMEOUT
    done

done < "$META_FILE"
