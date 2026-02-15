# 🦞 OpenClaw Vertex AI Module

> Add **Google Vertex AI** (Gemini 1.5 Pro, Gemini 1.5 Flash) support to [OpenClaw](https://openclaw.ai) with one command.

Created by **ROOH** — [rooh.red](https://rooh.red)

## ⚡ Quick Start

```bash
git clone https://github.com/roohcode/openclaw-vertex-module.git
cd openclaw-vertex-module
chmod +x install.sh
./install.sh
```

The installer will:
1.  Verify **Google Cloud SDK** (`gcloud`) installation.
2.  **Authenticate** you with Google Cloud (if needed).
3.  Help you select or configure your **Google Cloud Project**.
4.  **Enable** the Vertex AI API (`aiplatform.googleapis.com`).
5.  Patch your OpenClaw config to add the `google-vertex` provider.

---

## Requirements

-   **OpenClaw** installed and configured.
-   **Google Cloud SDK (`gcloud`)**.
    -   If you don't have it, the installer will warn you.
    -   [Install Guide](https://cloud.google.com/sdk/docs/install)
-   A Google Cloud Project with billing enabled.

## Models Included

This module configures the following models by default:

| Model ID | Name | Description |
|---|---|---|
| `gemini-3.0-preview-pro` | **Gemini 3.0 Preview Pro** | **Default.** User-requested preview model. |
| `gemini-2.0-flash-exp` | **Gemini 2.0 Flash (Exp)** | Next-gen Flash model. Extremely fast. |
| `gemini-1.5-pro-001` | **Gemini 1.5 Pro** | Stable, reasoning, long context (1M tokens). |
| `gemini-1.5-flash-001` | **Gemini 1.5 Flash** | Stable, efficient, long context (1M tokens). |
| `gemini-1.0-pro` | Gemini 1.0 Pro | Standard reliable model. |

During installation, you can **interactively verify and select** your preferred model, or enter a custom Model ID.

## Manual Installation

1.  Open `~/.openclaw/openclaw.json`.
2.  Add the provider config manually (see `config/vertex-provider.json`).
3.  Replace `__PROJECT_ID__` with your actual Google Cloud Project ID.
4.  Restart the OpenClaw gateway.

## Uninstall

To remove the Vertex AI provider and revert to your previous settings:

```bash
./uninstall.sh
```
