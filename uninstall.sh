#!/usr/bin/env bash
# ============================================================================
# OpenClaw Vertex AI Module — Uninstaller
# Removes Google Vertex AI support from OpenClaw
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

# Check if provider exists
export _VERTEX_CONFIG_PATH="$OPENCLAW_CONFIG"
if ! python3 -c "
import json, sys, os
with open(os.environ['_VERTEX_CONFIG_PATH']) as f:
    cfg = json.load(f)
sys.exit(0 if 'google-vertex' in cfg.get('models', {}).get('providers', {}) else 1)
" 2>/dev/null; then
    echo -e "${YELLOW}⚠ Google Vertex AI provider not found in config. Nothing to remove.${NC}"
    exit 0
fi

read -p "Remove Google Vertex AI provider from OpenClaw? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "  Aborted."
    exit 0
fi

# Backup
BACKUP_FILE="$OPENCLAW_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
cp "$OPENCLAW_CONFIG" "$BACKUP_FILE"
echo -e "  ${GREEN}✓${NC} Backup: $BACKUP_FILE"

# Remove provider
python3 << 'PYTHON_SCRIPT'
import json
import os

config_path = os.environ["_VERTEX_CONFIG_PATH"]

with open(config_path, 'r') as f:
    config = json.load(f)

# Remove provider
if 'google-vertex' in config.get('models', {}).get('providers', {}):
    del config['models']['providers']['google-vertex']
    print("  Removed google-vertex provider")

# Reset default model if it was Vertex
model = config.get('agents', {}).get('defaults', {}).get('model', {}).get('primary', '')
if model.startswith('google-vertex/'):
    fallback = None
    # Find first available model
    for pname, pconfig in config.get('models', {}).get('providers', {}).items():
        models = pconfig.get('models', [])
        if models:
            fallback = f"{pname}/{models[0]['id']}"
            break
    if fallback:
        config['agents']['defaults']['model']['primary'] = fallback
        print(f"  Default model reset to: {fallback}")
    else:
        print("  Warning: No fallback model found. Please set a default model manually.")

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')
PYTHON_SCRIPT

unset _VERTEX_CONFIG_PATH

# Restart gateway
echo ""
echo -e "${BOLD}Restarting gateway...${NC}"

RESTARTED=false
if [[ "$(uname)" == "Darwin" ]]; then
    if launchctl kickstart -k "gui/$(id -u)/ai.openclaw.gateway" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Gateway restarted"
        RESTARTED=true
    fi
elif command -v systemctl &>/dev/null; then
    if systemctl --user restart openclaw-gateway 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Gateway restarted"
        RESTARTED=true
    fi
fi

if [ "$RESTARTED" = false ]; then
    echo -e "  ${YELLOW}⚠${NC} Please restart the gateway manually."
fi

echo ""
echo -e "${GREEN}✅ Vertex AI module removed successfully.${NC}"
echo -e "  Backup: $BACKUP_FILE"
echo ""
