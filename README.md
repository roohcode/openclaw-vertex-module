# 🦞 OpenClaw Vertex AI Module

> Add **Google Vertex AI** (Gemini 1.5 Pro, Flash, etc.) support to [OpenClaw](https://openclaw.ai).

Created by **ROOH** — [rooh.red](https://rooh.red)

## ⚡ Quick Start

**One-Line Install:**
Run this command in your terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/roohcode/openclaw-vertex-module/main/install.sh)"
```

**Or Manual Install:**
1.  Clone this repository:
    ```bash
    git clone https://github.com/roohcode/openclaw-vertex-module.git
    cd openclaw-vertex-module
    ```
2.  Run the installer:
    ```bash
    ./install.sh
    ```

    Follow the interactive prompts to:
    - Authenticate with Google Cloud.
    - Set up the local LiteLLM bridge (Port `18790`).
    - Configure OpenClaw to use the bridge.

## 📋 Requirements

*   **OpenClaw** installed (`~/.openclaw/openclaw.json` must exist).
*   **Google Cloud SDK** (`gcloud`) installed and authorized.
*   **Python 3.11+** (3.13 recommended).
*   A Google Cloud Project with **Vertex AI API** enabled.

## 🛠️ Troubleshooting

**"Connection Refused" / Proxy not starting:**
- Check logs: `tail -f ~/.openclaw/vertex-proxy/proxy.err`
- If you see `uvloop` errors (Python 3.14), the installer automatically applies a fix. Try running `./uninstall.sh` and reinstalling.

**"Invalid Input" errors:**
- The installer automatically sanitizes the configuration for OpenClaw. Ensure you are using the latest version of this module.

## 🗑️ Uninstall

To remove the bridge, stop the service, and clean up config:

```bash
./uninstall.sh
```
