#!/bin/sh

DOMAIN="$1"
TAG="${DOMAIN%.*}"
TAG="${TAG##*.}"
CONF="/opt/etc/dnsmasq.raygate.conf"
SET4="vpn_domains"
META_FILE="/opt/etc/vpn_domains.meta"

if [ -z "$DOMAIN" ]; then
  echo "Usage: $0 <domain>"
  exit 1
fi

# Создаём ipset, если нет
if ! ipset list "$SET4" >/dev/null 2>&1; then
  ipset create "$SET4" hash:ip timeout 900 -exist
  echo "✔ Created ipset $SET4"
fi

# Добавляем в dnsmasq конфиг
ENTRY1="ipset=/$DOMAIN/$SET4"
ENTRY2="server=/$DOMAIN/127.0.0.1#53"

grep -qxF "$ENTRY1" "$CONF" || echo "$ENTRY1" >> "$CONF"
grep -qxF "$ENTRY2" "$CONF" || echo "$ENTRY2" >> "$CONF"

# === Активный резолв через системный DNS (порт 53) ===
ADDED=0
for ip in $(dig +short @"127.0.0.1" -p 53 "$DOMAIN" A); do
  if ipset add -! "$SET4" "$ip" timeout 900 2>/dev/null; then
    ADDED=$((ADDED+1))
  fi
done

# Перечитываем dnsmasq (он обновит ipset при истечении таймаута)
pidof dnsmasq >/dev/null && kill -HUP "$(pidof dnsmasq)"

# Сохраняем в META-файл
[ ! -f "$META_FILE" ] && touch "$META_FILE"
if ! grep -q "^$DOMAIN," "$META_FILE"; then
    echo "$DOMAIN,$TAG" >> "$META_FILE"
    echo "💾 Added to meta: $DOMAIN ($TAG)"
fi

echo "✅ Домен $DOMAIN добавлен в VPN (IP добавлено: $ADDED, автообновление через dnsmasq)"
