#!/bin/sh

DOMAIN="$1"
CONF="/opt/etc/dnsmasq.d/90-vpn-domains.conf"
SET4="vpn_domains"
IPSET_FILE="/opt/etc/vpn_domains.ipset"
DNS_PORT=5354
META_FILE="/opt/etc/vpn_domains.meta"

if [ -z "$DOMAIN" ]; then
  echo "Usage: $0 <domain>"
  exit 1
fi

# Удаляем из dnsmasq.conf
sed -i "\\|ipset=/$DOMAIN/$SET4|d" "$CONF"

# Удаляем IP из ipset
REMOVED=0
for ip in $(dig +tcp @"127.0.0.1" -p "$DNS_PORT" "$DOMAIN" A +short); do
  if ipset del "$SET4" "$ip" 2>/dev/null; then
    REMOVED=$((REMOVED+1))
  fi
done

# Обновляем META-файл
[ -f "$META_FILE" ] && sed -i "\\|^$DOMAIN,|d" "$META_FILE"

# Перечитываем dnsmasq
pidof dnsmasq >/dev/null && kill -HUP "$(pidof dnsmasq)"

# Сохраняем ipset
ipset save "$SET4" > "$IPSET_FILE"

echo "❌ Домен $DOMAIN удалён из VPN (IP удалено: $REMOVED)"

