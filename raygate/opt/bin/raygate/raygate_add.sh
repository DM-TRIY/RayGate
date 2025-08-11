#!/bin/sh

TAG="$1"
CONF_DIR="/opt/etc/dnsmasq.d"
CONF="$CONF_DIR/90-vpn-domains.conf"
NOAAAA_CONF="$CONF_DIR/99-no-aaaa.conf"
SET4="vpn_domains"
TMP="/tmp/${TAG}.lst"
TMP_IPS="/tmp/${TAG}.ips"
DNSMASQ_SOCK="/opt/var/run/raygate-dnsmasq.sock"
TUN_PORT=9999
IFACE="__IFACE__"
IPSET_FILE="/opt/etc/vpn_domains.ipset"

if [ -z "$TAG" ]; then
  echo "Usage: $0 <domain|geosite-tag>"
  exit 1
fi

mkdir -p "$CONF_DIR"

# Создаём ipset, если нет
if ! ipset list "$SET4" >/dev/null 2>&1; then
  ipset create "$SET4" hash:ip
  echo "✔ Создан ipset $SET4"
fi

# Создаём filter-aaaa, если нет
if [ ! -f "$NOAAAA_CONF" ]; then
  echo "filter-aaaa" > "$NOAAAA_CONF"
  echo "✔ Создан $NOAAAA_CONF (filter-aaaa)"
fi

# Очищаем старые TMP
> "$TMP"
> "$TMP_IPS"

################################
# 1. Geosite
################################
GEOSITE_URL="https://raw.githubusercontent.com/v2fly/domain-list-community/master/data/${TAG}"
curl -sfL "$GEOSITE_URL" >> "$TMP" && echo "✔ Geosite: найден список для '$TAG'"

################################
# 2. crt.sh (SSL поддомены)
################################
CRT_URL="https://crt.sh/?q=%25$TAG&output=json"
curl -s "$CRT_URL" \
  | grep -oE '"name_value":"[^"]+"' \
  | cut -d: -f2 | tr -d '"' \
  | sed 's/\\n/\n/g' >> "$TMP" \
  && echo "✔ crt.sh: поддомены добавлены"

################################
# 3. Passive DNS (hackertarget)
################################
HOSTSEARCH_URL="https://api.hackertarget.com/hostsearch/?q=$TAG"
curl -sfL "$HOSTSEARCH_URL" | cut -d, -f1 >> "$TMP" && echo "✔ Passive DNS: поддомены добавлены"

################################
# 4. Certspotter
################################
CERTSPOTTER_URL="https://api.certspotter.com/v1/issuances?domain=$TAG&include_subdomains=true&expand=dns_names"
curl -s "$CERTSPOTTER_URL" \
  | grep -oE '"dns_names":\[[^]]+\]' \
  | grep -oE '"[^"]+"' \
  | tr -d '"' >> "$TMP" \
  && echo "✔ Certspotter: поддомены добавлены"

################################
# 5. RapidDNS
################################
RAPID_URL="https://rapiddns.io/subdomain/$TAG?full=1"
curl -s "$RAPID_URL" | grep -oE '>[a-zA-Z0-9.-]+\.'$TAG'<' \
  | sed 's/[<>]//g' >> "$TMP" \
  && echo "✔ RapidDNS: поддомены добавлены"

################################
# 6. ThreatCrowd
################################
THREAT_URL="https://www.threatcrowd.org/searchApi/v2/domain/report/?domain=$TAG"
curl -s "$THREAT_URL" \
  | grep -oE '"domain":"[^"]+"' \
  | cut -d: -f2 | tr -d '"' >> "$TMP" \
  && echo "✔ ThreatCrowd: поддомены добавлены"

################################
# 7. Очистка и нормализация (первичный список)
################################
sort -u "$TMP" \
  | tr '[:upper:]' '[:lower:]' \
  | sed 's/^\*\.//' \
  | sed 's/^\.\(.*\)/\1/' \
  | sed 's/\.$//' \
  | grep -Ev '(^$|localhost$|local$|localdomain$|invalid$|test$|example$)' \
  > "$TMP.clean"
mv "$TMP.clean" "$TMP"

################################
# 8. Резолвим первичный список → IP
################################
while read -r domain; do
  for ip in $(dig +tcp @127.0.0.1 -p 5354 "$domain" A +short +time=3 +tries=1); do
    echo "$ip" >> "$TMP_IPS"
    ipset add "$SET4" "$ip" 2>/dev/null || true
  done
done < "$TMP"

################################
# 9. ASN-поиск по IP → домены
################################
ASN_TMP="/tmp/${TAG}.asn.domains"
> "$ASN_TMP"
for ip in $(sort -u "$TMP_IPS"); do
  ASN=$(whois -h whois.cymru.com " -v $ip" | awk 'NR>1 {print $1}' | tr -d ' ')
  [ -z "$ASN" ] && continue
  curl -s "https://api.hackertarget.com/aslookup/?q=AS$ASN" \
    | grep -Eo '[a-zA-Z0-9.-]+' \
    | grep -vE '^[0-9.]+$' >> "$ASN_TMP"
done

# Добавляем найденные по ASN в основной список
cat "$ASN_TMP" >> "$TMP"

################################
# 10. Финальная очистка списка (все домены)
################################
sort -u "$TMP" \
  | tr '[:upper:]' '[:lower:]' \
  | sed 's/^\*\.//' \
  | sed 's/^\.\(.*\)/\1/' \
  | sed 's/\.$//' \
  | grep -Ev '(^$|localhost$|local$|localdomain$|invalid$|test$|example$)' \
  > "$TMP.clean"
mv "$TMP.clean" "$TMP"

################################
# 11. Запись в dnsmasq.conf
################################
ADDED=0
touch "$CONF"
while read -r domain; do
  entry="ipset=/${domain}/${SET4}"
  grep -qxF "$entry" "$CONF" || { echo "$entry" >> "$CONF"; ADDED=$((ADDED+1)); }
done < "$TMP"
[ "$ADDED" -gt 0 ] && echo "✅ В dnsmasq добавлено $ADDED записей"

# Перечитываем dnsmasq
pidof dnsmasq >/dev/null && kill -HUP "$(pidof dnsmasq)" && echo "🔄 dnsmasq перечитан"

################################
# 12. Резолвим финальный список и добавляем IP в ipset
################################
while read -r domain; do
  for ip in $(dig +tcp @127.0.0.1 -p 5354 "$domain" A +short +time=3 +tries=1); do
    ipset add "$SET4" "$ip" 2>/dev/null || true
  done
done < "$TMP"

# Чистим временные файлы
rm -f "$TMP" "$TMP_IPS" "$ASN_TMP"

# Сохраняем ipset
ipset save "$SET4" > "$IPSET_FILE"
echo "💾 IpSet сохранён в $IPSET_FILE"
