# H3 Reference Director 01 v2 — custom nodes

This repository contains the custom node pack and installer for **H3 Reference Director 01 v2**. The workflow JSON is distributed separately.

## Installation

For a Linux system where ComfyUI is at `/work/ComfyUI` and its Python is `/work/ai/venv/bin/python`, run this in a **bash** terminal:

```bash
git clone https://github.com/DemyanSkov/H3-Director-MAX.git /work/H3-Director-MAX && H3_COMFY_ROOT=/work/ComfyUI H3_PYTHON=/work/ai/venv/bin/python bash /work/H3-Director-MAX/install.sh
```

`git clone` only downloads the repository; the `bash` portion runs the installer. If your system uses different paths, change `H3_COMFY_ROOT` and `H3_PYTHON` to the actual ComfyUI directory and Python executable. Restart ComfyUI after installation, then load your separately supplied `H3_Reference_Director_01_v2.0.json` in its UI.

The installer installs/checks the custom nodes and dependencies, but **does not download the main model weights**. Use the included model list and model download instructions for those files. It needs internet access for upstream dependencies.

## What's included

- `ComfyUI-H3-ExactMasterMemory_v0.10.1.zip`: the custom node pack used by the installer. **Keep this ZIP beside the bundled installer**; the script verifies its SHA-256 before installation.
- `custom_nodes/ComfyUI-H3-ExactMasterMemory/`: inspectable source extracted from that same ZIP. The installer uses the verified ZIP, not this copy.
- Installation script, model list, and model download instructions. The workflow JSON is not included.

**No third-party node source is hosted in this repository.** To make the workflow usable, the installer downloads its other required and optional node packs directly from their upstream GitHub repositories at pinned commits. It does not download those packs from this repository. SageAttention is a Python/CUDA dependency, not a ComfyUI node; the installer builds/tests it when needed.

The exact upstream sources, commit IDs, and installation checks are in the bundled installer script.
