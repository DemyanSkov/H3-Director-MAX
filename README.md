# H3 Reference Director 01 v2 — RunPod bundle

This repository contains the original **H3 Reference Director 01 v2** workflow distribution and its RunPod installer. It is for `H3_Reference_Director_01_v2.0.json`, not a separate Director MAX workflow.

## Install on RunPod

Run each line separately in a **bash** terminal. For a pod where ComfyUI is at `/work/ComfyUI` and its Python is `/work/ai/venv/bin/python`:

```bash
cd /work
git clone https://github.com/DemyanSkov/H3-Director-MAX.git
cd /work/H3-Director-MAX/H3_REFERENCE_DIRECTOR_01_V2_RUNPOD_DISTRIBUTION
H3_COMFY_ROOT=/work/ComfyUI H3_PYTHON=/work/ai/venv/bin/python bash INSTALL_H3_REFERENCE_DIRECTOR_V2_RUNPOD.sh
```

If your pod uses different paths, change `H3_COMFY_ROOT` and `H3_PYTHON` to the actual ComfyUI directory and Python executable. Restart ComfyUI after installation, then load `H3_Reference_Director_01_v2.0.json` in its UI.

The installer installs/checks the custom nodes and dependencies, but **does not download the main model weights**. Use `H3_Reference_Director_01_v2.0_MODELS.pdf` and `MODEL_DOWNLOAD_COMMANDS_RUNPOD.txt` for those files. It needs internet access to download third-party nodes and dependencies.

## What's included

- `H3_REFERENCE_DIRECTOR_01_V2_RUNPOD_DISTRIBUTION.zip`: unchanged original distribution, also available as unpacked files in the directory of the same name.
- `H3_REFERENCE_DIRECTOR_01_V2_RUNPOD_DISTRIBUTION/ComfyUI-H3-ExactMasterMemory_v0.10.1.zip`: the custom node pack used by the installer. **Keep this ZIP beside the installer**; the script verifies its SHA-256 before installation.
- `custom_nodes/ComfyUI-H3-ExactMasterMemory/`: inspectable source extracted from that same ZIP. The installer uses the verified ZIP, not this copy.
- Workflow JSON, RunPod installer, model list, and model download instructions.

The installer fetches the other required node packs at pinned commits:

| Pack | Upstream source | Role |
| --- | --- | --- |
| ComfyUI-H3-Multishot | [jlucasmcrell/ComfyUI-H3-Multishot](https://github.com/jlucasmcrell/ComfyUI-H3-Multishot) | Required |
| ComfyUI-KJNodes | [kijai/ComfyUI-KJNodes](https://github.com/kijai/ComfyUI-KJNodes) | Required |
| ComfyUI-MiniMaxH3-FirstBlockCache | [duckyshell/ComfyUI-MiniMaxH3-FirstBlockCache](https://github.com/duckyshell/ComfyUI-MiniMaxH3-FirstBlockCache) | Required |
| ComfyUI-MAINodes | [matlowai/ComfyUI-MAINodes](https://github.com/matlowai/ComfyUI-MAINodes) | Optional motion refine |
| ComfyUI_Minimax_h3_latent_Upscaler | [LBH-123-AI/ComfyUI_Minimax_h3_latent_Upscaler](https://github.com/LBH-123-AI/ComfyUI_Minimax_h3_latent_Upscaler) | Optional latent upscale |
| ComfyUI-H3-FaceRefine | [Carasibana/ComfyUI-H3-FaceRefine](https://github.com/Carasibana/ComfyUI-H3-FaceRefine) | Optional face refine |

The exact commit IDs and installation checks are in `INSTALL_H3_REFERENCE_DIRECTOR_V2_RUNPOD.sh`. SageAttention is a Python/CUDA dependency, not a ComfyUI node; the installer builds/tests it when needed.

## Integrity

Original distribution ZIP SHA-256: `0db74fcd5bcc818673be340fb7b82474d2fd410421be62b20b4312ca62945ec4`

Bundled ExactMasterMemory ZIP SHA-256: `7d0aefa3539f16907b11074399dc27355090cf6c60a9336cd2d1729e79555905`

The files here were packaged for Linux/RunPod. Review the install script and model download instructions before running them in your environment.
