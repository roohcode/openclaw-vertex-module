#!/usr/bin/env bash
# ============================================================================
# OpenClaw Vertex AI Module — One-Click Installer
# Adds Google Vertex AI support to OpenClaw via LiteLLM Bridge
#
# Created by ROOH (https://rooh.red)
# Usage:
#   ./install.sh
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
PROXY_DIR="$HOME/.openclaw/vertex-proxy"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Attempt to find gcloud if not in PATH
if ! command -v gcloud &>/dev/null; then
    POSSIBLE_PATHS=(
        "$HOME/google-cloud-sdk/bin/gcloud"
        "$HOME/.gemini/antigravity/scratch/google-cloud-sdk/bin/gcloud"
        "/usr/local/bin/gcloud"
        "/opt/homebrew/bin/gcloud"
    )
    for p in "${POSSIBLE_PATHS[@]}"; do
        if [ -f "$p" ] && [ -x "$p" ]; then
            alias gcloud="$p"
            export PATH="$(dirname "$p"):$PATH"
            break
        fi
    done
fi

# ── Banner ──────────────────────────────────────────────────────────────────
echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║   🦞 OpenClaw Vertex AI Module — Installer      ║"
echo "  ║     Created by ROOH — https://rooh.red          ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Preflight Checks ───────────────────────────────────────────────────────
echo -e "${BOLD}[1/8] Preflight checks...${NC}"

if [ ! -f "$OPENCLAW_CONFIG" ]; then
    echo -e "${RED}✗ OpenClaw config not found at $OPENCLAW_CONFIG${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} OpenClaw config found"

if ! command -v python3 &>/dev/null; then
    echo -e "${RED}✗ Python 3 is required but not found${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Python 3 available"

if ! command -v gcloud &>/dev/null; then
    echo -e "${RED}✗ Google Cloud SDK (gcloud) is not found.${NC}"
    echo "  Please install it first: https://cloud.google.com/sdk/docs/install"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} gcloud CLI available"

# ── Google Cloud Authentication ─────────────────────────────────────────────
echo ""
echo -e "${BOLD}[2/8] Checking Google Cloud Authentication...${NC}"

if ! gcloud auth print-access-token &>/dev/null; then
    echo -e "${YELLOW}⚠ You are not logged in to Google Cloud.${NC}"
    echo "  Launching login flow..."
    gcloud auth login
    # Login for ADC is crucial for LiteLLM
    echo "  Setting up Application Default Credentials (ADC)..."
    gcloud auth application-default login --no-launch-browser
else
    # Check if ADC is set up (usually implied, but let's be safe)
    if [ ! -f "$HOME/.config/gcloud/application_default_credentials.json" ]; then
         echo -e "${YELLOW}⚠ Application Default Credentials (ADC) needed for bridge.${NC}"
         gcloud auth application-default login --no-launch-browser
    fi
    CURRENT_USER=$(gcloud config get-value account 2>/dev/null)
    echo -e "  ${GREEN}✓${NC} Logged in as: ${CYAN}$CURRENT_USER${NC}"
fi

# ── Select Project ──────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[3/8] Configuring Google Cloud Project...${NC}"

CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)

if [ -n "$CURRENT_PROJECT" ]; then
    echo -e "  Current active project: ${CYAN}$CURRENT_PROJECT${NC}"
    read -p "  Use this project? (Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        CURRENT_PROJECT=""
    fi
fi

if [ -z "$CURRENT_PROJECT" ]; then
    echo "  Fetching available projects..."
    PROJECTS_LIST=$(gcloud projects list --format="value(projectId)" 2>/dev/null)
    
    if [ -z "$PROJECTS_LIST" ]; then
        echo -e "${RED}✗ No projects found.${NC}"
        exit 1
    fi

    echo ""
    echo "  Available Projects:"
    i=1
    declare -a P_LIST=()
    while IFS= read -r p_id; do
        P_LIST+=("$p_id")
        echo "   $i) $p_id"
        i=$((i + 1))
    done <<< "$PROJECTS_LIST"
    
    echo ""
    read -p "  Choose project (1-${#P_LIST[@]}): " choice
    if [ "$choice" -ge 1 ] && [ "$choice" -le "${#P_LIST[@]}" ] 2>/dev/null; then
        CURRENT_PROJECT="${P_LIST[$((choice - 1))]}"
    else
        echo -e "${RED}✗ Invalid selection.${NC}"
        exit 1
    fi

    echo "  Setting active project to $CURRENT_PROJECT..."
    gcloud config set project "$CURRENT_PROJECT"
fi
echo -e "  ${GREEN}✓${NC} Project: ${CYAN}$CURRENT_PROJECT${NC}"

# Enable API
echo "  Verifying API enablement..."
gcloud services enable aiplatform.googleapis.com &>/dev/null || true
echo -e "  ${GREEN}✓${NC} API ready"

# ── Install LiteLLM Bridge ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[4/8] Installing LiteLLM Bridge...${NC}"

mkdir -p "$PROXY_DIR"

