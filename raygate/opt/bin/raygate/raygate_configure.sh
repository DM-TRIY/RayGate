#!/bin/sh
set -e

echo "=== RayGate Configuration Wizard ==="

CONFIG_PATH="/opt/etc/xray/config.json"
RAYWEB_PATH="/opt/bin/raygate/rayweb/rayweb.py"
RAYGATE_ADD_PATH="/opt/bin/raygate/raygate_add.sh"

# === raygate_add.sh ===
echo "[1/5] Configuring raygate_add..."
DNS_PORT=$(netstat -lnp 2>/dev/null | awk '/dnsmasq/ && /udp/ {split($4,a,":"); print a[2]; exit}')
IFACE=$(ip -o link show | awk -F': ' '$2 ~ /^br/ {print $2; exit}')
sed -i "s#__PORT__#$DNS_PORT#g" "$RAYGATE_ADD_PATH"
sed -i "s#__IFACE__#$IFACE#g" "$RAYGATE_ADD_PATH"
echo "[1/5] raygate_add.sh configured!"

# === config.json ===
echo "[2/5] Writing config..."
echo "[2/5] Please enter your vless:// link:"
read -r VLESS
ADDRESS=$(echo "$VLESS" | sed -n 's#.*@\([^:]*\):.*#\1#p')
PORT=$(echo "$VLESS" | sed -n 's#.*:\([0-9]*\)?.*#\1#p')
UUID=$(echo "$VLESS" | sed -n 's#vless://\([^@]*\)@.*#\1#p')
SNI=$(echo "$VLESS" | grep -oP '(?<=sni=)[^&]*')
PUBKEY=$(echo "$VLESS" | grep -oP '(?<=pbk=)[^&]*')
SHORTID=$(echo "$VLESS" | grep -oP '(?<=sid=)[^&]*')

sed -i "s#__ADDRESS__#${ADDRESS//\//\\/}#g" "$CONFIG_PATH"
sed -i "s#__PORT__#$PORT#g" "$CONFIG_PATH"
sed -i "s#__UUID__#$UUID#g" "$CONFIG_PATH"
sed -i "s#__SNI__#$SNI#g" "$CONFIG_PATH"
sed -i "s#__PUBKEY__#$PUBKEY#g" "$CONFIG_PATH"
sed -i "s#__SHORTID__#$SHORTID#g" "$CONFIG_PATH"
echo "[2/5] config.json configured!"

# === rayweb.py ===
echo "[3/5] Configuring web interface..."
echo -n "[3/5] Please enter USERNAME for rayweb authorization: "
read USERNAME
echo -n "[3/5] Please enter PASSWORD for rayweb authorization: "
read -s PASSWORD
PASSHASH=$(python3 -c "import bcrypt; print(bcrypt.hashpw('$PASSWORD'.encode(), bcrypt.gensalt()).decode())")
SECRET=$(head -c 16 /dev/urandom | xxd -p)
sed -i "s#__USERNAME__#$USERNAME#g" "$RAYWEB_PATH"
sed -i "s#__PASSHASH__#$PASSHASH#g" "$RAYWEB_PATH"
sed -i "s#__SECRET__#$SECRET#g" "$RAYWEB_PATH"
echo "[3/5] rayweb.py configured!"

# === Автозапуск и старт ===
echo "[4/5] Starting RayGate..."
/opt/etc/init.d/S99raygate enable
/opt/etc/init.d/S99raygate start
echo "[4/5] RayGate service started!"

BR_IP=$(ip -o -4 addr show dev "$IFACE" | awk '{print $4}' | cut -d/ -f1)
echo "=== Setup complete! ==="
echo "Web UI available at: http://$BR_IP:9090"
echo "=== Enjoy! ==="
