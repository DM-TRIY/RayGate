#!/bin/sh
# === RayGate Sync Script ===
# Пересобирает ipset vpn_domains по списку доменов в vpn_domains.meta

SET="vpn_domains"
META_FILE="/opt/etc/vpn_domains.meta"
TIMEOUT=300
DNS_PORT="__SYSDNS__"

export TIMEOUT DNS_PORT SET META_FILE

# Создаём ipset если нет
ipset create "$SET" hash:ip timeout $TIMEOUT -exist

# Если meta нет — выходим
[ ! -f "$META_FILE" ] && exit 0

# Параллельный резолв доменов
cut -d, -f1 "$META_FILE" | grep -v '^$' | sort -u | \
xargs -n1 -P10 -I{} sh -c '
    dom="$1"
    ADDED=0
    for ip in $(dig +short @"127.0.0.1" -p $DNS_PORT "$dom" A \
                | grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}"); do
        case "$ip" in
            0.*|10.*|127.*|169.254.*|192.168.*) continue ;;
        esac
        first=$(echo "$ip" | cut -d. -f1)
        [ "$first" -ge 224 ] && continue

        if ipset add -! "$SET" "$ip" timeout $TIMEOUT 2>/dev/null; then
            ADDED=$((ADDED+1))
        fi
    done
    echo "✅ $dom (IP added: $ADDED)"
' _ {}
