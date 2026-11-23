#!/bin/zsh
# Foreground Secure MCP Tunnel; no credentials are written to disk.
set -eu
if [[ $# -lt 1 || $# -gt 3 ]]; then
    print -u2 'Usage: connect-chatgpt.sh TUNNEL_ID [--allow-write] [--allow-financials]'
    exit 1
fi
tunnel_id="$1"
shift
[[ "$tunnel_id" =~ '^tunnel_([a-z0-9]{4}_)?[a-z0-9]{32}$' ]] || { print -u2 'Invalid tunnel ID.'; exit 1; }
for flag in "$@"; do
    [[ "$flag" == --allow-write || "$flag" == --allow-financials ]] || { print -u2 'Unsupported permission flag.'; exit 1; }
done
command -v tunnel-client >/dev/null || { print -u2 'Install the official OpenAI tunnel-client first; see docs/CHATGPT_MCP.md.'; exit 1; }
[[ -n "${CONTROL_PLANE_API_KEY:-}" ]] || { print -u2 'Set CONTROL_PLANE_API_KEY locally; never paste it into chat.'; exit 1; }
app='/Applications/Coool PM.app/Contents/MacOS/CooolPM-MCP'
[[ -x "$app" ]] || { print -u2 'Install Coool PM in Applications first.'; exit 1; }
# Fail closed: an old app must never be connected to a cloud tunnel.
python3 - "$app" <<'PY'
import json, subprocess, sys
request = {'jsonrpc':'2.0','id':1,'method':'initialize','params':{
    'protocolVersion':'2025-06-18','capabilities':{},'clientInfo':{'name':'privacy-preflight','version':'1'}}}
try:
    run = subprocess.run([sys.argv[1]], input=json.dumps(request)+'\n', text=True,
                         capture_output=True, timeout=20, check=True)
    response = json.loads(run.stdout)
    assert response['result']['instructions'].startswith('Privacy: names and numbers are withheld.')
except Exception:
    sys.exit('Privacy preflight failed. Install the updated app, enable MCP, and keep it unlocked. No tunnel was started.')
print('Privacy preflight passed: aliases enabled. Starting the tunnel in the foreground.')
PY
# These are fixed program/flag tokens, not user-supplied command text.
mcp_command='"/Applications/Coool PM.app/Contents/MacOS/CooolPM-MCP"'
for flag in "$@"; do mcp_command+=" $flag"; done
exec tunnel-client run --control-plane.tunnel-id "$tunnel_id" --mcp-command "$mcp_command" --health.listen-addr 127.0.0.1:0
