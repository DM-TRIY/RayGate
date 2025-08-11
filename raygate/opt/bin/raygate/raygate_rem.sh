#!/bin/sh

TAG="$1"
CONF="/opt/etc/dnsmasq.d/90-vpn-domains.conf"
SET4="vpn_domains"
IPSET_FILE="/opt/etc/vpn_domains.ipset"

if [ -z "$TAG" ]; then
  echo "Usage: $0 <domain>"
  exit 1
fi

# Удаляем из dnsmasq.conf
sed -i "\|ipset=/$TAG/$SET4|d" "$CONF"

# Удаляем IP из ipset
REMOVED=0
for ip in $(ipset list "$SET4" | awk '/^Members:/ {f=1;next} f && NF {print $1}' | grep -F "$TAG"); do
  if ipset del "$SET4" "$ip" 2>/dev/null; then
    REMOVED=$((REMOVED+1))
  fi
done

# Перечитываем dnsmasq
pidof dnsmasq >/dev/null && kill -HUP "$(pidof dnsmasq)"

# Сохраняем ipset
ipset save "$SET4" > "$IPSET_FILE"

echo "❌ Домен $TAG удалён из VPN (IP удалено: $REMOVED)"
