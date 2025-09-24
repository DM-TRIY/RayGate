#!/bin/sh

DOMAIN="$1"
TAG="${DOMAIN%.*}"
TAG="${TAG##*.}"
SET="vpn_domains"
META_FILE="/opt/etc/vpn_domains.meta"
TIMEOUT=300

if [ -z "$DOMAIN" ]; then
  echo "Usage: $0 <domain>"
  exit 1
fi

# Создаём ipset, если нет
if ! ipset list "$SET" >/dev/null 2>&1; then
  ipset create "$SET" hash:ip timeout $TIMEOUT -exist
  echo "✔ Created ipset $SET"
fi

# Резолвим через системный DNS и добавляем в ipset
ADDED=0
for ip in $(dig +short @"127.0.0.1" -p __SYSDNS__ "$DOMAIN" A); do
  if ipset add -! "$SET" "$ip" timeout $TIMEOUT 2>/dev/null; then
    ADDED=$((ADDED+1))
  fi
done

# Сохраняем в META-файл
[ ! -f "$META_FILE" ] && touch "$META_FILE"
if grep -q "^$DOMAIN," "$META_FILE"; then
  echo "ℹ $DOMAIN уже есть в $META_FILE"
else
  echo "$DOMAIN,$TAG" >> "$META_FILE"
  echo "💾 Added to meta: $DOMAIN ($TAG)"
fi

# Итог
echo "✅ Домен $DOMAIN добавлен в VPN (Добавлено IP: $ADDED)"
