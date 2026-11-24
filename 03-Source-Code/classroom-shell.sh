# Source this from any folder INSIDE the repo in every NEW Terminal:
#   source "$(git rev-parse --show-toplevel)/03-Source-Code/classroom-shell.sh"
# It reads the current team.env, so commands need not hardcode yesterday's IPs.
CN_REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo 'Open a Terminal in the project repository first.' >&2
  return 1
}
. "$CN_REPO/03-Source-Code/team.env"
export CN_REPO
export CN_EDGE_IP="$MAC2_IP"
export CN_PRIMARY_DNS_IP="$MAC1_IP"
export CN_BACKUP_DNS_IP="$MAC4_IP"
export CN_A_IP="$MAC3_IP"
export CN_B_IP="$MAC4_IP"
export CN_DNS_DIR="$CN_REPO/03-Source-Code/docker-dns"
export CN_NGINX="$(command -v nginx 2>/dev/null || true)"
export CN_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
export CN_IFACE="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
printf 'Loaded: edge/primary DNS=%s | A=%s | B/backup DNS=%s | interface=%s\n' \
  "$CN_EDGE_IP" "$CN_A_IP" "$CN_B_IP" "$CN_IFACE"
