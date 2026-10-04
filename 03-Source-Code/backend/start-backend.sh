#!/bin/bash
# Task C: start this Mac's backend.  Mac 3 -> Backend A :3001   Mac 4 -> Backend B :3002
#   ./backend/start-backend.sh          (auto-detects A or B from this Mac's IP)
#   ./backend/start-backend.sh A        (force)
source "$(dirname "$0")/../lib.sh"

ID="$1"
if [ -z "$ID" ]; then
  if   [ "$MY_IP" = "$MAC3_IP" ]; then ID=A
  elif [ "$MY_IP" = "$MAC4_IP" ]; then ID=B
  else echo "This Mac ($MY_IP) is neither Mac 3 nor Mac 4 in team.env. Pass A or B."; exit 1; fi
fi
if [ "$ID" = A ]; then PORT=$PORT_A; else PORT=$PORT_B; fi

# Prefer Apple's signed Python: managed Macs may block incoming connections to Homebrew's python.
PY=python3
if xcode-select -p >/dev/null 2>&1 && [ -x /usr/bin/python3 ]; then PY=/usr/bin/python3; fi

echo "Starting Backend $ID on port $PORT with $PY. Test from another Mac: curl -i http://$MY_IP:$PORT/api/status"
echo "If macOS asks 'Allow incoming connections for python3?' click ALLOW."
exec "$PY" "$ROOT/backend/server.py" "$ID" "$PORT"
