#!/usr/bin/env bash
# ============================================================================
# OpenClaw Vertex AI Module — Uninstaller
# Removes Google Vertex AI support and LiteLLM Bridge
#
# Created by ROOH (https://rooh.red)
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
PROXY_DIR="$HOME/.openclaw/vertex-proxy"
PLIST_PATH="$HOME/Library/LaunchAgents/com.rooh.vertex-proxy.plist"

echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║   🦞 OpenClaw Vertex AI Module — Uninstaller    ║"
echo "  ║     Created by ROOH — https://rooh.red          ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

if [ ! -f "$OPENCLAW_CONFIG" ]; then
    echo -e "${RED}✗ OpenClaw config not found at $OPENCLAW_CONFIG${NC}"
    exit 1
fi

# ── Remove Proxy Service ────────────────────────────────────────────────────
echo -e "${BOLD}Stopping Vertex AI Bridge...${NC}"

if [ -f "$PLIST_PATH" ]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm "$PLIST_PATH"
    echo -e "  ${GREEN}✓${NC} LaunchAgent removed"
else
    echo -e "  ${YELLOW}⚠${NC} LaunchAgent not found (maybe already removed)"
fi

if [ -d "$PROXY_DIR" ]; then
    rm -rf "$PROXY_DIR"
    echo -e "  ${GREEN}✓${NC} Proxy files removed ($PROXY_DIR)"
fi

# ── Remove OpenClaw Config ──────────────────────────────────────────────────
# Check if provider exists
export _VERTEX_CONFIG_PATH="$OPENCLAW_CONFIG"
if ! python3 -c "
import json, sys, os
with open(os.environ['_VERTEX_CONFIG_PATH']) as f:
    cfg = json.load(f)
sys.exit(0 if 'google-vertex' in cfg.get('models', {}).get('providers', {}) else 1)
" 2>/dev/null; then
    echo -e "${YELLOW}⚠ Provider 'google-vertex' not found in config.${NC}"
else
    # Backup
    cp "$OPENCLAW_CONFIG" "$OPENCLAW_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"

    # Remove
    python3 << 'PYTHON_SCRIPT'
import json, os
config_path = os.environ["_VERTEX_CONFIG_PATH"]

with open(config_path, 'r') as f: config = json.load(f)

if 'google-vertex' in config.get('models', {}).get('providers', {}):
    del config['models']['providers']['google-vertex']
    print("  Removed google-vertex provider")

# Reset default model
model = config.get('agents', {}).get('defaults', {}).get('model', {}).get('primary', '')
if model.startswith('google-vertex/'):
    fallback = None
    for pname, pconfig in config.get('models', {}).get('providers', {}).items():
        if pconfig.get('models'):
            fallback = f"{pname}/{pconfig['models'][0]['id']}"
            break
    if fallback:
        config['agents']['defaults']['model']['primary'] = fallback
        print(f"  Default model reset to: {fallback}")
    else:
        print("  Warning: No fallback model found.")

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')
PYTHON_SCRIPT
fi

unset _VERTEX_CONFIG_PATH

# ── Restart Gateway ─────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Restarting gateway...${NC}"

if [[ "$(uname)" == "Darwin" ]]; then
    launchctl kickstart -k "gui/$(id -u)/ai.openclaw.gateway" 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}✅ Uninstalled successfully.${NC}"
echo ""
