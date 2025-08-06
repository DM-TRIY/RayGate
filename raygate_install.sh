#!/bin/sh
set -e

echo "=== RayGate Installer ==="

# === Зависимости ===
echo -n "[1/7] Installing dependencies... "
opkg update
opkg install xray-core dnsmasq-full ipset iptables curl bind-dig python3 python3-pip

pip3 install --no-cache-dir flask bcrypt
echo "OK!"

# === Директории ===
echo -n "[2/7] Creating directories..."
mkdir -p /opt/bin/raygate/rayweb
mkdir -p /opt/etc/dnsmasq.d
mkdir -p /opt/etc/init.d
mkdir -p /opt/etc/xray
mkdir -p /opt/var/log/xray
echo "OK!"

# === Перемещение файлов ===
echo -n "[3/7] Copying files..."
CONFIG_PATH="/opt/etc/xray/config.json"
RAYWEB_PATH="/opt/bin/raygate/rayweb/rayweb.py"
RAYGATE_ADD_PATH="/opt/bin/raygate/raygate_add.sh"
mv -f ./rayweb.py $RAYWEB_PATH
mv -f ./raygate_add.sh $RAYGATE_ADD_PATH
mv -f ./S99raygate /opt/etc/init.d/S99raygate
mv -f ./config.json $CONFIG_PATH
echo "OK!"

# === Наполнение настроек ===
echo "[4/7] Configuring..."

# === raygate_add.sh ===
DNS_PORT=$(netstat -lnp 2>/dev/null | awk '/dnsmasq/ && /udp/ {split($4,a,":"); print a[2]; exit}')
IFACE=$(ip -o link show | awk -F': ' '$2 ~ /^br/ {print $2; exit}')
sed -i "s#__PORT__#$DNS_PORT#g" "$RAYGATE_ADD_PATH"
sed -i "s#__IFACE__#$IFACE#g" "$RAYGATE_ADD_PATH"
echo "[4/7] raygate_add is configured!"

# === config.json ===
echo "[4/7] Please enter you're vless:// link:"
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
echo "[4/7] Config is configured!"

# === rayweb.py ===
echo -n "[4/7] Please enter USERNAME for rayweb authorization: "
read USERNAME
echo -n "[4/7] Please enter PASSWORD for rayweb authorization: "
read -s PASSWORD
PASSHASH=$(python3 -c "import bcrypt; print(bcrypt.hashpw('$PASSWORD'.encode(), bcrypt.gensalt()).decode())")
SECRET=$(head -c 16 /dev/urandom | xxd -p)
sed -i "s#__USERNAME__#$USERNAME#g" "$RAYWEB_PATH"
sed -i "s#__PASSHASH__#$PASSHASH#g" "$RAYWEB_PATH"
sed -i "s#__SECRET__#$SECRET#g" "$RAYWEB_PATH"
echo "[4/7] Rayweb is configured!"


# === Права на исполнение ===
echo -n "[5/7] Setting permissions..."
chmod +x /opt/bin/raygate/rayweb/rayweb.py
chmod +x /opt/bin/raygate/raygate_add.sh
chmod +x /opt/etc/init.d/S99raygate
echo "OK!"

# === Стартуем ===
echo -n "[6/7] Enabling RayGate..."
/opt/etc/init.d/S99raygate enable
echo "OK!"
echo -n "[6/7] Starting RayGate and RayWeb..."
/opt/etc/init.d/S99raygate start
echo "Done!"

echo "=== Installation complete! ==="
BR_IP=$(ip -o -4 addr show dev "$IFACE" | awk '{print $4}' | cut -d/ -f1)
echo "Web UI available at: http://"$BR_IP":9090"
