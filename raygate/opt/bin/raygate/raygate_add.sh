#!/bin/sh

DOMAIN="$1"
# Используем домен второго уровня в качестве тега
TAG="${DOMAIN%.*}"
TAG="${TAG##*.}"
CONF_DIR="/opt/etc/dnsmasq.d"
CONF="$CONF_DIR/90-vpn-domains.conf"
SET4="vpn_domains"
DEFAULT_META_FILE="/opt/etc/vpn_domains.meta"
DNS_PORT=5354 # У НАС СВОЙ DNSMASQ!!!

if [ -z "$DOMAIN" ]; then
  echo "Usage: $0 <domain>"
  exit 1
fi

mkdir -p "$CONF_DIR"

# Создаём ipset, если нет
if ! ipset list "$SET4" >/dev/null 2>&1; then
  ipset create "$SET4" hash:ip timeout 900 -exist
  echo "✔ Создан ipset $SET4"
fi

# Запись в dnsmasq.conf
ENTRY="ipset=/$DOMAIN/$SET4"
grep -qxF "$ENTRY" "$CONF" || echo "$ENTRY" >> "$CONF"

# Резолвим домен → IP → добавляем в ipset
ADDED=0
for ip in $(dig +tcp @"127.0.0.1" -p "$DNS_PORT" "$DOMAIN" A +short); do
  if ipset add "$SET4" "$ip" timeout 900 2>/dev/null; then
    ADDED=$((ADDED+1))
  fi
done

# Перечитываем dnsmasq
pidof dnsmasq >/dev/null && kill -HUP "$(pidof dnsmasq)"

echo "✅ Домен $DOMAIN добавлен в VPN (новых IP: $ADDED)"

# === Запись в META файл ===
META_FILE="${META_FILE:-$DEFAULT_META_FILE}"
mkdir -p "$(dirname "$META_FILE")"
[ ! -f "$META_FILE" ] && touch "$META_FILE"
if ! grep -q "^$DOMAIN," "$META_FILE"; then
    echo "$DOMAIN,$TAG" >> "$META_FILE"
    echo "💾 Added to meta: $DOMAIN ($TAG)"
fi
