#!/bin/sh

SET_NAME="vpn_domains"
IFACE="__IFACE__"
TUN_PORT=9999

while true; do
    if iptables -t nat -C PREROUTING -i "$IFACE" -p tcp -m set --match-set "$SET_NAME" dst --dport 443 -j REDIRECT --to-port $TUN_PORT 2>/dev/null; then
        echo "[RAYGATE_WATCHDOG] Iptables rule is OK for $IFACE → $SET_NAME"
    else
        echo "[RAYGATE_WATCHDOG] Iptables rule missing, adding..."
        iptables -t nat -A PREROUTING -i "$IFACE" -p tcp -m set --match-set "$SET_NAME" dst --dport 443 -j REDIRECT --to-port $TUN_PORT
    fi
    sleep 60
done
