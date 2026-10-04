#!/bin/bash
# Shared helper sourced by every script: loads team.env and checks it is filled in.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=team.env
source "$ROOT/team.env"

for v in MAC1_IP MAC2_IP MAC3_IP MAC4_IP; do
  if ! [[ "${!v}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: $v in team.env is '${!v}'. Put the real IP address there first." >&2
    exit 1
  fi
done

BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
IFACE="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
MY_IP="$(ipconfig getifaddr "${IFACE:-en0}" 2>/dev/null)"
EVIDENCE="$ROOT/evidence"
mkdir -p "$EVIDENCE"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
