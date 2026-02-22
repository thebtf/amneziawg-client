#!/usr/bin/env bash
set -e

# Default values
AWG_INTERFACE=${AWG_INTERFACE:-wg0}
AWG_AUTO_NAT=${AWG_AUTO_NAT:-true}
AWG_MSS_CLAMP=${AWG_MSS_CLAMP:-true}
AWG_IP_FORWARD=${AWG_IP_FORWARD:-true}
DISABLE_IPV6=${DISABLE_IPV6:-false}

CONF_PATH="/config/${AWG_INTERFACE}.conf"

if [ ! -f "$CONF_PATH" ]; then
    echo "ERROR: Configuration file not found at $CONF_PATH"
    echo "Please mount a valid amneziawg config to /config/"
    exit 1
fi

# Enable IP Forwarding
if [ "$AWG_IP_FORWARD" = "true" ]; then
    echo "[info] Enabling IP Forwarding..."
    sysctl -w net.ipv4.ip_forward=1 || echo "[warn] Failed to set ipv4 forwarding"
fi

# IPv6 Handling
HAS_IPV6=true
if [ "$DISABLE_IPV6" = "true" ]; then
    echo "[info] IPv6 explicitly disabled via ENV"
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 2>/dev/null || true
    HAS_IPV6=false
elif [ ! -f /proc/net/if_inet6 ]; then
    echo "[info] IPv6 not supported by host kernel"
    HAS_IPV6=false
else
    # Check if host actually disabled it
    IPV6_SYSCTL=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo "1")
    if [ "$IPV6_SYSCTL" = "1" ]; then
         echo "[info] IPv6 disabled by host sysctl"
         HAS_IPV6=false
    elif [ "$AWG_IP_FORWARD" = "true" ]; then
         sysctl -w net.ipv6.conf.all.forwarding=1 || echo "[warn] Failed to set ipv6 forwarding"
    fi
fi

# Bring up interface
echo "[info] Starting AmneziaWG interface $AWG_INTERFACE..."
awg-quick up "$CONF_PATH"

# Apply NAT (Masquerade)
if [ "$AWG_AUTO_NAT" = "true" ]; then
    echo "[info] Applying IPv4 MASQUERADE to $AWG_INTERFACE..."
    iptables -t nat -A POSTROUTING -o "$AWG_INTERFACE" -j MASQUERADE
    if [ "$HAS_IPV6" = "true" ]; then
        echo "[info] Applying IPv6 MASQUERADE to $AWG_INTERFACE..."
        ip6tables -t nat -A POSTROUTING -o "$AWG_INTERFACE" -j MASQUERADE || echo "[warn] ip6tables MASQUERADE failed"
    fi
fi

# Apply MSS Clamping
if [ "$AWG_MSS_CLAMP" = "true" ]; then
    echo "[info] Applying TCPMSS clamping..."
    iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
    if [ "$HAS_IPV6" = "true" ]; then
        ip6tables -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu || echo "[warn] ip6tables TCPMSS failed"
    fi
fi

# Graceful shutdown handler
cleanup() {
    echo "[info] Caught signal, shutting down..."

    if [ "$AWG_MSS_CLAMP" = "true" ]; then
        iptables -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu || true
        if [ "$HAS_IPV6" = "true" ]; then
            ip6tables -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu || true
        fi
    fi

    if [ "$AWG_AUTO_NAT" = "true" ]; then
        iptables -t nat -D POSTROUTING -o "$AWG_INTERFACE" -j MASQUERADE || true
        if [ "$HAS_IPV6" = "true" ]; then
            ip6tables -t nat -D POSTROUTING -o "$AWG_INTERFACE" -j MASQUERADE || true
        fi
    fi

    awg-quick down "$CONF_PATH" || true
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT

echo "[info] AmneziaWG client is running and configured."

# Keep container alive
sleep infinity &
wait $!