if [ ! -d "$PROXY_DIR/venv" ]; then
    echo "  Creating virtual environment..."
    python3 -m venv "$PROXY_DIR/venv"
fi

echo "  Installing dependencies options (this may take a minute)..."
"$PROXY_DIR/venv/bin/pip" install -q "litellm[proxy]"

# Copy config
cp "$SCRIPT_DIR/config/litellm_config.yaml" "$PROXY_DIR/config.yaml"
echo -e "  ${GREEN}✓${NC} Bridge installed in $PROXY_DIR"

# ── Setup LaunchAgent ───────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[5/8] Configuring Background Service...${NC}"

PLIST_PATH="$HOME/Library/LaunchAgents/com.rooh.vertex-proxy.plist"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.rooh.vertex-proxy</string>
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
    </dict>
</dict>
</plist>
EOF

# Unload previous and load new
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"
echo -e "  ${GREEN}✓${NC} Bridge service started on port 18790"

# ── Select Model ────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[6/8] Select Default Model${NC}"
echo ""

MODELS_JSON="$SCRIPT_DIR/config/models.json"
# Use regex to default to the 3.0 model logic if json absent, otherwise load names
if [ -f "$MODELS_JSON" ]; then
    MODEL_DATA=$(python3 -c "
import json
with open('$MODELS_JSON') as f:
    models = json.load(f)
    for m in models:
        print(f\"{m['id']}|{m['name']}\")
" 2>/dev/null)
else
     # Fallback
     MODEL_DATA="gemini-3.0-preview-pro|Gemini 3.0 Preview Pro"
fi

i=1
declare -a M_ID_LIST=()
while IFS='|' read -r m_id m_name; do
    M_ID_LIST+=("$m_id")
    printf "   %d) %-35s %s\n" "$i" "$m_id" "$m_name"
    i=$((i + 1))
done <<< "$MODEL_DATA"

echo "   $i) Enter Custom Model ID..."
CUSTOM_OPTION=$i

echo ""
read -p "  Choose (1-$CUSTOM_OPTION) [1]: " m_choice
m_choice="${m_choice:-1}"
SELECTED_MODEL=""

if [ "$m_choice" -eq "$CUSTOM_OPTION" ]; then
    read -p "  Enter Model ID: " SELECTED_MODEL
elif [ "$m_choice" -ge 1 ] && [ "$m_choice" -lt "$CUSTOM_OPTION" ]; then
    idx=$((m_choice - 1))
    SELECTED_MODEL="${M_ID_LIST[$idx]}"
else
    SELECTED_MODEL="${M_ID_LIST[0]}"
fi
echo -e "  ${GREEN}✓${NC} Default: $SELECTED_MODEL"

# ── Backup ──────────────────────────────────────────────────────────────────
# ... (standard backup step) ...
echo ""
echo -e "${BOLD}[7/8] Backing up config...${NC}"
cp "$OPENCLAW_CONFIG" "$OPENCLAW_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"

# ── Patch Config ────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[8/8] Patching OpenClaw config...${NC}"

export _VERTEX_TEMPLATE_PATH="$SCRIPT_DIR/config/vertex-provider.json"
export _VERTEX_MODELS_PATH="$SCRIPT_DIR/config/models.json"
export _VERTEX_SELECTED_MODEL="$SELECTED_MODEL"
export _VERTEX_CONFIG_PATH="$OPENCLAW_CONFIG"

python3 << 'PYTHON_SCRIPT'
import json, os

config_path = os.environ["_VERTEX_CONFIG_PATH"]
template_path = os.environ["_VERTEX_TEMPLATE_PATH"]
selected_model = os.environ["_VERTEX_SELECTED_MODEL"]
models_path = os.environ["_VERTEX_MODELS_PATH"]

with open(config_path) as f: config = json.load(f)
with open(template_path) as f: template = json.load(f)
with open(models_path) as f: all_models = json.load(f)

# Inject provider
if 'models' not in config: config['models'] = {}
if 'providers' not in config['models']: config['models']['providers'] = {}

provider_cfg = template['google-vertex']
# Update models list if needed, or strictly rely on template if it's generic
# Ideally we sync template models with models.json list
provider_cfg['models'] = all_models 

config['models']['providers']['google-vertex'] = provider_cfg

# Set default
if 'agents' not in config: config['agents'] = {}
if 'defaults' not in config['agents']: config['agents']['defaults'] = {}
if 'model' not in config['agents']['defaults']: config['agents']['defaults']['model'] = {}
config['agents']['defaults']['model']['primary'] = f"google-vertex/{selected_model}"

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')
PYTHON_SCRIPT

echo -e "  ${GREEN}✓${NC} Config updated"

# ── Restart Gateway ─────────────────────────────────────────────────────────
echo ""
echo "Restarting OpenClaw..."
if [[ "$(uname)" == "Darwin" ]]; then
    launchctl kickstart -k "gui/$(id -u)/ai.openclaw.gateway" 2>/dev/null || true
fi

echo -e "${GREEN}✅ Installed! OpenClaw is now bridged to Vertex AI.${NC}"
