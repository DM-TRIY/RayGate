#!/bin/sh

TAG="$1"
CONF_DIR="/opt/etc/dnsmasq.d"
CONF="$CONF_DIR/90-vpn-domains.conf"
NOAAAA_CONF="$CONF_DIR/99-no-aaaa.conf"
SET4="vpn_domains"
TMP="/tmp/${TAG}.lst"
RAW_URL="https://raw.githubusercontent.com/v2fly/domain-list-community/master/data/${TAG}"
DNS_SERVER="127.0.0.1"
DNS_PORT="__PORT__"
TUN_PORT=9999
IFACE="__IFACE__"
IPSET_FILE="/opt/etc/vpn_domains.ipset"

if ! ipset list "$SET4" >/dev/null 2>&1; then
  ipset create "$SET4" hash:ip
  echo "✔ Создан ipset $SET4"
fi

mkdir -p "$CONF_DIR"
if [ ! -f "$NOAAAA_CONF" ]; then
  cat > "$NOAAAA_CONF" << 'EOF'
filter-aaaa
EOF
  echo "✔ Создан $NOAAAA_CONF (filter-aaaa)"
fi

[ -z "$TAG" ] && { echo "Usage: $0 <geosite-tag|domain>"; exit 1; }

echo "⏬ Загружаем список доменов для '$TAG'..."
if curl -sfL "$RAW_URL" -o "$TMP"; then
  echo "✔ Скачан список доменов из тега '$TAG'"
else
  echo "❗ Тег '$TAG' не найден — используем '$TAG' как одиночный домен"
  echo "$TAG" > "$TMP"
fi

ADDED=0
touch "$CONF"
while IFS= read -r line; do
  domain="${line%%#*}"
  domain="${domain#.}"
  [ -z "$domain" ] && continue
  entry="ipset=/${domain}/${SET4}"
  entryw="ipset=/.${domain}/${SET4}"
  grep -qxF "$entry" "$CONF" || { echo "$entry" >> "$CONF"; ADDED=$((ADDED+1)); }
  grep -qxF "$entryw" "$CONF" || { echo "$entryw" >> "$CONF"; ADDED=$((ADDED+1)); }
done < "$TMP"
[ "$ADDED" -gt 0 ] && echo "✅ Добавлено $ADDED ipset-записей"

pidof dnsmasq >/dev/null && { kill -HUP "$(pidof dnsmasq)"; echo "dnsmasq перечитан"; }

while IFS= read -r line; do
  dom="${line%%#*}"
  dom="${dom#.}"
  [ -z "$dom" ] && continue
  for ip in $(dig @"$DNS_SERVER" -p "$DNS_PORT" "$dom" A +short); do
    ipset add "$SET4" "$ip" 2>/dev/null || true
  done
done < "$TMP"

rm -f "$TMP"

if [ "$TAG" = "twimg.com" ]; then
  for sub in abs pbs video ton; do
    echo "🔄 Добавляем $sub.$TAG"
    "$0" "$sub.$TAG"
  done
fi

iptables -t nat -D PREROUTING -i "$IFACE" -p tcp -m set --match-set "$SET4" dst --dport 443 -j REDIRECT --to-ports "$TUN_PORT" 2>/dev/null
iptables -t nat -A PREROUTING -i "$IFACE" -p tcp -m set --match-set "$SET4" dst --dport 443 -j REDIRECT --to-ports "$TUN_PORT"

ipset save "$SET4" > "$IPSET_FILE"
echo "💾 IpSet сохранён в $IPSET_FILE"

ipset list "$SET4" | head -n 20

