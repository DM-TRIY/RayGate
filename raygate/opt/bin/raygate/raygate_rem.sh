#!/bin/sh

TARGET="$1"
SET="vpn_domains"
META_FILE="/opt/etc/vpn_domains.meta"

if [ -z "$TARGET" ]; then
  echo "Usage: $0 <domain>|group:<tag>"
  exit 1
fi

# === Удаление целой группы ===
if echo "$TARGET" | grep -q "^group:"; then
  TAG="${TARGET#group:}"
  if [ ! -f "$META_FILE" ]; then
    echo "❌ META file not found, nothing to remove"
    exit 0
  fi

  DOMAINS=$(awk -F, -v t="$TAG" '$2==t {print $1}' "$META_FILE")
  if [ -z "$DOMAINS" ]; then
    echo "❌ No domains found for group '$TAG'"
    exit 0
  fi

  echo "⚠️ Removing group '$TAG' (domains: $DOMAINS)"
  TOTAL_REMOVED=0
  for dom in $DOMAINS; do
    COUNT=$("$0" "$dom" | grep -oE '[0-9]+$')
    TOTAL_REMOVED=$((TOTAL_REMOVED+COUNT))
  done

  # Чистим META-файл от строк с этим тегом
  sed -i "\\|,$TAG$|d" "$META_FILE"
  echo "✅ Group '$TAG' removed (total IP removed: $TOTAL_REMOVED)"
  exit 0
fi

DOMAIN="$TARGET"

# === Удаление одного домена ===
REMOVED=0
if ipset list "$SET" >/dev/null 2>&1; then
  for ip in $(dig +short @"127.0.0.1" -p __SYSDNS__ "$DOMAIN" A); do
    if ipset del "$SET" "$ip" 2>/dev/null; then
      REMOVED=$((REMOVED+1))
    fi
  done
fi

# META-файл
if [ -f "$META_FILE" ]; then
  if grep -q "^$DOMAIN," "$META_FILE"; then
    sed -i "\\|^$DOMAIN,|d" "$META_FILE"
    echo "❌ Домен $DOMAIN удалён из VPN (IP удалено: $REMOVED)"
  else
    echo "ℹ Домен $DOMAIN не найден в META (IP удалено: $REMOVED)"
  fi
else
  echo "ℹ META file not found (IP удалено: $REMOVED)"
fi
