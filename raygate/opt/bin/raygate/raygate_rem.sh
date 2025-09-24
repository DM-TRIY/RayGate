#!/bin/sh

TARGET="$1"
SET="vpn_domains"
META_FILE="/opt/etc/vpn_domains.meta"
SYNC_SCRIPT="/opt/bin/raygate/raygate_sync.sh"

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

  echo -e "⚠️ Removing group '$TAG' (domains:\n $DOMAINS)"
  sed -i "\\|,$TAG$|d" "$META_FILE"
  echo "✅ Group '$TAG' removed from META"

  if ipset list "$SET" >/dev/null 2>&1; then
    ipset flush "$SET"
    echo "🧹 IPSet '$SET' flushed"
  fi

  "$SYNC_SCRIPT" && echo "🔄 Sync completed"
  exit 0
fi

# === Удаление одного домена ===
DOMAIN="$TARGET"
if [ -f "$META_FILE" ]; then
  if grep -q "^$DOMAIN," "$META_FILE"; then
    sed -i "\\|^$DOMAIN,|d" "$META_FILE"
    echo "❌ Domain $DOMAIN removed from META"
  else
    echo "ℹ Domain $DOMAIN not found in META"
  fi
else
  echo "ℹ META file not found"
fi

if ipset list "$SET" >/dev/null 2>&1; then
  ipset flush "$SET"
  echo "🧹 IPSet '$SET' flushed"
fi

"$SYNC_SCRIPT" && echo "🔄 Sync completed"
