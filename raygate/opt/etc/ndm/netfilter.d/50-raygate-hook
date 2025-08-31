#!/bin/sh
SET="vpn_domains"
TPORT=9999
IFACE="__IFACE__"

iptables -t nat -D PREROUTING -i $IFACE -p tcp -m set --match-set $SET dst --dport 443 \
  -j REDIRECT --to-port $TPORT 2>/dev/null

iptables -t nat -A PREROUTING -i $IFACE -p tcp -m set --match-set $SET dst --dport 443 \
  -j REDIRECT --to-port $TPORT