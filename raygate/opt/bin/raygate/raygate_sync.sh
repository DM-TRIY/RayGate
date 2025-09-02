#!/bin/sh
# === RayGate Sync Script ===
# Пересобирает ipset vpn_domains по списку доменов в vpn_domains.meta

SET="vpn_domains"
META_FILE="/opt/etc/vpn_domains.meta"
TIMEOUT=300
DNS_PORT="__SYSDNS__"

# Функция проверки публичных IP
is_public_ip() {
    ip="$1"
    case "$ip" in
        0.*|10.*|127.*|169.254.*|192.168.*) return 1 ;;
    esac

    # 172.16.0.0 – 172.31.255.255
    if echo "$ip" | grep -Eq '^172\.(1[6-9]|2[0-9]|3[0-1])\.'; then
        return 1
    fi

    # 224.0.0.0/4 и выше (мультикаст, future use)
    first=$(echo "$ip" | cut -d. -f1)
    if [ "$first" -ge 224 ]; then
        return 1
    fi

    return 0
}

# Создаём ipset если нет
ipset create "$SET" hash:ip timeout $TIMEOUT -exist

# Если meta нет — выходим
[ ! -f "$META_FILE" ] && exit 0

# Для каждого домена из meta
while IFS=, read -r DOMAIN TAG; do
    [ -z "$DOMAIN" ] && continue

    # Берём только IPv4, отбрасываем мусор
    for ip in $(dig +short @"127.0.0.1" -p $DNS_PORT "$DOMAIN" A | \
                grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}'); do
        if is_public_ip "$ip"; then
            ipset add -! "$SET" "$ip" timeout $TIMEOUT
        fi
    done

done < "$META_FILE"
