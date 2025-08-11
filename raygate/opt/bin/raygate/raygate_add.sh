#!/bin/sh

DOMAIN="$1"
TAG="${DOMAIN%%.*}"
CONF_DIR="/opt/etc/dnsmasq.d"
CONF="$CONF_DIR/90-vpn-domains.conf"
SET4="vpn_domains"
IPSET_FILE="/opt/etc/vpn_domains.ipset"
META_FILE="/opt/etc/vpn_domains.meta"
DNS_PORT=5354

if [ -z "$DOMAIN" ]; then
  echo "Usage: $0 <domain>"
  exit 1
fi

mkdir -p "$CONF_DIR"

# Создаём ipset, если нет
if ! ipset list "$SET4" >/dev/null 2>&1; then
  ipset create "$SET4" hash:ip
  echo "✔ Создан ipset $SET4"
fi

# Запись в dnsmasq.conf
ENTRY="ipset=/$DOMAIN/$SET4"
grep -qxF "$ENTRY" "$CONF" || echo "$ENTRY" >> "$CONF"

# Резолвим домен → IP → добавляем в ipset
ADDED=0
for ip in $(dig +tcp @"127.0.0.1" -p "$DNS_PORT" "$DOMAIN" A +short); do
  if ipset add "$SET4" "$ip" 2>/dev/null; then
    ADDED=$((ADDED+1))
  fi
done

# Перечитываем dnsmasq
pidof dnsmasq >/dev/null && kill -HUP "$(pidof dnsmasq)"

# Сохраняем ipset
ipset save "$SET4" > "$IPSET_FILE"

echo "✅ Домен $DOMAIN добавлен в VPN (новых IP: $ADDED)"

# === Запись в META файл ===
[ ! -f "$META_FILE" ] && touch "$META_FILE"
if ! grep -q "^$DOMAIN," "$META_FILE"; then
    echo "$DOMAIN,$TAG" >> "$META_FILE"
    echo "💾 Added to meta: $DOMAIN ($TAG)"
fi

