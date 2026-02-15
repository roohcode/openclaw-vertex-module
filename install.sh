#!/usr/bin/env bash
# ============================================================================
# OpenClaw Vertex AI Module — Installer (v2.0)
# Adds Google Vertex AI support to OpenClaw via LiteLLM Bridge
#
# Features:
# - Auto-detects compatible Python (3.13/3.12/3.11) to avoid 3.14+ issues
# - Installs local LiteLLM proxy in isolated venv
# - Configures macOS LaunchAgent for background operation
# - Patches OpenClaw config with valid schema (sanitized inputs)
#
# Created by ROOH (https://rooh.red)
# ============================================================================

set -euo pipefail

# ── Configuration ───────────────────────────────────────────────────────────
OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
PROXY_DIR="$HOME/.openclaw/vertex-proxy"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_LABEL="com.rooh.vertex-proxy"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Helpers ─────────────────────────────────────────────────────────────────

# Banner
print_banner() {
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║   🦞 OpenClaw Vertex AI Module — Installer      ║"
    echo "  ║     Created by ROOH — https://rooh.red          ║"
    echo "  ╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Python Detection
find_python() {
    local cmd=""
    
    # 1. User Override
    if [ -n "${VERTEX_PYTHON:-}" ]; then
        echo "$VERTEX_PYTHON"
        return
    fi
    
    # 2. Check specific stable versions (Homebrew & System)
    # Priority: 3.13 > 3.12 > 3.11 (Known stable with uvloop)
    for v in 3.13 3.12 3.11; do
        # Homebrew path (preferred)
        if [ -x "/opt/homebrew/bin/python$v" ]; then
            echo "/opt/homebrew/bin/python$v"
            return
        fi
        # Path lookup
        if command -v "python$v" &>/dev/null; then
            echo "$(command -v "python$v")"
            return
        fi
    done
    
    # 3. Fallback to generic python3 (but warn/check version later if needed)
    if command -v python3 &>/dev/null; then
        echo "$(command -v python3)"
        return
    fi
    
    return 1
}

# ── Main ────────────────────────────────────────────────────────────────────

print_banner

# Step 1: Preflight
echo -e "${BOLD}[1/8] Preflight checks...${NC}"

if [ ! -f "$OPENCLAW_CONFIG" ]; then
    echo -e "${RED}✗ OpenClaw config not found at $OPENCLAW_CONFIG${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} OpenClaw config found"

# Check gcloud
if ! command -v gcloud &>/dev/null; then
    # Try finding it in common paths
    POSSIBLE_PATHS=(
        "$HOME/google-cloud-sdk/bin/gcloud"
        "$HOME/.gemini/antigravity/scratch/google-cloud-sdk/bin/gcloud"
        "/usr/local/bin/gcloud"
        "/opt/homebrew/bin/gcloud"
    )
    FOUND_GCLOUD=0
    for p in "${POSSIBLE_PATHS[@]}"; do
        if [ -x "$p" ]; then
            alias gcloud="$p"
            export PATH="$(dirname "$p"):$PATH"
            FOUND_GCLOUD=1
            break
        fi
    done
    if [ $FOUND_GCLOUD -eq 0 ]; then
        echo -e "${RED}✗ Google Cloud SDK (gcloud) is not found.${NC}"
        echo "  Please install it first: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
fi
echo -e "  ${GREEN}✓${NC} gcloud CLI available"

# Check Python
PYTHON_EXEC=$(find_python || true)

if [ -z "$PYTHON_EXEC" ]; then
    echo -e "${RED}✗ Compatible Python 3 (3.11-3.13) not found.${NC}"
    exit 1
fi

PYTHON_VERSION=$($PYTHON_EXEC --version 2>&1 | awk '{print $2}')
echo -e "  ${GREEN}✓${NC} Using Python: $PYTHON_EXEC ($PYTHON_VERSION)"

# Warn on 3.14 (bleeding edge)
if [[ "$PYTHON_VERSION" == 3.14* ]]; then
    echo -e "${YELLOW}⚠ Warning: Python 3.14 detected. This may cause issues with uvloop.${NC}"
    echo "  Proceeding, but will force 'asyncio' loop in configuration."
fi

# Step 2: Auth
echo ""
echo -e "${BOLD}[2/8] Google Cloud Authentication...${NC}"
if ! gcloud auth print-access-token &>/dev/null; then
    echo -e "${YELLOW}⚠ Not logged in.${NC}"
    gcloud auth login
    gcloud auth application-default login --no-launch-browser
else
    echo -e "  ${GREEN}✓${NC} Authenticated"
    # Ensure ADC matches
    if [ ! -f "$HOME/.config/gcloud/application_default_credentials.json" ]; then
         echo "  Runnning ADC login..."
         gcloud auth application-default login --no-launch-browser
    fi
fi

# Step 3: Project Selection
echo ""
echo -e "${BOLD}[3/8] Project Selection...${NC}"
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
if [ -n "$CURRENT_PROJECT" ]; then
    echo -e "  Active Project: ${CYAN}$CURRENT_PROJECT${NC}"
    read -p "  Use this project? (Y/n): " confirm
    [[ "$confirm" =~ ^[Nn] ]] && CURRENT_PROJECT=""
fi

if [ -z "$CURRENT_PROJECT" ]; then
    echo "  Fetching projects..."
    PROJECTS=$(gcloud projects list --format="value(projectId)" 2>/dev/null)
    if [ -z "$PROJECTS" ]; then
        echo -e "${RED}✗ No projects found.${NC}"; exit 1
    fi
    
    echo "  Available Projects:"
    select p in $PROJECTS; do
        if [ -n "$p" ]; then CURRENT_PROJECT="$p"; break; fi
    done
    
    gcloud config set project "$CURRENT_PROJECT"
fi
echo -e "  ${GREEN}✓${NC} Using Project: ${CYAN}$CURRENT_PROJECT${NC}"

echo "  Enabling Vertex AI API..."
gcloud services enable aiplatform.googleapis.com &>/dev/null || true

# Step 4: Install Bridge
echo ""
echo -e "${BOLD}[4/8] Installing LiteLLM Bridge...${NC}"
mkdir -p "$PROXY_DIR"

# Always clean venv to ensure correct python version
rm -rf "$PROXY_DIR/venv"
echo "  Creating virtual environment ($PYTHON_EXEC)..."
"$PYTHON_EXEC" -m venv "$PROXY_DIR/venv"

echo "  Installing packages..."
"$PROXY_DIR/venv/bin/pip" install -q "litellm[proxy]" uvicorn

cp "$SCRIPT_DIR/config/litellm_config.yaml" "$PROXY_DIR/config.yaml"
echo -e "  ${GREEN}✓${NC} Installed in $PROXY_DIR"

# Step 5: Background Service
echo ""
echo -e "${BOLD}[5/8] Configuring Service...${NC}"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PROXY_DIR/venv/bin/litellm</string>
        <string>--config</string>
        <string>$PROXY_DIR/config.yaml</string>
        <string>--port</string>
        <string>18790</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$PROXY_DIR/proxy.log</string>
    <key>StandardErrorPath</key>
    <string>$PROXY_DIR/proxy.err</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>GOOGLE_CLOUD_PROJECT</key>
        <string>$CURRENT_PROJECT</string>
        <key>UVICORN_LOOP</key>
        <string>asyncio</string>
    </dict>
</dict>
</plist>
EOF

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"
echo -e "  ${GREEN}✓${NC} Bridge running at http://127.0.0.1:18790"

# Step 6: Model Selection
echo ""
echo -e "${BOLD}[6/8] Select Model${NC}"
MODELS_JSON="$SCRIPT_DIR/config/models.json"
if [ -f "$MODELS_JSON" ]; then
    # Simple python parser for menu
    python3 -c "
import json
with open('$MODELS_JSON') as f:
    for i, m in enumerate(json.load(f), 1):
        print(f\"{i}) {m['id']} | {m['name']}\")
"
    echo "Enter number (default 1):"
    read -r m_idx
    m_idx="${m_idx:-1}"
    # Extract ID using python
    SELECTED_MODEL=$(python3 -c "
import json
try:
    with open('$MODELS_JSON') as f:
        print(json.load(f)[int('$m_idx')-1]['id'])
except:
    print('gemini-3.0-preview-pro')
")
else
    SELECTED_MODEL="gemini-3.0-preview-pro"
fi
echo -e "  ${GREEN}✓${NC} Selected: $SELECTED_MODEL"

# Step 7: Backup
echo ""
echo -e "${BOLD}[7/8] Backing up config...${NC}"
cp "$OPENCLAW_CONFIG" "$OPENCLAW_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"

# Step 8: Patch Config
echo ""
echo -e "${BOLD}[8/8] Updating OpenClaw...${NC}"

export V_CFG="$OPENCLAW_CONFIG"
export V_TPL="$SCRIPT_DIR/config/vertex-provider.json"
export V_MOD="$SCRIPT_DIR/config/models.json"
export V_SEL="$SELECTED_MODEL"

python3 << 'EOF'
import json, os

cfg_path = os.environ["V_CFG"]
tpl_path = os.environ["V_TPL"]
mod_path = os.environ["V_MOD"]
sel_model = os.environ["V_SEL"]

with open(cfg_path) as f: config = json.load(f)
with open(tpl_path) as f: template = json.load(f)
with open(mod_path) as f: models = json.load(f)

# 1. Prepare Provider Config
provider = template['google-vertex']
# Verify API type (should be openai-completions)
if provider.get('api') != 'openai-completions':
    provider['api'] = 'openai-completions'

# 2. Prepare Models (Sanitize)
clean_models = []
valid_inputs = {'text', 'image'} # OpenClaw supported inputs
for m in models:
    clean = {
        'id': m['id'],
        'name': m['name'],
        'reasoning': m.get('reasoning', False),
        'contextWindow': m.get('contextWindow', 8192),
        'maxTokens': m.get('maxTokens', 4096)
    }
    # Filter inputs
    if 'input' in m:
        clean['input'] = [i for i in m['input'] if i in valid_inputs]
    clean_models.append(clean)

provider['models'] = clean_models
config.setdefault('models', {}).setdefault('providers', {})['google-vertex'] = provider

# 3. Set Default
config.setdefault('agents', {}).setdefault('defaults', {}).setdefault('model', {})['primary'] = f"google-vertex/{sel_model}"

with open(cfg_path, 'w') as f:
    json.dump(config, f, indent=2)
EOF

echo -e "  ${GREEN}✓${NC} Configuration applied"

# Restart
echo ""
echo "Restarting Gateway..."
if [[ "$(uname)" == "Darwin" ]]; then
    launchctl kickstart -k "gui/$(id -u)/ai.openclaw.gateway" 2>/dev/null || true
fi

echo -e "${GREEN}✅ Done! OpenClaw is ready.${NC}"
