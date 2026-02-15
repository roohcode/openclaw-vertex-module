#!/usr/bin/env bash
# ============================================================================
# OpenClaw Vertex AI Module — One-Click Installer
# Adds Google Vertex AI support to OpenClaw
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
echo -e "${BOLD}[1/7] Preflight checks...${NC}"

if [ ! -f "$OPENCLAW_CONFIG" ]; then
    echo -e "${RED}✗ OpenClaw config not found at $OPENCLAW_CONFIG${NC}"
    echo "  Please install OpenClaw first: https://openclaw.ai"
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

# Check valid JSON
export _VERTEX_CONFIG_PATH="$OPENCLAW_CONFIG"
if ! python3 -c "import json,os; json.load(open(os.environ['_VERTEX_CONFIG_PATH']))" 2>/dev/null; then
    echo -e "${RED}✗ openclaw.json contains invalid JSON. Please fix it first.${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Config JSON is valid"

# ── Google Cloud Authentication ─────────────────────────────────────────────
echo ""
echo -e "${BOLD}[2/7] Checking Google Cloud Authentication...${NC}"

if ! gcloud auth print-access-token &>/dev/null; then
    echo -e "${YELLOW}⚠ You are not logged in to Google Cloud.${NC}"
    echo "  Launching login flow..."
    gcloud auth login
else
    CURRENT_USER=$(gcloud config get-value account 2>/dev/null)
    echo -e "  ${GREEN}✓${NC} Logged in as: ${CYAN}$CURRENT_USER${NC}"
fi

# ── Select Project ──────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[3/7] Configuring Google Cloud Project...${NC}"

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
        echo -e "${RED}✗ No projects found. Please create a Google Cloud project first.${NC}"
        echo "  https://console.cloud.google.com/projectcreate"
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

PROJECT_ID="$CURRENT_PROJECT"
echo -e "  ${GREEN}✓${NC} Using Project ID: ${CYAN}$PROJECT_ID${NC}"

# ── Enable Vertex AI API ────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[4/7] Verifying Vertex AI API...${NC}"

echo "  Enabling aiplatform.googleapis.com (this may take a moment)..."
if gcloud services enable aiplatform.googleapis.com; then
    echo -e "  ${GREEN}✓${NC} API Enabled"
else
    echo -e "${RED}✗ Failed to enable Vertex AI API.${NC}"
    echo "  Check your billing status: https://console.cloud.google.com/billing"
    exit 1
fi

# ── Select Model ────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[5/7] Select Default Model${NC}"
echo ""

MODELS_JSON="$SCRIPT_DIR/config/models.json"
DETECTED_MODELS=""

if [ -f "$MODELS_JSON" ]; then
    # Load models from JSON
    # Parse just the ID and Name for the menu
    MODEL_DATA=$(python3 -c "
import json
with open('$MODELS_JSON') as f:
    models = json.load(f)
    for m in models:
        print(f\"{m['id']}|{m['name']}\")
" 2>/dev/null)
else
    # Fallback if file missing
    MODEL_DATA="gemini-3.0-preview-pro|Gemini 3.0 Preview Pro
gemini-2.0-flash-exp|Gemini 2.0 Flash (Exp)
gemini-1.5-pro-001|Gemini 1.5 Pro
gemini-1.5-flash-001|Gemini 1.5 Flash"
fi

echo "   #  Model ID                       Name"
echo "  ─── ─────────────────────────────── ────────────────────────"

i=1
declare -a M_ID_LIST=()
declare -a M_NAME_LIST=()

while IFS='|' read -r m_id m_name; do
    M_ID_LIST+=("$m_id")
    M_NAME_LIST+=("$m_name")
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
    read -p "  Enter Model ID (e.g. gemini-1.5-pro): " SELECTED_MODEL
elif [ "$m_choice" -ge 1 ] && [ "$m_choice" -lt "$CUSTOM_OPTION" ]; then
    idx=$((m_choice - 1))
    SELECTED_MODEL="${M_ID_LIST[$idx]}"
else
    SELECTED_MODEL="${M_ID_LIST[0]}"
fi

echo -e "  ${GREEN}✓${NC} Selected: ${CYAN}$SELECTED_MODEL${NC}"


# ── Backup ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[6/7] Backing up config...${NC}"

BACKUP_FILE="$OPENCLAW_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
cp "$OPENCLAW_CONFIG" "$BACKUP_FILE"
echo -e "  ${GREEN}✓${NC} Backup saved to: $BACKUP_FILE"

# ── Patch Config ────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[7/7] Patching OpenClaw config...${NC}"

export _VERTEX_PROJECT_ID="$PROJECT_ID"
export _VERTEX_TEMPLATE_PATH="$SCRIPT_DIR/config/vertex-provider.json"
export _VERTEX_MODELS_PATH="$SCRIPT_DIR/config/models.json"
export _VERTEX_SELECTED_MODEL="$SELECTED_MODEL"

python3 << 'PYTHON_SCRIPT'
import json
import os

config_path = os.environ["_VERTEX_CONFIG_PATH"]
project_id = os.environ["_VERTEX_PROJECT_ID"]
template_path = os.environ["_VERTEX_TEMPLATE_PATH"]
selected_model_id = os.environ["_VERTEX_SELECTED_MODEL"]
models_path = os.environ["_VERTEX_MODELS_PATH"]

with open(config_path, 'r') as f:
    config = json.load(f)

# Ensure structure
if 'models' not in config: config['models'] = {}
if 'providers' not in config['models']: config['models']['providers'] = {}

# Load provider template
with open(template_path, 'r') as f:
    template = json.load(f)

provider_config = template['google-vertex']
provider_config['projectId'] = project_id

# Load models list to inject (ensure all models are available in the provider config, not just selected)
# The template already has them, but let's make sure the selected one is in the list if custom
with open(models_path, 'r') as f:
    all_models = json.load(f)

# If selected model is custom (not in file), we need to add it or trust the user
# Just checking if the ID exists in our list
known_ids = [m['id'] for m in all_models]
if selected_model_id not in known_ids:
    # Add a generic entry for the custom model
    all_models.insert(0, {
        "id": selected_model_id,
        "name": selected_model_id,
        "description": "Custom user-selected model",
        "reasoning": True,
        "input": ["text", "image"],
        "contextWindow": 1048576,
        "maxTokens": 8192
    })

# Update provider models list with our full list (including any custom one)
provider_config['models'] = all_models

# Inject
config['models']['providers']['google-vertex'] = provider_config

# Set default model
if 'agents' not in config: config['agents'] = {}
if 'defaults' not in config['agents']: config['agents']['defaults'] = {}
if 'model' not in config['agents']['defaults']: config['agents']['defaults']['model'] = {}

# Set primary model
config['agents']['defaults']['model']['primary'] = f"google-vertex/{selected_model_id}"

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')

print("  Config patched successfully")
PYTHON_SCRIPT

unset _VERTEX_PROJECT_ID _VERTEX_TEMPLATE_PATH _VERTEX_MODELS_PATH _VERTEX_CONFIG_PATH _VERTEX_SELECTED_MODEL

echo -e "  ${GREEN}✓${NC} Google Vertex AI provider added"
echo -e "  ${GREEN}✓${NC} Default model set to: ${CYAN}google-vertex/$SELECTED_MODEL${NC}"

# ── Restart Gateway ─────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Restarting OpenClaw gateway...${NC}"

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

echo -e "${GREEN}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║  ✅ Vertex AI module configuration complete!     ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
