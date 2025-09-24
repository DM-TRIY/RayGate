#!/bin/sh

MODE="$1"       # single | --subdomains | домен (если без ключа)
DOMAIN="$2"     # spotify.com
TAG="$3"        # группа или [auto]
SET="vpn_domains"
META_FILE="/opt/etc/vpn_domains.meta"
TIMEOUT=300
DNS_PORT="__SYSDNS__"

# Проверка аргументов
if [ "$MODE" = "--subdomains" ]; then
  if [ -z "$DOMAIN" ] || [ -z "$TAG" ]; then
    echo "Usage: $0 --subdomains <domain> <tag|[auto]>"
    exit 1
  fi
else
  DOMAIN="$MODE"
  TAG="$2"
  MODE="single"
  if [ -z "$DOMAIN" ] || [ -z "$TAG" ]; then
    echo "Usage: $0 <domain> <tag|[auto]>"
    exit 1
  fi
fi

# Если тег = [auto] → берём основу домена (до первой точки)
if [ "$TAG" = "[auto]" ]; then
  TAG=$(echo "$DOMAIN" | cut -d. -f1)
fi

# Создаём ipset, если нет
if ! ipset list "$SET" >/dev/null 2>&1; then
  ipset create "$SET" hash:ip timeout $TIMEOUT -exist
  echo "✔ Created ipset $SET"
fi

# helper: фильтр публичных IP
is_public_ip() {
  ip="$1"
  case "$ip" in
    0.*|10.*|127.*|169.254.*|192.168.*) return 1 ;;
  esac
  if echo "$ip" | grep -Eq '^172\.(1[6-9]|2[0-9]|3[0-1])\.'; then
    return 1
  fi
  first=$(echo "$ip" | cut -d. -f1)
  [ "$first" -ge 224 ] && return 1
  return 0
}

# добавляем домен
add_domain() {
  dom="$1"
  ADDED=0
  for ip in $(dig +short @"127.0.0.1" -p $DNS_PORT "$dom" A \
              | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}'); do
    if is_public_ip "$ip"; then
      if ipset add -! "$SET" "$ip" timeout $TIMEOUT 2>/dev/null; then
        ADDED=$((ADDED+1))
      fi
    fi
  done

  [ ! -f "$META_FILE" ] && touch "$META_FILE"
  if ! grep -q "^$dom," "$META_FILE"; then
    echo "$dom,$TAG" >> "$META_FILE"
  fi
  echo "✅ $dom (IP: $ADDED)"
}

# === MAIN ===
if [ "$MODE" = "single" ]; then
  echo "🔹 Single mode for: $DOMAIN (group: $TAG)"
  add_domain "$DOMAIN"

elif [ "$MODE" = "--subdomains" ]; then
  echo "🌐 Subdomains mode for: $DOMAIN (group: $TAG)"
  BASE=$(echo "$DOMAIN" | sed 's/^www\.//')

  # 1. сам домен
  add_domain "$DOMAIN"

  # 2. сабдомены через crt.sh
  SUBS=$(curl -s "https://crt.sh/?q=%25.$BASE&output=json" \
    | grep -oE '"name_value":"[^"]*"' \
    | cut -d: -f2- | tr -d '"' \
    | sed 's/\\n/\n/g' \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/^\*\.//' \
    | sed 's/\.$//' \
    | grep -F "$BASE" \
    | sort -u)

  if [ -n "$SUBS" ]; then
    echo "🔎 Found $(echo "$SUBS" | wc -l) entries in crt.sh"
    echo "$SUBS" | TAG="$TAG" DNS_PORT="$DNS_PORT" META_FILE="$META_FILE" \
      xargs -n1 -P10 -I{} sh -c '
        dom="$1"
        ADDED=0
        for ip in $(dig +short @"127.0.0.1" -p $DNS_PORT "$dom" A \
                    | grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}"); do
          case "$ip" in
            0.*|10.*|127.*|169.254.*|192.168.*) continue ;;
          esac
          if ipset add -! vpn_domains "$ip" timeout 300 2>/dev/null; then
            ADDED=$((ADDED+1))
          fi
        done
        [ ! -f "$META_FILE" ] && touch "$META_FILE"
        if ! grep -q "^$dom," "$META_FILE"; then
          echo "$dom,$TAG" >> "$META_FILE"
        fi
        echo "✅ $dom (IP: $ADDED)"
      ' _ {}
  else
    echo "⚠️ No subdomains found in crt.sh"
  fi

  # 3. geosite
  GEO_TAG=$(echo "$BASE" | cut -d. -f1)
  URL="https://raw.githubusercontent.com/v2fly/domain-list-community/master/data/${GEO_TAG}"
  GEO=$(curl -fsL "$URL" 2>/dev/null \
    | grep -v '^#' \
    | grep -v 'regexp:' \
    | tr -d '\r' \
    | sed 's/^full://')

  if [ -n "$GEO" ]; then
    echo "📦 Found $(echo "$GEO" | wc -l) entries in geosite:$GEO_TAG"
    echo "$GEO" | TAG="$TAG" DNS_PORT="$DNS_PORT" META_FILE="$META_FILE" \
      xargs -n1 -P10 -I{} sh -c '
        dom="$1"
        ADDED=0
        for ip in $(dig +short @"127.0.0.1" -p $DNS_PORT "$dom" A \
                    | grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}"); do
          case "$ip" in
            0.*|10.*|127.*|169.254.*|192.168.*) continue ;;
          esac
          if ipset add -! vpn_domains "$ip" timeout 300 2>/dev/null; then
            ADDED=$((ADDED+1))
          fi
        done
        [ ! -f "$META_FILE" ] && touch "$META_FILE"
        if ! grep -q "^$dom," "$META_FILE"; then
          echo "$dom,$TAG" >> "$META_FILE"
        fi
        echo "✅ $dom (IP: $ADDED)"
      ' _ {}
  else
    echo "⚠️ No entries found in geosite:$GEO_TAG"
  fi

  echo "✅ Subdomains mode completed for $DOMAIN"
fi
