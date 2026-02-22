# amneziawg-client

Generic Docker image for running an AmneziaWG client using `amneziawg-go` and `amneziawg-tools`.

## What it does

- Brings up an AmneziaWG interface from `/config/<name>.conf`
- Manages NAT and routing rules automatically in `entrypoint.sh`
- Supports both IPv4 and IPv6 with graceful fallback when IPv6 is unavailable

## Files expected

- Mount a WireGuard/AmneziaWG config at: `/config/wg0.conf`

## Build

```bash
git clone <repo>
docker build -t amneziawg-client .
```

## Run

```bash
docker run --rm \
  --cap-add NET_ADMIN \
  --device /dev/net/tun \
  -v /path/to/config:/config:ro \
  -e AWG_INTERFACE=wg0 \
  -e AWG_AUTO_NAT=true \
  -e AWG_MSS_CLAMP=true \
  -e AWG_IP_FORWARD=true \
  -e DISABLE_IPV6=false \
  amneziawg-client
```

## Environment variables

- `AWG_INTERFACE` (default: `wg0`) — config file name under `/config`
- `AWG_AUTO_NAT` (default: `true`) — add MASQUERADE rules
- `AWG_MSS_CLAMP` (default: `true`) — add TCPMSS clamping rules
- `AWG_IP_FORWARD` (default: `true`) — enables IP forwarding
- `DISABLE_IPV6` (default: `false`) — force disables IPv6 processing