# 🦞 OpenClaw Vertex AI Module

> Add **Google Vertex AI** (Gemini 1.5 Pro, Flash, etc.) support to [OpenClaw](https://openclaw.ai).

Created by **ROOH** — [rooh.red](https://rooh.red)

## ⚡ Quick Start

```bash
git clone https://github.com/roohcode/openclaw-vertex-module.git
cd openclaw-vertex-module
chmod +x install.sh
./install.sh
```

## How It Works (The Bridge) 🌉

OpenClaw does not support Vertex AI natively. This module solves that by installing a lightweight, local bridge (**LiteLLM**) that translates OpenClaw's requests into Vertex AI calls automatically.

The installer will:
1.  **Verify Google Cloud**: Checks configuration and enables ADC (Application Default Credentials).
2.  **Install Bridge**: Sets up a Python virtual environment in `~/.openclaw/vertex-proxy` and installs `litellm`.
3.  **Start Background Service**: Creates a macOS LaunchAgent (`com.rooh.vertex-proxy`) to keep the bridge running on port `18790`.
4.  **Configure OpenClaw**: Connects OpenClaw to the local bridge using the `openai` protocol.

## Supported Models

The installer features an **Interactive Selection Menu**.

-   **Gemini 3.0 Preview Pro** (`gemini-3.0-preview-pro`) — **Default**
-   **Gemini 2.0 Flash (Exp)** (`gemini-2.0-flash-exp`)
-   **Gemini 1.5 Pro** (`gemini-1.5-pro-001`)
-   **Gemini 1.5 Flash** (`gemini-1.5-flash-001`)
-   **Gemini 1.0 Pro** (`gemini-1.0-pro`)
-   **Custom ID**: Enter any valid Vertex AI model ID.

## Requirements

-   **OpenClaw** installed.
-   **Google Cloud SDK (`gcloud`)**.
-   **Python 3** (for the bridge).

## Uninstall

To remove the bridge, stop the service, and clean up config:

```bash
./uninstall.sh
```
