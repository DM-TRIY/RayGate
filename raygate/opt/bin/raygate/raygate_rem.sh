#!/bin/sh

TARGET="$1"
CONF="/opt/etc/dnsmasq.raygate.conf"
SET4="vpn_domains"
META_FILE="/opt/etc/vpn_domains.meta"

if [ -z "$TARGET" ]; then
  echo "Usage: $0 <domain>|group:<tag>"
  exit 1
fi

# === Удаление целой группы ===
if echo "$TARGET" | grep -q "^group:"; then
  TAG="${TARGET#group:}"
  if [ ! -f "$META_FILE" ]; then
    echo "⚠️ META file not found, nothing to remove"
    exit 0
  fi

  DOMAINS=$(awk -F, -v t="$TAG" '$2==t {print $1}' "$META_FILE")
  if [ -z "$DOMAINS" ]; then
    echo "⚠️ No domains found for group '$TAG'"
    exit 0
  fi

  echo "❌ Removing group '$TAG' (domains: $DOMAINS)"
  for dom in $DOMAINS; do
    "$0" "$dom"
  done

  # Чистим META-файл
  sed -i "\\|,$TAG$|d" "$META_FILE"
  exit 0
fi

DOMAIN="$TARGET"

# === Удаление одного домена ===
# Убираем строки из dnsmasq.raygate.conf
sed -i "\\|ipset=/$DOMAIN/$SET4|d" "$CONF"
sed -i "\\|server=/$DOMAIN/127.0.0.1#53|d" "$CONF"

# Удаляем все IP этого домена из ipset (если остались)
REMOVED=0
for ip in $(ipset list "$SET4" 2>/dev/null | awk '/^[0-9]+\./ {print $1}'); do
  if ipset del "$SET4" "$ip" 2>/dev/null; then
    REMOVED=$((REMOVED+1))
  fi
done

# META-файл
[ -f "$META_FILE" ] && sed -i "\\|^$DOMAIN,|d" "$META_FILE"

# Перечитываем dnsmasq
pidof dnsmasq >/dev/null && kill -HUP "$(pidof dnsmasq)"

echo "❌ Домен $DOMAIN удалён из VPN (IP удалено: $REMOVED)"
