#!/usr/bin/env bash
# ======================================================================
#  H3 REFERENCE DIRECTOR - WORKFLOW 01 v2 - RUNPOD INSTALLER v2.1
#  Custom nodes + dependencies for RunPod (Linux). The main model files are downloaded by
#  hand; the only file this installer downloads is the 10 MB live-preview decoder taeh3.
#  RunPod edition of INSTALL_H3_REFERENCE_DIRECTOR_V2_CUSTOM_NODES_AND_DEPENDENCIES.bat
#
#  HOW TO RUN (RunPod web terminal, inside the folder that holds this file):
#    chmod +x INSTALL_H3_REFERENCE_DIRECTOR_V2_RUNPOD.sh
#    ./INSTALL_H3_REFERENCE_DIRECTOR_V2_RUNPOD.sh
# ======================================================================
#  OPTIONAL SETTINGS  -  1 = yes, 0 = no.
#  Edit them here before running, or put them in front of the command:
#    H3_UPGRADE_KJNODES_FOR_PREVIEW=1 ./INSTALL_H3_REFERENCE_DIRECTOR_V2_RUNPOD.sh
#  The installer asks NO questions. The only model file it downloads is taeh3 (10 MB).
# ======================================================================
#  Install KJNodes at the pinned commit with MiniMax H3 live-preview support. The workflow
#  ships with live preview ON. A KJNodes without it is replaced (the old copy is moved to
#  the snapshot folder). 0 = use the older validated commit, without live preview:
H3_UPGRADE_KJNODES_FOR_PREVIEW="${H3_UPGRADE_KJNODES_FOR_PREVIEW:-1}"
#  Download the live-preview decoder taeh3.safetensors when it is missing: about 10 MB,
#  Kijai/MiniMax-H3-TAE pinned to one commit, SHA-256 verified, into models/vae_approx:
H3_DOWNLOAD_PREVIEW_DECODER="${H3_DOWNLOAD_PREVIEW_DECODER:-1}"
#  Build SageAttention 2.2.0 on this pod when no matching build is cached
#  (about 3-15 minutes, once per GPU type; the build is kept on /workspace):
H3_BUILD_SAGEATTENTION="${H3_BUILD_SAGEATTENTION:-1}"
# ======================================================================

if [ -z "${BASH_VERSION:-}" ]; then
    echo "Run this installer with bash:  bash INSTALL_H3_REFERENCE_DIRECTOR_V2_RUNPOD.sh"
    exit 90
fi

set -u
set -o pipefail
umask 022

H3_SELF="$(readlink -f "${BASH_SOURCE[0]}")"
INSTALLER_DIR="$(dirname "$H3_SELF")"

if [ -t 1 ]; then
    C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
    C_GRAY=$'\033[90m'; C_WHITE=$'\033[1;37m'; C_OFF=$'\033[0m'
else
    C_CYAN=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_GRAY=''; C_WHITE=''; C_OFF=''
fi
RULE='======================================================================'

echo "$RULE"
echo "  H3 REFERENCE DIRECTOR - WORKFLOW 01 v2 - RUNPOD"
echo "  CUSTOM NODES + DEPENDENCIES INSTALLER  -  MAIN MODELS ARE DOWNLOADED BY HAND"
echo "$RULE"
echo
echo "Installs what Workflow 01 v2 needs to run, EXCEPT the main model files:"
echo "  1. Custom nodes, each pinned to an exact commit (KJNodes with H3 live preview)"
echo "  2. Our node pack ComfyUI-H3-ExactMasterMemory v0.10.1 (ZIP beside this file)"
echo "  3. Speed dependencies: SageAttention 2.2.0 for this GPU, tested on CUDA"
echo "  4. The live-preview decoder taeh3.safetensors (about 10 MB, SHA-256 verified)"
echo
echo "The MAIN MODEL FILES are downloaded by hand. See H3_Reference_Director_01_v2.0_MODELS.pdf"
echo "and MODEL_DOWNLOAD_COMMANDS_RUNPOD.txt. This installer CHECKS them and reports"
echo "complete, missing or damaged. It never moves, renames or deletes them."
echo
echo "SAFETY"
echo "  - Healthy existing installs are kept untouched."
echo "  - ComfyUI core, PyTorch, CUDA, Triton and NumPy are never upgraded or downgraded."
echo "  - Anything replaced is MOVED to a snapshot folder, never deleted."
echo "  - Conflicting or unvalidated items are skipped, not forced."
echo
echo "----------------------------------------------------------------------"
echo " NO QUESTIONS ARE ASKED. You can start this and walk away."
echo " ComfyUI may keep running; restart it at the end so it loads the nodes."
echo "----------------------------------------------------------------------"
echo
echo "Optional settings (edit the top of this file, or set them before the command):"
echo "  KJNodes with H3 live preview ................. $H3_UPGRADE_KJNODES_FOR_PREVIEW"
echo "  Download live-preview decoder taeh3 (10 MB) .. $H3_DOWNLOAD_PREVIEW_DECODER"
echo "  Build SageAttention when no build is cached .. $H3_BUILD_SAGEATTENTION"
echo "  (1 = yes, 0 = no)"
echo
if [ "${H3_NO_WAIT:-0}" != "1" ]; then
    echo "The installation starts in 10 seconds. Press Ctrl+C now to cancel."
    sleep 10
fi
echo
echo "Starting ..."

# ---------------------------------------------------------------------------------------------
# Pinned sources. Every third-party node pack is fetched by its FULL commit id.
# ---------------------------------------------------------------------------------------------
EXACT_ZIP_NAME='ComfyUI-H3-ExactMasterMemory_v0.10.1.zip'
EXACT_ZIP_SHA256='7d0aefa3539f16907b11074399dc27355090cf6c60a9336cd2d1729e79555905'
PIN_MULTISHOT='d7d197709fc93c1afb125e3db1dfd4ac0ae28c60'
PIN_LBH='40316cf008b2fd8663263270669eb4da23f89d2c'
PIN_KJ_VALIDATED='6ab7e8130e449ed2c0037589bcf84146ceb7fc9c'
PIN_KJ_PREVIEW='d3cfe21625e5170126ce06fbfcfe1d88108688c3'
PIN_FBC='725973c3bfd9de6dce249bc93dc5fe27f820df31'
PIN_FACEREFINE='d8521d14fe0d721d80cd9417fff5a559cbc21aba'
PIN_MAINODES='f4868b4a08e8a504ce86db54a17961d399ffa2bc'
# SageAttention: Linux has no prebuilt 2.x wheels, so it is built from the upstream tag v2.2.0.
PIN_SAGE='eb615cf6cf4d221338033340ee2de1c37fbdba4a'
SAGE_LINE='2.2.0'
# Live-preview decoder: Kijai/MiniMax-H3-TAE (Apache-2.0), pinned to repository commit a213ac8.
# The ONLY model file this installer downloads. It is installed only after size + SHA-256 match.
TAEH3_URL='https://huggingface.co/Kijai/MiniMax-H3-TAE/resolve/a213ac8bf2f148b4f32372279a7f207846978900/vae_approx/taeh3.safetensors'
TAEH3_SHA256='f0f60fa072089997f817402098c2fd90777cb2660dd79cf5df42fc1e3e08e527'
TAEH3_BYTES=9791388

SUMMARY=()
CHANGES=()
WARNINGS=()
REQUIRED_FAILED=0
STATE_ROOT=""
APT_UPDATED=0

TMP_ROOT="$(mktemp -d /tmp/H3_refdirector_v2_XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT

step(){ printf '\n%s==> %s%s\n' "$C_CYAN" "$1" "$C_OFF"; }
ok(){ printf '%s[OK] %s%s\n' "$C_GREEN" "$1" "$C_OFF"; }
info(){ printf '%s[INFO] %s%s\n' "$C_GRAY" "$1" "$C_OFF"; }
warn(){ printf '%s[WARN] %s%s\n' "$C_YELLOW" "$1" "$C_OFF"; WARNINGS+=("$1"); }
add_summary(){ SUMMARY+=("$1"); }
add_change(){ CHANGES+=("$1"); add_summary "CHANGE: $1"; }
save_summary(){
    if [ -n "$STATE_ROOT" ] && [ "${#SUMMARY[@]}" -gt 0 ]; then
        printf '%s\n' "${SUMMARY[@]}" > "$STATE_ROOT/INSTALL_SUMMARY.txt" 2>/dev/null || true
    fi
}
finish(){
    local rc="$1"
    echo
    if [ "$rc" = "0" ]; then
        echo "${C_GREEN}[SUCCESS] Custom nodes and dependencies passed the installer validation.${C_OFF}"
        echo "Read the model check above, then restart ComfyUI and load"
        echo "H3_Reference_Director_01_v2.0.json."
    elif [ "$rc" = "2" ]; then
        echo "${C_YELLOW}[INCOMPLETE] A required item needs attention. Read the WARN lines above.${C_OFF}"
        echo "It is safe to run this installer again: finished items are skipped."
    else
        echo "${C_RED}[ABORTED] The installer stopped safely. See the snapshot/log path printed above.${C_OFF}"
        echo "ComfyUI core, PyTorch and CUDA are never changed by this installer."
    fi
    echo
    exit "$rc"
}
fail(){
    printf '%s[ABORT] %s%s\n' "$C_RED" "$1" "$C_OFF"
    add_summary "ABORT: $1"
    save_summary
    if [ -n "$STATE_ROOT" ]; then printf '%s[INFO] Snapshot/log: %s%s\n' "$C_YELLOW" "$STATE_ROOT" "$C_OFF"; fi
    finish 1
}
norm_dist(){ printf '%s' "$1" | tr 'A-Z' 'a-z' | sed -E 's/[_.]+/-/g'; }
sha256_of(){ sha256sum "$1" | awk '{print $1}'; }
file_has(){ [ -f "$1" ] && grep -qF -- "$2" "$1"; }
tree_has(){ [ -d "$1" ] && grep -rqF --include='*.py' -- "$2" "$1"; }
apt_ok(){ [ "$(id -u)" = "0" ] && command -v apt-get >/dev/null 2>&1; }
apt_install(){
    local log="$STATE_ROOT/apt-get.txt"
    if [ "$APT_UPDATED" = "0" ]; then
        apt-get update >>"$log" 2>&1 && APT_UPDATED=1
    fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@" >>"$log" 2>&1
}
# version_ge A B : true when version A >= version B (numeric, dotted)
version_ge(){ [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

# Returns 0 on success. Never aborts by itself, so optional downloads can fail softly.
try_download(){
    local url="$1" dest="$2" max="${3:-900}"
    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --retry 5 --retry-delay 3 --connect-timeout 20 --max-time "$max" \
             --silent --show-error --output "$dest" "$url"
        return $?
    fi
    if command -v wget >/dev/null 2>&1; then
        timeout "$max" wget -q --tries=5 --timeout=20 -O "$dest" "$url"
        return $?
    fi
    return 1
}

# ---------------------------------------------------------------------------------------------
# Python helpers. They run with ComfyUI's own Python and use the standard library only.
# ---------------------------------------------------------------------------------------------
H_UNZIP="$TMP_ROOT/h3_unzip.py"
cat > "$H_UNZIP" <<'PY'
import os, sys, zipfile
z, dest = sys.argv[1], os.path.realpath(sys.argv[2])
os.makedirs(dest, exist_ok=True)
with zipfile.ZipFile(z) as zf:
    for m in zf.infolist():
        target = os.path.realpath(os.path.join(dest, m.filename))
        if not (target == dest or target.startswith(dest + os.sep)):
            raise SystemExit("unsafe path inside the archive: " + m.filename)
    zf.extractall(dest)
PY
safe_unzip(){ "$PYTHON" "$H_UNZIP" "$1" "$2"; }

H_PREFLIGHT="$TMP_ROOT/h3_preflight.py"
cat > "$H_PREFLIGHT" <<'PY'
import platform, shlex, struct, sys, sysconfig, importlib.metadata as md
def v(name):
    try: return md.version(name)
    except md.PackageNotFoundError: return None
gil = getattr(sys, "_is_gil_enabled", None)
info = {"python": platform.python_version(), "py_major": sys.version_info.major, "py_minor": sys.version_info.minor,
        "py_bits": struct.calcsize("P") * 8, "machine": platform.machine(), "pip": v("pip"), "triton": v("triton"),
        "sageattention": v("sageattention"), "numpy": v("numpy"), "torchvision": v("torchvision"),
        "torchaudio": v("torchaudio"), "free_threaded": 1 if (gil is not None and gil() is False) else 0,
        "include_path": sysconfig.get_paths().get("include", ""), "torch": None, "cuda": "None", "hip": "None",
        "cuda_available": 0, "gpu": "", "cc_major": "", "cc_minor": "", "vram_gb": "", "torch_error": ""}
try:
    import torch
    info.update({"torch": torch.__version__, "cuda": str(torch.version.cuda), "hip": str(getattr(torch.version, "hip", None)),
                 "cuda_available": 1 if torch.cuda.is_available() else 0})
    if torch.cuda.is_available():
        p = torch.cuda.get_device_properties(0)
        info.update({"gpu": torch.cuda.get_device_name(0), "cc_major": p.major, "cc_minor": p.minor,
                     "vram_gb": round(p.total_memory / 2**30, 2)})
except Exception as e:
    info["torch_error"] = repr(e)
for k, val in info.items():
    print("PF_%s=%s" % (k, shlex.quote("" if val is None else str(val))))
PY

H_POSTPROBE="$TMP_ROOT/h3_postprobe.py"
cat > "$H_POSTPROBE" <<'PY'
import shlex, importlib.metadata as md
def v(n):
    try: return md.version(n)
    except md.PackageNotFoundError: return None
import torch
for k, val in {"torch": torch.__version__, "cuda": str(torch.version.cuda), "numpy": v("numpy"),
               "torchvision": v("torchvision"), "torchaudio": v("torchaudio"), "triton": v("triton")}.items():
    print("PP_%s=%s" % (k, shlex.quote("" if val is None else str(val))))
PY

H_PIPGUARD="$TMP_ROOT/h3_pipguard.py"
cat > "$H_PIPGUARD" <<'PY'
import json, re, shlex, sys
report, protected_file = sys.argv[1], sys.argv[2]
prot = set(l.strip() for l in open(protected_file) if l.strip())
def norm(n): return re.sub(r"[_.]+", "-", n.lower())
names, pins = [], []
for it in json.load(open(report)).get("install", []):
    m = it.get("metadata") or {}
    n, ver = m.get("name"), m.get("version")
    if not n: continue
    names.append(norm(n)); pins.append("%s==%s" % (n, ver))
# The CUDA-bound packages PyTorch itself depends on are protected too: read from PyTorch's own
# metadata, plus a fixed pattern for NVIDIA's CUDA runtime wheels (nvidia-cudnn-cu12, nvidia-nccl-cu12 ...).
# Other nvidia-* packages, such as the NVML monitoring library nvidia-ml-py, are ordinary packages.
try:
    import importlib.metadata as md
    for r in (md.requires("torch") or []):
        m = re.match(r"^\s*([A-Za-z0-9_.-]+)", r)
        if m:
            n = norm(m.group(1))
            if n.startswith("nvidia-") or n.startswith("cuda-") or n == "triton": prot.add(n)
except Exception:
    pass
cuda_wheel = re.compile(r"^nvidia-(cuda|cudnn|cublas|cufft|curand|cusolver|cusparse|cusparselt|nccl|nvtx|nvjitlink|cufile|nvshmem|npp|nvjpeg)(-|$)")
hits = [n for n in names if n in prot or cuda_wheel.match(n)]
print("PIP_NAMES=" + shlex.quote(" ".join(names)))
print("PIP_PINS=" + shlex.quote(" ".join(pins)))
print("PIP_HITS=" + shlex.quote(" ".join(hits)))
PY

H_STCHECK="$TMP_ROOT/h3_stcheck.py"
cat > "$H_STCHECK" <<'PY'
# Exit 0 when the .safetensors file is complete: as long as its own header says.
import os, re, struct, sys
p = sys.argv[1]
with open(p, "rb") as f:
    ln = os.fstat(f.fileno()).st_size
    b = f.read(8)
    if len(b) != 8: sys.exit(1)
    n = struct.unpack("<Q", b)[0]
    if n < 2 or n > 104857600 or 8 + n > ln: sys.exit(1)
    h = f.read(n).decode("utf-8", "replace")
offs = [int(m.group(2)) for m in re.finditer(r'"data_offsets"\s*:\s*\[\s*(\d+)\s*,\s*(\d+)\s*\]', h)]
if not offs or ln < 8 + n + max(offs): sys.exit(1)
print("ST_OK")
PY

H_FACEPROBE="$TMP_ROOT/h3_faceprobe.py"
cat > "$H_FACEPROBE" <<'PY'
import importlib.util as u
for k in ("ultralytics", "scenedetect", "scipy"):
    print("FACE_%s=%s" % (k, 1 if u.find_spec(k) else 0))
PY

H_NVINC="$TMP_ROOT/h3_nvidia_includes.py"
cat > "$H_NVINC" <<'PY'
import glob, importlib.util, os
s = importlib.util.find_spec("nvidia")
out = set()
if s and s.submodule_search_locations:
    for root in s.submodule_search_locations:
        out.update(glob.glob(os.path.join(root, "*", "include")))
        out.update(glob.glob(os.path.join(root, "*", "*", "include")))
print("\n".join(sorted(out)))
PY

H_TRITON_TEST="$TMP_ROOT/h3_triton_test.py"
cat > "$H_TRITON_TEST" <<'PY'
import torch, triton, triton.language as tl
@triton.jit
def add_kernel(x,y,o,n:tl.constexpr,BLOCK:tl.constexpr):
    offs=tl.program_id(0)*BLOCK+tl.arange(0,BLOCK); m=offs<n
    tl.store(o+offs,tl.load(x+offs,mask=m)+tl.load(y+offs,mask=m),mask=m)
a=torch.rand(1024,device='cuda'); b=torch.rand(1024,device='cuda'); o=torch.empty_like(a)
add_kernel[(1,)](a,b,o,n=1024,BLOCK=1024); torch.cuda.synchronize()
err=(o-(a+b)).abs().max().item()
print('Triton',triton.__version__,'max_error',err)
if err>1e-5: raise SystemExit('Triton JIT numerical smoke test failed')
print('TRITON_JIT_OK')
PY

H_SAGE_TEST="$TMP_ROOT/h3_sage_test.py"
cat > "$H_SAGE_TEST" <<'PY'
import torch, importlib.metadata as md
from sageattention import sageattn
q=torch.randn(1,2,64,128,device='cuda',dtype=torch.float16)
k=torch.randn_like(q); v=torch.randn_like(q)
o=sageattn(q,k,v); torch.cuda.synchronize()
print('SageAttention',md.version('sageattention'),'shape',tuple(o.shape),'finite',bool(torch.isfinite(o).all()))
if tuple(o.shape)!=tuple(q.shape) or not bool(torch.isfinite(o).all()): raise SystemExit('SageAttention CUDA smoke test failed')
print('SAGE_CUDA_OK')
PY

# The three "MEM-EFF SAGE" nodes of the workflow (KJNodes' MiniMax H3 Mem-Eff Sage patch) call
# SageAttention's compiled CUDA kernels directly. This mirrors the way KJNodes looks them up.
H_MEMEFF_TEST="$TMP_ROOT/h3_memeff_test.py"
cat > "$H_MEMEFF_TEST" <<'PY'
import importlib
from sageattention.core import per_thread_int8_triton, per_warp_int8_cuda, per_block_int8_triton, per_channel_fp8, get_cuda_arch_versions, attn_false
arch = get_cuda_arch_versions()[0]
need = {"sm80": "sm80", "sm86": "sm80", "sm89": "sm89", "sm90": "sm90", "sm120": "sm89", "sm121": "sm89"}.get(arch)
probe = {"sm80": "qk_int8_sv_f16_accum_f32_attn",
         "sm89": "qk_int8_sv_f8_accum_f32_fuse_v_scale_attn_inst_buf",
         "sm90": "qk_int8_sv_f8_accum_f32_fuse_v_scale_attn_inst_buf"}
if need is None: raise SystemExit("GPU %s is not covered by the MiniMax H3 Mem-Eff Sage patch" % arch)
core = importlib.import_module("sageattention.core")
cands = [getattr(core, "_qattn_" + need, None), getattr(core, need + "_compile", None)]
try:
    mod = importlib.import_module("sageattention.%s_compile" % need)
    cands += [mod, getattr(mod, "_qattn_" + need, None)]
except Exception:
    pass
if not any(c is not None and hasattr(c, probe[need]) for c in cands):
    raise SystemExit("SageAttention has no compiled %s kernels for %s" % (need, arch))
print("MEMEFF_OK", arch, need)
PY

H_MODELCHECK="$TMP_ROOT/h3_modelcheck.py"
cat > "$H_MODELCHECK" <<'PY'
# Read-only model check. Downloads no model file and never moves or renames one.
# A model file only counts as installed when it is complete:
#   1. exact size, against the size Hugging Face reports for that file;
#   2. for .safetensors: the file is as long as its own header says (the check ComfyUI fails
#      with "Tensor ... extends past the end of the file").
# Without network access only check 2 and a minimum size apply.
import json, os, re, struct, sys, urllib.parse, urllib.request
models_dir, out_tsv, out_unfinished = sys.argv[1], sys.argv[2], sys.argv[3]
HF = "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main"
UP_NEW = "minimax_h3_latent_upscaler_3d_conv_v1_fp16.safetensors"
JK = "https://huggingface.co/JOKER141/MiniMax-H3-General-Motion-Continuity-Repair/resolve/main/"
JO = "https://huggingface.co/Jojocodex/minimax-h3-spatial-physics-lora/resolve/main/"
# L label, C folder under models, N file names (first = the name in the models PDF), U matching download
# links (used only to read the true size from Hugging Face), W fallback keyword sets, R required, M minimum bytes.
LIST = [
 dict(L="Base model: Singularity v1.3", C="diffusion_models", N=["Minimax-h3_Singularity_ref2va_Pruned_v1.3_int8.safetensors"], U=["https://huggingface.co/WarmBloodAban/Minimax-h3_Singularity/resolve/main/Minimax-h3_Singularity_ref2va_Pruned_v1.3_int8.safetensors"], W=[], R=True, M=18000000000),
 dict(L="Text encoder", C="text_encoders", N=["qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"], U=[HF + "/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"], W=[], R=True, M=14000000000),
 dict(L="Video VAE", C="vae", N=["minimax_h3_video_vae_fp16.safetensors"], U=[HF + "/vae/minimax_h3_video_vae_fp16.safetensors"], W=[], R=True, M=4500000000),
 dict(L="Audio VAE", C="vae", N=["minimax_h3_audio_vae_fp32.safetensors"], U=[HF + "/vae/minimax_h3_audio_vae_fp32.safetensors"], W=[], R=True, M=500000000),
 dict(L="Turbo 8-step LoRA", C="loras", N=["minimax_h3_ref2v_turbo_8step_v1.0_768p_comfyui_bf16.safetensors"], U=["https://huggingface.co/lightx2v/Minimax-h3-Turbo/resolve/main/minimax_h3_ref2v_turbo_8step_v1.0_768p_comfyui_bf16.safetensors"], W=[["ref2v", "turbo", "8step"]], R=False, M=1000000),
 dict(L="Turbo 4-step LoRA", C="loras", N=["minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors"], U=[HF + "/loras/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors"], W=[["ref2v", "turbo", "4step"]], R=False, M=1000000),
 dict(L="LoRA: fal Realism People", C="loras", N=["h3-realism-people-t2v-i2v-r2v.safetensors"], U=["https://huggingface.co/fal/MiniMax-H3-Realism-People-LoRA/resolve/main/h3-realism-people-t2v-i2v-r2v.safetensors"], W=[["realism", "people"]], R=False, M=1000000),
 dict(L="LoRA: Motion Continuity Repair", C="loras", N=["Motion_Repair_V2.safetensors", "Motion_Repair.safetensors"], U=[JK + "Motion_Repair_V2.safetensors", JK + "Motion_Repair.safetensors"], W=[["continuity"]], R=False, M=1000000),
 dict(L="LoRA: Spatial Physics", C="loras", N=["wushu_spatial_physics_clean_3000_pruned.safetensors", "wushu_spatial_physics_v2_1000_pruned.safetensors"], U=[JO + "wushu_spatial_physics_clean_3000_pruned.safetensors", JO + "wushu_spatial_physics_v2_1000_pruned.safetensors"], W=[["spatial", "physics"]], R=False, M=1000000),
 dict(L="LoRA: LMS Sharpness", C="loras", N=["minimax_h3_lms_v1.0_r64.safetensors"], U=["https://huggingface.co/Alissonerdx/Minimax-H3-ComfyUI/resolve/main/loras/minimax_h3_lms_v1.0_r64.safetensors"], W=[["minimax_h3_lms"]], R=False, M=1000000),
 dict(L="Latent upscaler model (Group 07)", C="latent_upscale_models", N=[UP_NEW, "minimax_h3_latent_upscaler_3d_fp16.safetensors"], U=["https://huggingface.co/LBH-123-AI/Minimax_h3_latent_Upscaler/resolve/main/minimax_h3_latent_upscaler_3d_conv_v1/" + UP_NEW, ""], W=[], R=False, M=100000000),
 dict(L="Face detector (Group 08)", C="ultralytics/bbox", N=["face_yolov8m.pt"], U=["https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov8m.pt"], W=[], R=False, M=10000000),
 dict(L="Live preview decoder", C="vae_approx", N=["taeh3.safetensors"], U=[""], W=[], R=False, M=1000000),
]
_cache = {}
def repo_index(repo):
    if repo in _cache: return _cache[repo]
    idx = None
    try:
        with urllib.request.urlopen("https://huggingface.co/api/models/%s?blobs=true" % repo, timeout=45) as r:
            j = json.load(r)
        idx = {}
        for sb in j.get("siblings", []):
            fn = sb.get("rfilename")
            if not fn: continue
            idx[fn] = int(sb.get("size") or (sb.get("lfs") or {}).get("size") or 0)
    except Exception:
        idx = None
    _cache[repo] = idx
    return idx
def remote_size(url):
    m = re.match(r"^https://huggingface\.co/([^/]+)/([^/]+)/resolve/[^/]+/([^?#]+)", url or "")
    if not m: return None
    idx = repo_index(m.group(1) + "/" + m.group(2))
    if idx is None: return None
    return idx.get(urllib.parse.unquote(m.group(3)))
def fmt(b): return ("%.2f GB" % (b / 2**30)) if b >= 2**30 else ("%.1f MB" % (b / 2**20))
def safetensors_why(path):
    try:
        with open(path, "rb") as fs:
            ln = os.fstat(fs.fileno()).st_size
            if ln < 16: return "the file is far too small to be a model"
            b = fs.read(8)
            if len(b) != 8: return "the file header could not be read"
            n = struct.unpack("<Q", b)[0]
            if n < 2 or n > 104857600 or 8 + n > ln: return "the file header is damaged or the file is cut short"
            h = fs.read(n)
            if len(h) < n: return "the file header is cut short"
        mx, count = 0, 0
        for m in re.finditer(r'"data_offsets"\s*:\s*\[\s*(\d+)\s*,\s*(\d+)\s*\]', h.decode("utf-8", "replace")):
            mx = max(mx, int(m.group(2))); count += 1
        if count == 0: return "the file header lists no tensors"
        need = 8 + n + mx
        if ln < need: return "the file is cut short: %s of %s (%.1f%%)" % (fmt(ln), fmt(need), 100.0 * ln / need)
        return None
    except Exception as e:
        return "the file could not be read (%s)" % e
def test_file(path, name, rsize, minb):
    ln = os.path.getsize(path)
    if rsize:
        if ln != rsize: return "it is %s (%s bytes) but the file on Hugging Face is %s (%s bytes)" % (fmt(ln), format(ln, ","), fmt(rsize), format(rsize, ","))
    elif ln < minb:
        return "it is only %s" % fmt(ln)
    if name.lower().endswith(".safetensors"):
        return safetensors_why(path)
    return None
def files_under(d):
    out = []
    for root, dirs, files in os.walk(d):
        for f in files: out.append(os.path.join(root, f))
    return sorted(out)
def find(category, names, wordsets):
    d = os.path.join(models_dir, category)
    if not os.path.isdir(d): return None
    allf = files_under(d)
    for n in names:
        for p in allf:
            if os.path.basename(p) == n: return p
    for n in names:
        for p in allf:
            if os.path.basename(p).lower() == n.lower(): return p
    for ws in wordsets:
        for p in allf:
            b = os.path.basename(p).lower()
            if b.endswith(".safetensors") and all(w in b for w in ws): return p
    return None
rows = []
for e in LIST:
    f = find(e["C"], e["N"], e["W"])
    req = "1" if e["R"] else "0"
    if not f:
        rows.append([e["L"], "MISSING", e["C"], e["N"][0], "", req]); continue
    name = os.path.basename(f); rs = None
    for i, n in enumerate(e["N"]):
        if name.lower() == n.lower() and i < len(e["U"]) and e["U"][i]:
            rs = remote_size(e["U"][i])
    why = test_file(f, name, rs, e["M"])
    rel = os.path.relpath(f, os.path.join(models_dir, e["C"]))
    if why:
        rows.append([e["L"], "DAMAGED", e["C"], rel, why, req])
    else:
        d = fmt(os.path.getsize(f))
        if not rs: d += "; structure checked, size not compared with Hugging Face"
        rows.append([e["L"], "OK", e["C"], rel, d, req])
SEP = "\x1f"   # unit separator: unlike a tab, bash keeps empty fields between two of them
with open(out_tsv, "w") as fo:
    for r in rows: fo.write(SEP.join(x.replace(SEP, " ").replace("\n", " ") for x in r) + "\n")
unfinished = []
for sub in ("diffusion_models", "text_encoders", "vae", "loras", "latent_upscale_models", "vae_approx", "model_patches", "checkpoints", "ultralytics"):
    d = os.path.join(models_dir, sub)
    if os.path.isdir(d):
        for p in files_under(d):
            if p.endswith(".part") or p.endswith(".part.aria2") or p.endswith(".aria2"):
                unfinished.append("%s%s%s" % (p, SEP, fmt(os.path.getsize(p))))
with open(out_unfinished, "w") as fo:
    fo.write("\n".join(unfinished) + ("\n" if unfinished else ""))
PY

# Runs one of the helper scripts with a time limit. Output goes to <log>; stdout is kept in PY_OUT.
PY_OUT=""
run_py(){
    local script="$1" secs="$2" log="$3"; shift 3
    local rc
    timeout "$secs" "$PYTHON" "$script" "$@" > "$log.out" 2> "$log.err"
    rc=$?
    if [ "$rc" = "124" ]; then echo "TIMEOUT after $secs seconds" >> "$log.err"; fi
    cat "$log.out" "$log.err" > "$log" 2>/dev/null
    PY_OUT="$(cat "$log.out" 2>/dev/null)"
    rm -f "$log.out" "$log.err"
    return "$rc"
}
# run_check <script> <seconds> <logname> <marker> : true when the script exits 0 and prints the marker.
run_check(){
    run_py "$1" "$2" "$STATE_ROOT/$3.txt"
    local rc=$?
    [ "$rc" = "0" ] && printf '%s' "$PY_OUT" | grep -qF -- "$4"
}

# ---- structural health tests (one per node pack) ---------------------------------------------
test_multishot(){ [ -f "$1/__init__.py" ] && file_has "$1/h3_advanced.py" H3ConditionStrength && file_has "$1/h3_advanced.py" H3FreeTextEncoder; }
test_exact(){
    local r="$1" k
    file_has "$r/__init__.py" '0.10.1' || return 1
    for k in H3RDLoraStack H3RDCompareVideo H3RDMotionGate H3RDLoadVideo H3RDFaceAudioLock H3RDHQPass2Conditioning; do
        file_has "$r/v2_nodes.py" "$k" || return 1
    done
    file_has "$r/semantic_ref.py" H3_HQ_REFPACK && file_has "$r/semantic_ref.py" H3SourceEditAudioPriority &&
    file_has "$r/ui_utils.py" H3TrimAVToFrames && file_has "$r/ui_utils.py" LazyAudioMap &&
    [ -f "$r/nodes.py" ] && [ -f "$r/timeline.py" ] && [ -f "$r/keyframes_stable.py" ]
}
test_lbh(){ local a="$1/nodes/minimax_h3_latent_upscaler_3d.py"; file_has "$a" MinimaxH3LatentUpscaler3D && file_has "$a" force_unload; }
test_kj_required(){ file_has "$1/nodes/ltxv_nodes.py" MiniMaxH3MemoryEfficientSageAttentionPatch && file_has "$1/nodes/model_optimization_nodes.py" PathchSageAttentionKJ; }
test_kj_preview(){ local p="$1/nodes/preview_override_node.py"; file_has "$p" ModelPreviewOverrideKJ && file_has "$p" MiniMaxH3; }
test_kj_both(){ test_kj_required "$1" && test_kj_preview "$1"; }
test_fbc(){ tree_has "$1" ApplyMiniMaxH3FirstBlockCache; }
test_mainodes(){
    local k; [ -f "$1/__init__.py" ] || return 1
    for k in H3JerkOracle H3TimeSmear H3ExactRecover H3V2VInit H3InjectSchedule; do file_has "$1/motion.py" "$k" || return 1; done
}
test_facerefine(){
    local k; [ -f "$1/__init__.py" ] || return 1
    for k in H3FaceTrackCrop H3PerFrameDenoise H3InjectVideoLatent H3FaceStitch; do file_has "$1/nodes.py" "$k" || return 1; done
}

# Node folders in custom_nodes that match a pattern (case-insensitive, like Windows), minus disabled/backup copies.
get_node_folders(){
    local pat="$1" f b
    shopt -s nocaseglob nullglob
    for f in "$CUSTOM_NODES"/$pat; do
        [ -d "$f" ] || continue
        b="$(basename "$f")"
        case "${b,,}" in *.disabled|*.bak) continue ;; esac
        printf '%s\n' "$f"
    done
    shopt -u nocaseglob nullglob
}
move_out_of_custom_nodes(){
    local path="$1" qroot base dst i=1
    qroot="$STATE_ROOT/moved_out_of_custom_nodes"
    mkdir -p "$qroot"
    base="$(basename "$path")"; dst="$qroot/$base"
    while [ -e "$dst" ]; do dst="$qroot/${base}_$i"; i=$((i+1)); done
    mv "$path" "$dst"
    add_change "Moved existing '$base' out of custom_nodes (kept intact) to: $dst"
}
# Fetch a pinned GitHub commit into a temp folder and structurally validate it BEFORE touching custom_nodes.
ARC_TMP=""; ARC_SRC=""
get_pinned_archive(){
    local repo="$1" commit="$2" tfn="$3" label="$4" tmp src
    ARC_TMP=""; ARC_SRC=""
    tmp="$(mktemp -d "$TMP_ROOT/pin_XXXXXX")"
    info "Downloading $label pinned commit ${commit:0:7} ..."
    if ! try_download "https://github.com/$repo/archive/$commit.zip" "$tmp/src.zip" 900; then rm -rf "$tmp"; return 1; fi
    if ! safe_unzip "$tmp/src.zip" "$tmp/x" >/dev/null 2>&1; then rm -rf "$tmp"; return 1; fi
    src="$(find "$tmp/x" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    if [ -z "$src" ] || ! "$tfn" "$src"; then rm -rf "$tmp"; return 1; fi
    ARC_TMP="$tmp"; ARC_SRC="$src"
    return 0
}
# Generic: keep ONE healthy copy untouched; otherwise validate the pinned copy first, then swap.
ENSURE_PATH=""
ensure_pinned_node(){
    local label="$1" pat="$2" target="$3" repo="$4" commit="$5" tfn="$6" req="$7"
    local found=() healthy=() f keep="" dst msg
    ENSURE_PATH=""
    mapfile -t found < <(get_node_folders "$pat")
    for f in "${found[@]}"; do "$tfn" "$f" && healthy+=("$f"); done
    if [ "${#healthy[@]}" -ge 1 ]; then
        # Keep ONE healthy copy exactly as it is (prefer the standard folder name). Extra copies register the
        # same node ids twice, so they are moved out of custom_nodes (kept intact in the snapshot folder).
        for f in "${healthy[@]}"; do if [ "$(basename "$f")" = "$target" ]; then keep="$f"; break; fi; done
        [ -z "$keep" ] && keep="${healthy[0]}"
        for f in "${found[@]}"; do
            if [ "$f" != "$keep" ]; then warn "$label : extra copy '$(basename "$f")' moved out of custom_nodes."; move_out_of_custom_nodes "$f"; fi
        done
        ok "$label already healthy; leaving it untouched: $(basename "$keep")"
        add_summary "$label : existing healthy copy kept ($(basename "$keep"))"
        ENSURE_PATH="$keep"
        return 0
    fi
    [ "${#found[@]}" -ge 1 ] && warn "$label : the existing copy is missing the nodes this workflow needs."
    if ! get_pinned_archive "$repo" "$commit" "$tfn" "$label"; then
        msg="$label : pinned download or structural validation failed. Nothing was changed for this pack."
        if [ "$req" = "1" ]; then REQUIRED_FAILED=1; warn "$msg"; add_summary "FAILED (required): $label"
        else warn "$msg"; add_summary "SKIPPED (optional): $label"; fi
        return 1
    fi
    for f in "${found[@]}"; do move_out_of_custom_nodes "$f"; done
    dst="$CUSTOM_NODES/$target"
    [ -e "$dst" ] && move_out_of_custom_nodes "$dst"
    mv "$ARC_SRC" "$dst"
    rm -rf "$ARC_TMP"
    if ! "$tfn" "$dst"; then [ "$req" = "1" ] && REQUIRED_FAILED=1; warn "$label : post-install validation failed."; return 1; fi
    add_change "Installed $label from pinned commit $commit into custom_nodes/$target"
    ok "$label installed from pinned commit ${commit:0:7}."
    ENSURE_PATH="$dst"
    return 0
}

# ---- protected-package guard -----------------------------------------------------------------
# Before ANY pip install, a dry run reports what pip WOULD install. If that list touches ComfyUI's
# own requirements, PyTorch, the CUDA wheels or the speed stack, the install is refused.
# What is then installed is exactly the list the dry run approved (--no-deps), nothing more.
PROTECTED_FILE=""
init_protected(){
    PROTECTED_FILE="$STATE_ROOT/protected-packages.txt"
    printf '%s\n' torch torchvision torchaudio torchsde xformers triton triton-windows sageattention numpy transformers \
        tokenizers safetensors onnxruntime onnxruntime-gpu comfy-kitchen comfy-aimdo comfyui-frontend-package \
        comfyui-workflow-templates comfyui-embedded-docs pip setuptools > "$PROTECTED_FILE"
    if [ -f "$COMFY_ROOT/requirements.txt" ]; then
        grep -vE '^[[:space:]]*(#|$)' "$COMFY_ROOT/requirements.txt" | tr -d '\r' |
            sed -nE 's/^[[:space:]]*([A-Za-z0-9_.-]+).*/\1/p' | tr 'A-Z' 'a-z' | sed -E 's/[_.]+/-/g' >> "$PROTECTED_FILE"
    fi
}
PIP_NAMES=""; PIP_PINS=""; PIP_HITS=""; PIP_REASON=""
pip_dry_run(){
    local label="$1"; shift
    local report="$STATE_ROOT/pip-dryrun-$label.json" log="$STATE_ROOT/pip-dryrun-$label.txt" out rc
    PIP_NAMES=""; PIP_PINS=""; PIP_HITS=""; PIP_REASON=""
    rm -f "$report"
    "$PYTHON" -m pip install --disable-pip-version-check --dry-run --quiet --report "$report" "$@" > "$log" 2>&1
    rc=$?
    if [ "$rc" != "0" ] || [ ! -s "$report" ]; then PIP_REASON="pip dry-run could not resolve the requirements (see $log)"; return 1; fi
    if ! out="$("$PYTHON" "$H_PIPGUARD" "$report" "$PROTECTED_FILE" 2>>"$log")"; then PIP_REASON='pip dry-run report could not be parsed'; return 1; fi
    eval "$(printf '%s\n' "$out" | grep -E '^PIP_(NAMES|PINS|HITS)=')"
    if [ -n "$PIP_HITS" ]; then PIP_REASON="it would install or replace protected package(s): $PIP_HITS"; return 1; fi
    return 0
}
# Installs the exact list approved by the last pip_dry_run. An OpenCV that pip wants to add is not
# installed when one already works (two OpenCV builds overwrite each other); on a server without
# one, the headless build is used instead of the desktop build.
install_resolved_pins(){
    local label="$1" p n have_cv2=0 skipped="" rc
    local pins=()
    if timeout 60 "$PYTHON" -c 'import cv2' >/dev/null 2>&1; then have_cv2=1; fi
    for p in $PIP_PINS; do
        n="$(norm_dist "${p%%==*}")"
        case "$n" in
            opencv-python|opencv-contrib-python)
                if [ "$have_cv2" = "1" ]; then skipped="$skipped $p"; continue; fi
                p="opencv-python-headless==${p#*==}" ;;
        esac
        pins+=("$p")
    done
    [ -n "$skipped" ] && info "$label : the OpenCV already installed is kept (not added:$skipped)."
    if [ "${#pins[@]}" -eq 0 ]; then ok "$label : nothing left to install."; return 0; fi
    info "$label : installing ${pins[*]}"
    "$PYTHON" -m pip install --disable-pip-version-check --retries 3 --timeout 30 --no-deps "${pins[@]}"
    rc=$?
    if [ "$rc" != "0" ]; then warn "$label : pip install returned exit code $rc."; return 1; fi
    add_change "pip installed for ${label}: ${pins[*]}"
    return 0
}
install_pip_guarded(){
    local label="$1"; shift
    if ! pip_dry_run "$label" "$@"; then warn "$label : Python requirements were NOT installed because $PIP_REASON."; return 1; fi
    if [ -z "$PIP_NAMES" ]; then ok "$label : Python requirements already satisfied."; return 0; fi
    install_resolved_pins "$label"
}

# ---- locate ComfyUI and its Python -----------------------------------------------------------
find_comfy_root(){
    local c cur i
    local cands=()
    [ -n "${H3_COMFY_ROOT:-}" ] && cands+=("$H3_COMFY_ROOT")
    cands+=("/workspace/runpod-slim/ComfyUI" "/workspace/ComfyUI")
    cur="$INSTALLER_DIR"
    for i in 1 2 3 4 5 6; do
        cands+=("$cur" "$cur/ComfyUI" "$cur/runpod-slim/ComfyUI")
        [ "$cur" = "/" ] && break
        cur="$(dirname "$cur")"
    done
    for c in "${cands[@]}"; do
        if [ -f "$c/main.py" ] && [ -d "$c/comfy" ]; then readlink -f "$c"; return 0; fi
    done
    return 1
}
comfy_pids(){
    local pid
    for pid in $(pgrep -f 'main.py' 2>/dev/null); do
        [ "$(readlink -f "/proc/$pid/cwd" 2>/dev/null)" = "$COMFY_ROOT" ] && echo "$pid"
    done
}
find_python(){
    local root="$1" parent c pid venv
    parent="$(dirname "$root")"
    local cands=()
    [ -n "${H3_PYTHON:-}" ] && cands+=("$H3_PYTHON")
    cands+=("$root/.venv-cu128/bin/python" "$root/.venv-cu130/bin/python" "$root/.venv/bin/python" "$root/venv/bin/python"
            "$parent/.venv/bin/python" "$parent/venv/bin/python")
    for c in "${cands[@]}"; do [ -x "$c" ] && { echo "$c"; return 0; }; done
    # The virtual environment of a ComfyUI that is running from this folder.
    for pid in $(comfy_pids); do
        venv="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^VIRTUAL_ENV=//p' | head -n 1)"
        if [ -n "$venv" ] && [ -x "$venv/bin/python" ]; then echo "$venv/bin/python"; return 0; fi
    done
    command -v python3 2>/dev/null && return 0
    return 1
}

# =============================================================================================
echo "$RULE"
echo "${C_WHITE} H3 Reference Director - Workflow 01 v2 - RunPod Installer v2.1${C_OFF}"
echo "$RULE"
echo "Installs: custom nodes (pinned) + our node pack v0.10.1 + speed dependencies + live-preview decoder."
echo "${C_YELLOW}The main model files are downloaded by hand from the list in the MODELS PDF;${C_OFF}"
echo "${C_YELLOW}this installer checks them and reports what is complete, missing or damaged.${C_OFF}"
echo "${C_YELLOW}The only model file it downloads is the 10 MB live-preview decoder (taeh3), SHA-256 verified.${C_OFF}"
echo "Never upgrades or downgrades: ComfyUI core, PyTorch, CUDA, Triton, NumPy, ComfyUI-Manager or your workflows."
echo "Healthy existing installs are kept. Anything replaced is MOVED to a snapshot folder, never deleted."

COMFY_ROOT="$(find_comfy_root)" || fail 'Could not locate a ComfyUI folder containing main.py and comfy. This installer expects the RunPod ComfyUI template (/workspace/runpod-slim/ComfyUI) or /workspace/ComfyUI. Another location: run it as  H3_COMFY_ROOT=/path/to/ComfyUI ./INSTALL_H3_REFERENCE_DIRECTOR_V2_RUNPOD.sh'
PYTHON="$(find_python "$COMFY_ROOT")" || fail "Could not locate the Python that runs ComfyUI. Set it with  H3_PYTHON=/path/to/python ./INSTALL_H3_REFERENCE_DIRECTOR_V2_RUNPOD.sh"
CUSTOM_NODES="$COMFY_ROOT/custom_nodes"; mkdir -p "$CUSTOM_NODES"
MODELS="$COMFY_ROOT/models"; mkdir -p "$MODELS"
COMFY_PARENT="$(dirname "$COMFY_ROOT")"
TOOLS_DIR="$COMFY_PARENT/H3_REFDIRECTOR_TOOLS"
STAMP="$(date +%Y%m%d_%H%M%S)"
STATE_ROOT="$COMFY_PARENT/H3_REFDIRECTOR_V2_SNAPSHOT_$STAMP"
mkdir -p "$STATE_ROOT" || { STATE_ROOT=""; fail "Could not create the snapshot folder next to ComfyUI ($COMFY_PARENT)."; }

# The RunPod ComfyUI template pins PyTorch for every pip call with this constraint file. Use it here too.
if [ -z "${PIP_CONSTRAINT:-}" ] && [ -f /opt/comfyui-runtime-constraints.txt ]; then
    export PIP_CONSTRAINT=/opt/comfyui-runtime-constraints.txt
fi

step '1/6  Read-only preflight + safety snapshot'
echo "ComfyUI root : $COMFY_ROOT"
echo "Python       : $PYTHON"
echo "Snapshot/log : $STATE_ROOT"
add_summary 'Installer: H3 Reference Director Workflow 01 v2 - RunPod v2.1'
add_summary "ComfyUI root: $COMFY_ROOT"; add_summary "Python: $PYTHON"
[ -n "${PIP_CONSTRAINT:-}" ] && info "pip constraints in effect: $PIP_CONSTRAINT"

# Download tools (RunPod rule from v8: install a missing tool with apt-get).
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    if apt_ok && apt_install wget; then ok 'Installed missing tool: wget'
    else fail 'Neither curl nor wget is available, and wget could not be installed with apt-get.'; fi
else
    ok "Download tool: $(command -v curl >/dev/null 2>&1 && echo curl || echo wget)"
fi

RUNNING="$(comfy_pids | tr '\n' ' ' | sed 's/ *$//')"
if [ -n "${RUNNING// /}" ]; then
    info "ComfyUI is running from this folder (PID $RUNNING). That is fine on RunPod: nothing is locked, and the new nodes load after you restart ComfyUI at the end."
else
    ok 'No running ComfyUI process found for this folder.'
fi

SELF_LOG="$STATE_ROOT/python-self-test.txt"
if ! "$PYTHON" -c "print('H3_PYTHON_SELF_TEST_OK')" > "$SELF_LOG" 2>&1 || ! grep -q H3_PYTHON_SELF_TEST_OK "$SELF_LOG"; then
    fail 'Python self-test failed. Nothing has been installed.'
fi
ok 'Python self-test passed.'
if ! "$PYTHON" -m pip --version > "$STATE_ROOT/pip-version.txt" 2>&1; then
    fail "pip is not available in ComfyUI's Python ($PYTHON). Nothing has been installed."
fi

for v in python py_major py_minor py_bits machine pip triton sageattention numpy torchvision torchaudio free_threaded \
         include_path torch cuda hip cuda_available gpu cc_major cc_minor vram_gb torch_error; do
    printf -v "PF_$v" '%s' ''
done
if ! run_py "$H_PREFLIGHT" 120 "$STATE_ROOT/hardware-python-preflight.txt" || ! printf '%s' "$PY_OUT" | grep -q '^PF_python='; then
    fail 'Python preflight failed. See hardware-python-preflight.txt in the snapshot folder.'
fi
eval "$(printf '%s\n' "$PY_OUT" | grep -E '^PF_[a-z_]+=')"
[ -n "$PF_torch" ] || fail "PyTorch could not be imported by ComfyUI's Python ($PF_torch_error). Fix the ComfyUI install first; this installer never installs PyTorch."
echo "Python       : $PF_python ($PF_py_bits-bit, $PF_machine)"
echo "Torch / CUDA : $PF_torch / $PF_cuda   CUDA usable: $([ "$PF_cuda_available" = 1 ] && echo True || echo False)"
if [ -n "$PF_gpu" ]; then echo "GPU          : $PF_gpu   compute cap. $PF_cc_major.$PF_cc_minor   VRAM $PF_vram_gb GB"
else echo "GPU          : none visible to PyTorch"; fi
echo "NumPy / pip  : $PF_numpy / $PF_pip"
add_summary "Environment: Python $PF_python; Torch $PF_torch; CUDA $PF_cuda; NumPy $PF_numpy; GPU $PF_gpu; VRAM ${PF_vram_gb}GB"
[ "$PF_py_bits" = "64" ] || fail 'Only 64-bit Python is supported.'
if [ "$PF_py_major" != "3" ] || [ "$PF_py_minor" -lt 10 ]; then fail "Python $PF_python is older than the supported 3.10+."; fi

# ComfyUI native MiniMax H3 structural gate. No core update is ever performed.
H3_CORE="$COMFY_ROOT/comfy_extras/nodes_minimax_h3.py"
[ -f "$H3_CORE" ] || fail 'Native MiniMax H3 support is missing from this ComfyUI. Update ComfyUI yourself (ComfyUI Manager > Update ComfyUI), restart it, confirm a normal H3 workflow runs, then run this installer again.'
ok 'ComfyUI native MiniMax H3 support is present.'
MODEL_BASE="$COMFY_ROOT/comfy/model_base.py"
HQ_CORE_OK=0
if file_has "$MODEL_BASE" '_denoise_mask_conds' && [ -f "$COMFY_ROOT/comfy/nested_tensor.py" ] &&
   file_has "$COMFY_ROOT/comfy_execution/graph_utils.py" 'ExecutionBlocker'; then
    HQ_CORE_OK=1
    ok 'ComfyUI core has MiniMax H3 audio-video noise-mask support (needed by the latent upscale, motion refine and face refine groups).'
else
    warn 'This ComfyUI build lacks MiniMax H3 audio-video noise-mask support (it arrived in ComfyUI 0.34). Everything else works; keep the latent upscale, motion refine and face refine groups OFF until you update ComfyUI yourself (ComfyUI Manager > Update ComfyUI, restart ComfyUI, then run this installer again to confirm).'
fi

CORE_HASH_FILES=()
for f in "$COMFY_ROOT/main.py" "$H3_CORE" "$MODEL_BASE" "$COMFY_ROOT/nodes.py" "$COMFY_ROOT/requirements.txt"; do
    [ -f "$f" ] && CORE_HASH_FILES+=("$f")
done
sha256sum "${CORE_HASH_FILES[@]}" > "$STATE_ROOT/comfy-core-hashes-before.txt"
ls -1 "$CUSTOM_NODES" > "$STATE_ROOT/custom-nodes-before.txt" 2>/dev/null
"$PYTHON" -m pip freeze --disable-pip-version-check > "$STATE_ROOT/pip-freeze-before.txt" 2>&1
init_protected
FREE_GB="$(df -BG --output=avail "$COMFY_ROOT" 2>/dev/null | tail -n 1 | tr -dc '0-9')"
echo "Free disk    : ${FREE_GB:-?} GB (ComfyUI volume)"
ok 'Snapshot written: core hashes, custom-node list, pip freeze.'

# =============================================================================================
step '2/6  Custom nodes (pinned commits; healthy copies are kept)'

ensure_pinned_node 'ComfyUI-H3-Multishot' 'ComfyUI-H3-Multishot*' 'ComfyUI-H3-Multishot' 'jlucasmcrell/ComfyUI-H3-Multishot' "$PIN_MULTISHOT" test_multishot 1
MULTISHOT="$ENSURE_PATH"
# VideoHelperSuite is not installed any more: the workflow's video loaders are our own H3RDLoadVideo node.
# An existing VideoHelperSuite is left exactly as it is.

# ---- our own node pack, from the ZIP beside this installer, hash-verified ------------------------
EXACT_PATH=""
mapfile -t EXACT_FOUND < <(get_node_folders 'ComfyUI-H3-ExactMasterMemory*')
EXACT_HEALTHY=""
for f in "${EXACT_FOUND[@]}"; do if test_exact "$f"; then EXACT_HEALTHY="$f"; break; fi; done
if [ -n "$EXACT_HEALTHY" ]; then
    for f in "${EXACT_FOUND[@]}"; do
        if [ "$f" != "$EXACT_HEALTHY" ]; then warn "ExactMasterMemory : older/extra copy '$(basename "$f")' moved out of custom_nodes."; move_out_of_custom_nodes "$f"; fi
    done
    ok 'ComfyUI-H3-ExactMasterMemory v0.10.1 already healthy; leaving it untouched.'
    add_summary 'ExactMasterMemory: existing v0.10.1 kept'
    EXACT_PATH="$EXACT_HEALTHY"
else
    ZIP_PATH=""
    for d in "$INSTALLER_DIR" "$PWD" /workspace/runpod-slim /workspace; do
        if [ -f "$d/$EXACT_ZIP_NAME" ]; then ZIP_PATH="$d/$EXACT_ZIP_NAME"; break; fi
    done
    [ -n "$ZIP_PATH" ] || fail "Required file is missing: $EXACT_ZIP_NAME. Keep it in the same folder as this installer (or in /workspace/runpod-slim or /workspace)."
    info "Node pack ZIP: $ZIP_PATH"
    ACTUAL="$(sha256_of "$ZIP_PATH")"
    [ "$ACTUAL" = "$EXACT_ZIP_SHA256" ] || fail "$EXACT_ZIP_NAME SHA-256 mismatch. Expected $EXACT_ZIP_SHA256; got $ACTUAL. The file was NOT installed."
    ok "$EXACT_ZIP_NAME SHA-256 verified."
    TMP_E="$(mktemp -d "$TMP_ROOT/exact_XXXXXX")"
    safe_unzip "$ZIP_PATH" "$TMP_E" || fail 'The bundled ExactMasterMemory ZIP could not be extracted. Nothing was changed.'
    SRC_E="$TMP_E/ComfyUI-H3-ExactMasterMemory"
    test_exact "$SRC_E" || fail 'The bundled ExactMasterMemory ZIP failed structural validation. Nothing was changed.'
    mapfile -t PY_FILES < <(find "$SRC_E" -maxdepth 1 -type f -name '*.py' | sort)
    if ! "$PYTHON" -m py_compile "${PY_FILES[@]}" > "$STATE_ROOT/exactmaster-compile.txt" 2>&1; then
        fail "The bundled node pack does not compile with this Python ($PF_python). Nothing was changed. See exactmaster-compile.txt."
    fi
    find "$SRC_E" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null
    for f in "${EXACT_FOUND[@]}"; do move_out_of_custom_nodes "$f"; done
    [ -e "$CUSTOM_NODES/ComfyUI-H3-ExactMasterMemory" ] && move_out_of_custom_nodes "$CUSTOM_NODES/ComfyUI-H3-ExactMasterMemory"
    mv "$SRC_E" "$CUSTOM_NODES/ComfyUI-H3-ExactMasterMemory"
    add_change 'Installed ComfyUI-H3-ExactMasterMemory v0.10.1 (hash-verified, compile-checked)'
    ok 'ComfyUI-H3-ExactMasterMemory v0.10.1 installed (hash-verified, compile-checked).'
    EXACT_PATH="$CUSTOM_NODES/ComfyUI-H3-ExactMasterMemory"
fi

# ---- KJNodes: keep if it has both Sage nodes; validated pin otherwise ------------------------
KJ_ALLOW=' pillow color-matcher matplotlib mss opencv-python-headless '
test_kj_requirements(){
    local req="$1/requirements.txt" line pkg
    [ -f "$req" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line="$(printf '%s' "$line" | tr -d '\r' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
        [ -z "$line" ] && continue
        case "$line" in \#*) continue ;; esac
        pkg="$(printf '%s' "$line" | grep -oE '^[A-Za-z0-9_.-]+' | tr 'A-Z' 'a-z')"
        case "$KJ_ALLOW" in *" $pkg "*) ;; *) warn "KJNodes requirements contain an unexpected package '$pkg'."; return 1 ;; esac
    done < "$req"
    return 0
}
KJ_INSTALL_TARGET=""
install_kj(){
    local commit="$1" tfn="$2" why="$3" f has_pins=0 kj_folders=()
    if ! get_pinned_archive 'kijai/ComfyUI-KJNodes' "$commit" "$tfn" 'ComfyUI-KJNodes'; then
        warn "KJNodes pinned archive ($why) failed download or validation. Nothing was changed."; return 1
    fi
    if ! test_kj_requirements "$ARC_SRC"; then rm -rf "$ARC_TMP"; return 1; fi
    if [ -f "$ARC_SRC/requirements.txt" ]; then
        if ! pip_dry_run "kjnodes-${commit:0:7}" -r "$ARC_SRC/requirements.txt"; then
            warn "KJNodes was NOT changed because $PIP_REASON."; rm -rf "$ARC_TMP"; return 1
        fi
        [ -n "$PIP_NAMES" ] && has_pins=1
    fi
    mapfile -t kj_folders < <(get_node_folders 'ComfyUI-KJNodes*')
    for f in "${kj_folders[@]}"; do move_out_of_custom_nodes "$f"; done
    KJ_INSTALL_TARGET="$CUSTOM_NODES/ComfyUI-KJNodes"
    [ -e "$KJ_INSTALL_TARGET" ] && move_out_of_custom_nodes "$KJ_INSTALL_TARGET"
    mv "$ARC_SRC" "$KJ_INSTALL_TARGET"
    rm -rf "$ARC_TMP"
    if [ "$has_pins" = "1" ]; then install_resolved_pins 'KJNodes' || warn 'KJNodes requirements installation returned an error.'; fi
    add_change "Installed ComfyUI-KJNodes from pinned commit $commit ($why)"
    return 0
}
mapfile -t KJ_FOLDERS < <(get_node_folders 'ComfyUI-KJNodes*')
KJ_TARGET=""; KJ_KEPT=0
for f in "${KJ_FOLDERS[@]}"; do if test_kj_required "$f"; then KJ_TARGET="$f"; break; fi; done
if [ -n "$KJ_TARGET" ]; then
    for f in "${KJ_FOLDERS[@]}"; do
        if [ "$f" != "$KJ_TARGET" ]; then warn "KJNodes : extra copy '$(basename "$f")' moved out of custom_nodes."; move_out_of_custom_nodes "$f"; fi
    done
    ok 'Existing KJNodes contains both required H3/Sage nodes.'
    KJ_KEPT=1
else
    [ "${#KJ_FOLDERS[@]}" -ge 1 ] && info 'The installed KJNodes predates the MiniMax H3 Mem-Eff Sage node this workflow uses (the RunPod template ships an older copy). It is replaced by the pinned commit; the old copy goes to the snapshot folder.'
    # Both pins carry byte-identical Sage and Mem-Eff code; the live-preview pin adds MiniMax H3 decoding
    # to the LIVE PREVIEW node, which the workflow ships switched ON.
    if [ "$H3_UPGRADE_KJNODES_FOR_PREVIEW" = "1" ] && install_kj "$PIN_KJ_PREVIEW" test_kj_both 'live-preview pin'; then
        KJ_TARGET="$KJ_INSTALL_TARGET"; ok "KJNodes installed from pinned commit ${PIN_KJ_PREVIEW:0:7} (Sage, Mem-Eff Sage and H3 live preview)."
    elif install_kj "$PIN_KJ_VALIDATED" test_kj_required 'validated Sage pin'; then
        KJ_TARGET="$KJ_INSTALL_TARGET"; ok "KJNodes installed from the validated pinned commit ${PIN_KJ_VALIDATED:0:7}."
        [ "$H3_UPGRADE_KJNODES_FOR_PREVIEW" = "1" ] && warn 'The live-preview KJNodes commit could not be installed, so the validated commit was used. Live preview stays unavailable; switch the LIVE PREVIEW node off (Ctrl+B).'
    else
        REQUIRED_FAILED=1; add_summary 'FAILED (required): KJNodes'
    fi
fi
PREVIEW_KJ=0
if [ -n "$KJ_TARGET" ] && test_kj_preview "$KJ_TARGET"; then
    PREVIEW_KJ=1
    if [ "$KJ_KEPT" = "1" ]; then ok 'KJNodes supports the MiniMax H3 live preview; leaving it untouched.'
    else ok 'KJNodes supports the MiniMax H3 live preview.'; fi
elif [ -n "$KJ_TARGET" ] && test_kj_required "$KJ_TARGET"; then
    # No question. Controlled by H3_UPGRADE_KJNODES_FOR_PREVIEW at the top of this file (default 1 on RunPod).
    if [ "$H3_UPGRADE_KJNODES_FOR_PREVIEW" = "1" ]; then
        info 'Your KJNodes has the Sage nodes but predates the MiniMax H3 live preview the workflow uses. It is replaced by the pinned live-preview commit; your current copy is moved to the snapshot folder.'
        if install_kj "$PIN_KJ_PREVIEW" test_kj_both 'live-preview pin'; then
            KJ_TARGET="$KJ_INSTALL_TARGET"; PREVIEW_KJ=1; ok 'KJNodes upgraded to the live-preview pinned commit.'
        else
            warn 'KJNodes was left as it was. Live preview stays unavailable; switch the LIVE PREVIEW node off (Ctrl+B).'
        fi
    else
        info 'KJNodes works for Sage but predates MiniMax H3 live-preview support. It was left unchanged because H3_UPGRADE_KJNODES_FOR_PREVIEW=0. Switch the LIVE PREVIEW node off (Ctrl+B), or run the installer again with the setting at 1.'
    fi
fi

# ---- Live-preview decoder taeh3.safetensors: the ONLY model file this installer downloads ---------
# Pinned to one repository commit; installed only after its size and SHA-256 match. A complete
# taeh3 that is already there is kept as it is, even a different version (for example the temporal
# taeh3 from madebyollin, which the same node also reads). Only a damaged copy is moved aside.
TAEH3_PATH="$MODELS/vae_approx/taeh3.safetensors"
get_preview_decoder(){
    local tmp stage
    if [ -f "$TAEH3_PATH" ]; then
        if [ "$(sha256_of "$TAEH3_PATH")" = "$TAEH3_SHA256" ]; then
            ok 'Live-preview decoder taeh3.safetensors is present (SHA-256 verified); leaving it untouched.'; return 0
        fi
        if "$PYTHON" "$H_STCHECK" "$TAEH3_PATH" >/dev/null 2>&1; then
            info 'A different but complete taeh3.safetensors is in models/vae_approx (for example the temporal version from madebyollin, which the same node reads). It is kept as it is.'
            return 0
        fi
        warn 'The taeh3.safetensors in models/vae_approx is damaged or incomplete. It is moved to the snapshot folder and downloaded again.'
        mkdir -p "$STATE_ROOT/moved_models"
        mv "$TAEH3_PATH" "$STATE_ROOT/moved_models/"
        add_change "Moved a damaged vae_approx/taeh3.safetensors to $STATE_ROOT/moved_models"
    fi
    if [ "$H3_DOWNLOAD_PREVIEW_DECODER" != "1" ]; then
        info 'H3_DOWNLOAD_PREVIEW_DECODER=0: taeh3.safetensors was not downloaded. Download it by hand, or switch the LIVE PREVIEW node off (Ctrl+B).'
        return 1
    fi
    tmp="$(mktemp -d "$TMP_ROOT/taeh3_XXXXXX")"
    info 'Downloading the live-preview decoder taeh3.safetensors (about 10 MB, Kijai/MiniMax-H3-TAE, pinned commit a213ac8) ...'
    if ! try_download "$TAEH3_URL" "$tmp/taeh3.safetensors" 600; then
        warn 'taeh3.safetensors could not be downloaded (Hugging Face unreachable?). Nothing was changed. Run the installer again later, or switch the LIVE PREVIEW node off (Ctrl+B).'
        return 1
    fi
    if [ "$(stat -c %s "$tmp/taeh3.safetensors")" != "$TAEH3_BYTES" ] || [ "$(sha256_of "$tmp/taeh3.safetensors")" != "$TAEH3_SHA256" ]; then
        warn 'The downloaded taeh3.safetensors does not match its pinned SHA-256. It was NOT installed.'
        return 1
    fi
    # Copy under a hidden name in the same folder, then rename: no half-written file ever carries the real name.
    mkdir -p "$MODELS/vae_approx"
    stage="$MODELS/vae_approx/.taeh3.safetensors.h3-incoming"
    cp "$tmp/taeh3.safetensors" "$stage" && mv -f "$stage" "$TAEH3_PATH" || { rm -f "$stage"; warn 'taeh3.safetensors could not be written to models/vae_approx.'; return 1; }
    add_change 'Downloaded vae_approx/taeh3.safetensors (Kijai/MiniMax-H3-TAE @ a213ac8, SHA-256 verified)'
    ok 'Live-preview decoder taeh3.safetensors installed (SHA-256 verified).'
    return 0
}
get_preview_decoder || true

ensure_pinned_node 'MiniMax H3 FirstBlockCache' 'ComfyUI-MiniMaxH3-FirstBlockCache*' 'ComfyUI-MiniMaxH3-FirstBlockCache' 'duckyshell/ComfyUI-MiniMaxH3-FirstBlockCache' "$PIN_FBC" test_fbc 1
FBC="$ENSURE_PATH"
ensure_pinned_node 'ComfyUI-MAINodes (motion refine, Group 06)' 'ComfyUI-MAINodes*' 'ComfyUI-MAINodes' 'matlowai/ComfyUI-MAINodes' "$PIN_MAINODES" test_mainodes 0
MAI="$ENSURE_PATH"
ensure_pinned_node 'LBH MiniMax H3 Latent Upscaler (latent upscale, Group 07)' '*Minimax_h3_latent_Upscaler*' 'ComfyUI_Minimax_h3_latent_Upscaler' 'LBH-123-AI/ComfyUI_Minimax_h3_latent_Upscaler' "$PIN_LBH" test_lbh 0
LBH="$ENSURE_PATH"

# ---- H3 Face Refine node pack (Group 08 of the workflow) --------------------------------------
# The pack imports its heavy Python packages only while face refine actually runs, so adding the
# folder is always safe: the workflow then loads without missing-node warnings. The Python packages
# are a separate, guarded step.
ensure_pinned_node 'H3 Face Refine (Group 08)' 'ComfyUI-H3-FaceRefine*' 'ComfyUI-H3-FaceRefine' 'Carasibana/ComfyUI-H3-FaceRefine' "$PIN_FACEREFINE" test_facerefine 0
FACE_REFINE="$ENSURE_PATH"
FACE_ultralytics=0; FACE_scenedetect=0; FACE_scipy=0
get_face_packages(){
    FACE_ultralytics=0; FACE_scenedetect=0; FACE_scipy=0
    if run_py "$H_FACEPROBE" 60 "$STATE_ROOT/face-packages-probe.txt"; then
        eval "$(printf '%s\n' "$PY_OUT" | grep -E '^FACE_(ultralytics|scenedetect|scipy)=[01]$')"
    fi
}
get_face_packages
if [ -n "$FACE_REFINE" ]; then
    # No question here. Each step is guarded: if it would touch a protected package, or pip cannot
    # complete it, that step is skipped with a message and nothing else is affected.
    if [ "$FACE_ultralytics" != 1 ] || [ "$FACE_scenedetect" != 1 ] || [ "$FACE_scipy" != 1 ]; then
        info 'Installing the Python packages for face refine (ultralytics, scenedetect) ...'
        install_pip_guarded 'FaceRefine-base' 'ultralytics' 'scenedetect>=0.7' 'scipy' || true
        get_face_packages
    fi
    if [ "$FACE_ultralytics" = 1 ] && [ "$FACE_scenedetect" = 1 ]; then ok 'Face refine Python packages ready (ultralytics + scenedetect).'
    else warn 'Face refine Python packages are not complete. The workflow still loads and runs; keep enable_face_refine OFF.'; fi
fi

# =============================================================================================
step '3/6  Speed dependencies (Triton + SageAttention 2.2.0)'
SPEED_READY=0; SPEED_NOTE=""; SPEED_ABORT=""; SAGE_WHEEL=""; SAGE_TEST_ERR=""
TM="$(printf '%s' "$PF_torch" | grep -oE '^[0-9]+\.[0-9]+' || true)"
CM="$(printf '%s' "$PF_cuda" | grep -oE '^[0-9]+\.[0-9]+' || true)"
TORCH_MAJOR="${TM%%.*}"; TORCH_MINOR="${TM#*.}"
CUDA_MAJOR="${CM%%.*}"; CUDA_MINOR="${CM#*.}"
[ -z "$TM" ] && { TORCH_MAJOR=-1; TORCH_MINOR=-1; }
[ -z "$CM" ] && { CUDA_MAJOR=-1; CUDA_MINOR=-1; }
SM="${PF_cc_major}${PF_cc_minor}"
SPEED_BLOCK=""
if [ "$PF_cuda_available" != "1" ] || { [ -n "$PF_hip" ] && [ "$PF_hip" != "None" ]; }; then
    SPEED_BLOCK='a CUDA-enabled NVIDIA PyTorch is required (AMD/ROCm and CPU are not supported by the speed stack)'
elif [ "$PF_free_threaded" = "1" ]; then SPEED_BLOCK='free-threaded Python builds are not supported'
elif [ "$PF_py_minor" -gt 14 ]; then SPEED_BLOCK="Python $PF_python is newer than the validated 3.10-3.14 range"
elif [ "$TORCH_MAJOR" != "2" ]; then SPEED_BLOCK='PyTorch 2.x could not be identified'
elif [ "$TORCH_MINOR" -lt 3 ]; then SPEED_BLOCK="PyTorch $PF_torch is older than 2.3, the minimum for SageAttention 2.2.0"
elif [ "$CUDA_MAJOR" != "12" ] && [ "$CUDA_MAJOR" != "13" ]; then SPEED_BLOCK="CUDA $PF_cuda is outside the supported 12.x / 13.x"
elif [[ " 80 86 89 90 120 " != *" $SM "* ]]; then
    SPEED_BLOCK="GPU compute capability SM$SM is outside the supported set (A100, RTX 30/A40/A6000, RTX 40/L40S/L4, H100/H200, RTX 50/RTX PRO 6000; B200 is not covered)"
elif [ "$SM" = "120" ] && [ "$CUDA_MAJOR" = "12" ] && [ "$CUDA_MINOR" -lt 8 ]; then
    SPEED_BLOCK="Blackwell/SM120 needs a CUDA 12.8+ (or 13.x) PyTorch; detected CUDA $PF_cuda"
fi

SAGE_PROFILE="py${PF_py_major}${PF_py_minor}-torch${PF_torch}-sm${SM}"
SAGE_CACHE="$TOOLS_DIR/wheels/sageattention-$SAGE_LINE/$SAGE_PROFILE"

# Triton compiles a small launcher with the Python header and a C compiler the first time it runs.
ensure_jit_toolchain(){
    local pkgs=()
    [ -f "$PF_include_path/Python.h" ] || pkgs+=("python${PF_py_major}.${PF_py_minor}-dev")
    command -v gcc >/dev/null 2>&1 || pkgs+=("build-essential")
    if [ "${#pkgs[@]}" -eq 0 ]; then ok 'Python development header (Python.h) and C compiler are present; leaving them untouched.'; return 0; fi
    if ! apt_ok; then SPEED_ABORT="Triton needs ${pkgs[*]}, and apt-get is not available here as root"; return 1; fi
    info "Installing ${pkgs[*]} with apt-get (Triton compiles a small launcher with them) ..."
    if ! apt_install "${pkgs[@]}"; then SPEED_ABORT="apt-get could not install ${pkgs[*]} (see apt-get.txt)"; return 1; fi
    add_change "apt-get installed ${pkgs[*]}"
    warn "${pkgs[*]} were added to the container disk, which RunPod resets on every Pod restart. Run this installer again after each restart, before rendering."
    if [ ! -f "$PF_include_path/Python.h" ]; then SPEED_ABORT='Python.h is still missing after apt-get'; return 1; fi
    return 0
}
test_sage_stack(){
    run_check "$H_SAGE_TEST" 240 sageattention-cuda-test SAGE_CUDA_OK || { SAGE_TEST_ERR='SageAttention CUDA smoke test failed (see sageattention-cuda-test.txt)'; return 1; }
    run_check "$H_MEMEFF_TEST" 120 sageattention-memeff-test MEMEFF_OK || { SAGE_TEST_ERR='SageAttention lacks the compiled kernels the MEM-EFF SAGE nodes call (see sageattention-memeff-test.txt)'; return 1; }
    return 0
}
build_sage_wheel(){
    local nvcc="" c nv nv_major need="" cuda_home tmp src bt out log arch jobs rc w n
    local missing=() h d extra=() cpath_add="" nvcc_add="" stubs=""
    for c in "${CUDA_HOME:-/nonexistent}/bin/nvcc" /usr/local/cuda/bin/nvcc "$(command -v nvcc 2>/dev/null || true)"; do
        if [ -n "$c" ] && [ -x "$c" ]; then nvcc="$c"; break; fi
    done
    if [ -z "$nvcc" ]; then SPEED_ABORT="the CUDA compiler (nvcc) was not found. The official RunPod ComfyUI template includes it; this Pod's image does not"; return 1; fi
    cuda_home="$(dirname "$(dirname "$(readlink -f "$nvcc")")")"
    nv="$("$nvcc" --version 2>/dev/null | grep -oE 'release [0-9]+\.[0-9]+' | awk '{print $2}')"
    [ -n "$nv" ] || { SPEED_ABORT="could not read the version of $nvcc"; return 1; }
    nv_major="${nv%%.*}"
    if [ "$nv_major" != "$CUDA_MAJOR" ]; then SPEED_ABORT="nvcc $nv does not match PyTorch's CUDA $PF_cuda (the major versions must be equal)"; return 1; fi
    case "$SM" in 89) need='12.4' ;; 90) need='12.3' ;; 120) need='12.8' ;; *) need='12.0' ;; esac
    if ! version_ge "$nv" "$need"; then SPEED_ABORT="SageAttention needs CUDA $need or newer for SM$SM; nvcc is $nv"; return 1; fi
    info "CUDA compiler: $nvcc (CUDA $nv)"

    tmp="$(mktemp -d "$TMP_ROOT/sage_XXXXXX")"
    info "Downloading SageAttention $SAGE_LINE source, pinned commit ${PIN_SAGE:0:7} (thu-ml/SageAttention tag v2.2.0) ..."
    if ! try_download "https://github.com/thu-ml/SageAttention/archive/$PIN_SAGE.zip" "$tmp/src.zip" 900; then SPEED_ABORT='the pinned SageAttention source could not be downloaded'; return 1; fi
    if ! safe_unzip "$tmp/src.zip" "$tmp/x" >/dev/null 2>&1; then SPEED_ABORT='the SageAttention source archive could not be extracted'; return 1; fi
    src="$(find "$tmp/x" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    if [ -z "$src" ] || ! file_has "$src/setup.py" "version='2.2.0'" || ! file_has "$src/setup.py" 'SUPPORTED_ARCHS'; then
        SPEED_ABORT='the SageAttention source failed its structural check'; return 1
    fi

    # PyTorch's CUDA extension headers include these CUDA library headers. When the CUDA folder lacks
    # them, the copies inside PyTorch's own NVIDIA wheels are used for this build only.
    for h in cusparse.h cublas_v2.h cublasLt.h cusolverDn.h; do [ -f "$cuda_home/include/$h" ] || missing+=("$h"); done
    if [ "${#missing[@]}" -gt 0 ]; then
        while IFS= read -r d; do
            [ -n "$d" ] || continue
            for h in "${missing[@]}"; do if [ -f "$d/$h" ]; then extra+=("$d"); break; fi; done
        done < <("$PYTHON" "$H_NVINC" 2>/dev/null)
        local still=()
        for h in "${missing[@]}"; do
            local hit=0
            for d in "${extra[@]}"; do [ -f "$d/$h" ] && hit=1; done
            [ "$hit" = "1" ] || still+=("$h")
        done
        if [ "${#still[@]}" -gt 0 ]; then
            local tag="${nv/./-}"
            if apt_ok && apt_install "libcusparse-dev-$tag" "libcublas-dev-$tag" "libcusolver-dev-$tag"; then
                info "apt-get added the CUDA $nv library headers for this build (container disk only)."
            else
                SPEED_ABORT="CUDA library headers are missing (${still[*]}) and could not be added"; return 1
            fi
        fi
        for d in "${extra[@]}"; do cpath_add="${cpath_add:+$cpath_add:}$d"; nvcc_add="$nvcc_add -I$d"; done
    fi
    [ -d "$cuda_home/lib64/stubs" ] && stubs="$cuda_home/lib64/stubs"

    bt="$tmp/buildtools"
    info "Preparing private build tools (setuptools, wheel, packaging, ninja) in a temporary folder; ComfyUI's Python is not changed ..."
    if ! "$PYTHON" -m pip install --disable-pip-version-check --quiet --target "$bt" 'setuptools>=62,<75' 'wheel>=0.38,<0.44' 'packaging>=21,<24' 'ninja' > "$STATE_ROOT/sageattention-buildtools.txt" 2>&1; then
        SPEED_ABORT='the temporary build tools could not be prepared (see sageattention-buildtools.txt)'; return 1
    fi

    arch="$PF_cc_major.$PF_cc_minor"
    jobs="$(nproc 2>/dev/null || echo 2)"; jobs=$((jobs / 2)); [ "$jobs" -lt 1 ] && jobs=1; [ "$jobs" -gt 8 ] && jobs=8
    out="$tmp/out"; mkdir -p "$out"
    log="$STATE_ROOT/sageattention-build.txt"
    info "Building SageAttention $SAGE_LINE for SM$SM (TORCH_CUDA_ARCH_LIST=$arch, $jobs parallel jobs)."
    info 'This takes about 3-15 minutes (about 3 on an RTX 4090) and happens once per GPU type. A dot is printed every 30 seconds ...'
    (
        export PYTHONPATH="$bt${PYTHONPATH:+:$PYTHONPATH}"
        export PATH="$bt/bin:$cuda_home/bin:$PATH"
        export CUDA_HOME="$cuda_home"
        export TORCH_CUDA_ARCH_LIST="$arch"
        export MAX_JOBS="$jobs"
        export EXT_PARALLEL=2
        [ -n "$cpath_add" ] && export CPATH="$cpath_add${CPATH:+:$CPATH}"
        [ -n "$nvcc_add" ] && export NVCC_APPEND_FLAGS="${NVCC_APPEND_FLAGS:-}$nvcc_add"
        [ -n "$stubs" ] && export LIBRARY_PATH="${LIBRARY_PATH:+$LIBRARY_PATH:}$stubs"
        exec timeout 5400 "$PYTHON" -m pip wheel --disable-pip-version-check --no-build-isolation --no-deps -v -w "$out" "$src"
    ) > "$log" 2>&1 &
    local pid=$!
    n=0
    while kill -0 "$pid" 2>/dev/null; do sleep 2; n=$((n + 2)); [ $((n % 30)) -eq 0 ] && printf '.'; done
    wait "$pid"; rc=$?
    echo
    if [ "$rc" != "0" ]; then
        echo "${C_GRAY}--- last lines of sageattention-build.txt ---${C_OFF}"
        tail -n 25 "$log" | sed 's/^/    /'
        SPEED_ABORT="the SageAttention build failed (exit code $rc; see sageattention-build.txt in the snapshot folder)"
        return 1
    fi
    w="$(find "$out" -maxdepth 1 -name 'sageattention-*.whl' | head -n 1)"
    [ -n "$w" ] || { SPEED_ABORT='the SageAttention build produced no wheel'; return 1; }
    mkdir -p "$SAGE_CACHE"
    cp "$w" "$SAGE_CACHE/"
    SAGE_WHEEL="$SAGE_CACHE/$(basename "$w")"
    sha256_of "$SAGE_WHEEL" > "$SAGE_WHEEL.sha256"
    printf 'SageAttention %s from thu-ml/SageAttention commit %s\nbuilt %s\nprofile %s\nnvcc %s\n' \
        "$SAGE_LINE" "$PIN_SAGE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SAGE_PROFILE" "$nv" > "$SAGE_CACHE/BUILD_INFO.txt"
    add_change "Built SageAttention $SAGE_LINE from pinned commit $PIN_SAGE for SM$SM; build cached in $SAGE_CACHE"
    ok "SageAttention $SAGE_LINE built and cached: $(basename "$SAGE_WHEEL")"
    return 0
}
get_sage_wheel(){
    local w
    SAGE_WHEEL=""
    w="$(find "$SAGE_CACHE" -maxdepth 1 -name 'sageattention-*.whl' 2>/dev/null | head -n 1)"
    if [ -n "$w" ]; then
        if [ -f "$w.sha256" ] && [ "$(sha256_of "$w")" = "$(cat "$w.sha256")" ]; then
            ok "Using the SageAttention $SAGE_LINE build cached for this profile (SHA-256 verified): $(basename "$w")"
            SAGE_WHEEL="$w"; return 0
        fi
        warn 'The cached SageAttention build failed its SHA-256 check. It is moved to the snapshot folder and built again.'
        mkdir -p "$STATE_ROOT/moved_cache"; mv "$SAGE_CACHE" "$STATE_ROOT/moved_cache/"
        add_change "Moved a damaged SageAttention cache to $STATE_ROOT/moved_cache"
    fi
    if [ "$H3_BUILD_SAGEATTENTION" != "1" ]; then
        SPEED_ABORT="no SageAttention $SAGE_LINE build is cached for this profile and H3_BUILD_SAGEATTENTION=0"; return 1
    fi
    build_sage_wheel
}
ensure_sage(){
    local v="$PF_sageattention" major rc
    if [ -z "$v" ]; then
        info 'SageAttention is not installed yet.'
    else
        major="${v%%.*}"
        if [ "$major" = "0" ] || [ "$major" = "1" ]; then
            info "SageAttention $v (version 1, the PyPI package) cannot run this workflow's MEM-EFF SAGE nodes. It is replaced by the $SAGE_LINE build."
        elif test_sage_stack; then
            ok "Existing SageAttention $v passed its CUDA test and the Mem-Eff kernel check; preserving it."
            return 0
        else
            info "Existing SageAttention $v did not pass ($SAGE_TEST_ERR). The usual cause is a PyTorch change underneath it. It is replaced by the $SAGE_LINE build for this pod."
        fi
    fi
    get_sage_wheel || return 1
    "$PYTHON" -m pip install --disable-pip-version-check --force-reinstall --no-deps "$SAGE_WHEEL"
    rc=$?
    if [ "$rc" != "0" ]; then SPEED_ABORT='SageAttention installation failed'; return 1; fi
    add_change "Installed SageAttention $SAGE_LINE ($(basename "$SAGE_WHEEL")) with --no-deps${v:+, replacing $v}"
    return 0
}

if [ -n "$SPEED_BLOCK" ]; then
    SPEED_NOTE="not installed: $SPEED_BLOCK"
    warn "Speed dependencies skipped: $SPEED_BLOCK."
else
    echo "Profile      : Python $PF_python / Torch $PF_torch / CUDA $PF_cuda / SM$SM"
    echo "Targets      : Triton as shipped with PyTorch ; SageAttention $SAGE_LINE"
    # -- Triton: on Linux it is part of the PyTorch install and is never changed here --
    if [ -z "$PF_triton" ]; then
        SPEED_ABORT="the 'triton' package is missing. On Linux it ships with PyTorch; this installer never installs or replaces it"
    else
        ok "Triton $PF_triton (installed with PyTorch) is present; preserving it."
    fi
    [ -z "$SPEED_ABORT" ] && ensure_jit_toolchain
    if [ -z "$SPEED_ABORT" ]; then
        if run_check "$H_TRITON_TEST" 240 triton-jit-test TRITON_JIT_OK; then ok 'Triton CUDA JIT smoke test passed.'
        else SPEED_ABORT='Triton CUDA JIT smoke test failed (see triton-jit-test.txt)'; fi
    fi
    [ -z "$SPEED_ABORT" ] && ensure_sage
    if [ -z "$SPEED_ABORT" ]; then
        SAGE_TEST_ERR=""
        test_sage_stack || SPEED_ABORT="$SAGE_TEST_ERR"
    fi
    if [ -n "$SPEED_ABORT" ]; then
        SPEED_NOTE="not ready: $SPEED_ABORT"; warn "Speed dependencies: $SPEED_ABORT."
    else
        SPEED_READY=1
        SPEED_NOTE='Triton JIT + SageAttention CUDA + Mem-Eff kernel tests passed'
        ok 'Triton JIT, SageAttention CUDA and Mem-Eff kernel tests passed.'
        # KJNodes asks nvcc for the CUDA version when it loads; ComfyUI must be able to find it.
        if ! command -v nvcc >/dev/null 2>&1; then
            warn "nvcc is not on PATH. KJNodes reads the CUDA version from it when ComfyUI starts; if KJNodes then fails to load, start ComfyUI with /usr/local/cuda/bin on PATH."
        fi
    fi
fi
add_summary "Speed dependencies: $SPEED_NOTE"

# =============================================================================================
step '4/6  Model check (read-only: nothing is downloaded, moved or renamed)'
MODEL_TSV="$STATE_ROOT/model-check.tsv"
UNFINISHED_TSV="$STATE_ROOT/unfinished-downloads.tsv"
if ! run_py "$H_MODELCHECK" 600 "$STATE_ROOT/model-check.txt" "$MODELS" "$MODEL_TSV" "$UNFINISHED_TSV"; then
    warn 'The model check could not run (see model-check.txt). Nothing was changed.'
    : > "$MODEL_TSV"; : > "$UNFINISHED_TSV"
fi
declare -A MODEL_STATE=()
MISSING_REQUIRED=(); DAMAGED=(); MISSING_OPTIONAL=0; UPSCALER_NAME=""; UPSCALER_STATE=""
while IFS=$'\x1f' read -r m_label m_state m_folder m_name m_detail m_req; do
    [ -n "$m_label" ] || continue
    MODEL_STATE["$m_label"]="$m_state"
    if [ "$m_state" = "OK" ]; then col="$C_GREEN"; elif [ "$m_state" = "MISSING" ] && [ "$m_req" != "1" ]; then col="$C_YELLOW"; else col="$C_RED"; fi
    if [ -n "$m_detail" ]; then tail_txt="- $m_detail"; elif [ "$m_req" = "1" ]; then tail_txt='(required)'; else tail_txt='(optional)'; fi
    printf '%s  [%-7s] %-34s  %s/%s  %s%s\n' "$col" "$m_state" "$m_label" "$m_folder" "$m_name" "$tail_txt" "$C_OFF"
    add_summary "MODEL [$m_state] $m_label: $m_folder/$m_name $m_detail"
    if [ "$m_req" = "1" ] && [ "$m_state" != "OK" ]; then MISSING_REQUIRED+=("$m_name"); fi
    [ "$m_state" = "DAMAGED" ] && DAMAGED+=("$m_name")
    if [ "$m_req" != "1" ] && [ "$m_state" = "MISSING" ]; then MISSING_OPTIONAL=$((MISSING_OPTIONAL + 1)); fi
    case "$m_label" in 'Latent upscaler'*) UPSCALER_NAME="$m_name"; UPSCALER_STATE="$m_state" ;; esac
done < "$MODEL_TSV"
model_ok(){ [ "${MODEL_STATE[$1]:-}" = "OK" ]; }
echo
if [ "${#MISSING_REQUIRED[@]}" -eq 0 ] && [ "${#DAMAGED[@]}" -eq 0 ] && [ -s "$MODEL_TSV" ]; then ok 'All four required model files are present and complete.'; fi
[ "${#MISSING_REQUIRED[@]}" -gt 0 ] && warn "Required model file(s) not ready: ${MISSING_REQUIRED[*]}. Download them by hand: see MODEL_DOWNLOAD_COMMANDS_RUNPOD.txt and H3_Reference_Director_01_v2.0_MODELS.pdf."
[ "${#DAMAGED[@]}" -gt 0 ] && warn "Damaged or incomplete model file(s): ${DAMAGED[*]}. Delete them and download them again."
[ "$MISSING_OPTIONAL" -gt 0 ] && info "$MISSING_OPTIONAL optional file(s) are not installed. Each belongs to an optional feature; the MODELS PDF lists them."
if [ "$UPSCALER_STATE" = "OK" ] && [ "$(basename "$UPSCALER_NAME")" != 'minimax_h3_latent_upscaler_3d_conv_v1_fp16.safetensors' ]; then
    info "Your upscaler file has its older name ($UPSCALER_NAME). It is the same model. On the node 'UPSCALE 2', pick it once in the model_name list."
fi

# =============================================================================================
step '5/6  Preservation audit (nothing protected may have changed)'
sha256sum "${CORE_HASH_FILES[@]}" > "$STATE_ROOT/comfy-core-hashes-after.txt"
if ! cmp -s "$STATE_ROOT/comfy-core-hashes-before.txt" "$STATE_ROOT/comfy-core-hashes-after.txt"; then
    fail 'Critical ComfyUI core files changed during installation. This should never happen. Compare the before/after hash files in the snapshot folder.'
fi
ok 'ComfyUI core files are byte-identical before/after.'
for v in torch cuda numpy torchvision torchaudio triton; do printf -v "PP_$v" '%s' ''; done
if ! run_py "$H_POSTPROBE" 120 "$STATE_ROOT/post-install-probe.txt" || ! printf '%s' "$PY_OUT" | grep -q '^PP_torch='; then
    fail 'Post-install probe failed: PyTorch no longer imports. Use pip-freeze-before.txt in the snapshot folder to restore your environment.'
fi
eval "$(printf '%s\n' "$PY_OUT" | grep -E '^PP_[a-z]+=')"
for k in torch cuda numpy torchvision torchaudio triton; do
    before_var="PF_$k"; after_var="PP_$k"
    if [ "${!before_var}" != "${!after_var}" ]; then
        fail "Protected package '$k' changed from '${!before_var}' to '${!after_var}'. This should never happen. pip-freeze-before.txt in the snapshot folder lists the original versions."
    fi
done
ok "PyTorch $PP_torch, CUDA $PP_cuda, NumPy $PP_numpy, Triton $PP_triton, torchvision and torchaudio are unchanged."
"$PYTHON" -m pip freeze --disable-pip-version-check > "$STATE_ROOT/pip-freeze-after.txt" 2>&1
ls -1 "$CUSTOM_NODES" > "$STATE_ROOT/custom-nodes-after.txt" 2>/dev/null

# =============================================================================================
step '6/6  Capability report'
report_line(){
    local name="$1" okv="$2" detail="$3" tag col
    if [ "$okv" = "1" ]; then tag='READY  '; col="$C_GREEN"; else tag='MISSING'; col="$C_YELLOW"; fi
    printf '%s  [%s] %-34s  %s%s\n' "$col" "$tag" "$name" "$detail" "$C_OFF"
    add_summary "[${tag// /}] $name $detail"
}
b(){ if "$@"; then echo 1; else echo 0; fi; }
EXACT_OK=0
mapfile -t EXACT_NOW < <(get_node_folders 'ComfyUI-H3-ExactMasterMemory*')
if [ "${#EXACT_NOW[@]}" -eq 1 ] && [ -n "$EXACT_PATH" ] && test_exact "$EXACT_PATH"; then EXACT_OK=1; fi
NODES_OK=0
if [ "$EXACT_OK" = "1" ] && [ -n "$MULTISHOT" ] && [ -n "$KJ_TARGET" ] && test_kj_required "$KJ_TARGET" && [ -n "$FBC" ]; then NODES_OK=1; fi
echo
report_line 'Workflow 01 v2 custom nodes' "$NODES_OK" 'Multishot, ExactMasterMemory 0.10.1, KJNodes, FirstBlockCache'
report_line 'Required models' "$([ "${#MISSING_REQUIRED[@]}" -eq 0 ] && [ -s "$MODEL_TSV" ] && echo 1 || echo 0)" 'Singularity, Qwen3-VL, video VAE, audio VAE (downloaded by hand)'
report_line 'Sage attention (default speed path)' "$SPEED_READY" "$SPEED_NOTE"
if [ "$HQ_CORE_OK" = "1" ]; then report_line 'Refine groups: ComfyUI core support' 1 'audio-video noise masks (Groups 06, 07, 08)'
else report_line 'Refine groups: ComfyUI core support' 0 'needs ComfyUI 0.34+: Manager > Update ComfyUI, restart, run this again'; fi
report_line 'Latent upscale: node pack' "$([ -n "$LBH" ] && echo 1 || echo 0)" 'LBH latent upscaler'
report_line 'Latent upscale: model' "$(b model_ok 'Latent upscaler model (Group 07)')" 'latent_upscale_models'
report_line 'Motion refine: node pack' "$([ -n "$MAI" ] && echo 1 || echo 0)" 'ComfyUI-MAINodes'
if [ -n "$PF_torchaudio" ]; then report_line 'Motion refine: torchaudio' 1 "torchaudio $PF_torchaudio"
else report_line 'Motion refine: torchaudio' 0 'not installed; this installer never installs it (it must match your PyTorch)'; fi
report_line 'Face refine: node pack' "$([ -n "$FACE_REFINE" ] && echo 1 || echo 0)" 'ComfyUI-H3-FaceRefine'
report_line 'Face refine: Python packages' "$([ "$FACE_ultralytics" = 1 ] && [ "$FACE_scenedetect" = 1 ] && echo 1 || echo 0)" 'ultralytics + scenedetect'
report_line 'Face refine: detector model' "$(b model_ok 'Face detector (Group 08)')" 'ultralytics/bbox/face_yolov8m.pt'
report_line 'Live preview (ON by default): KJNodes' "$PREVIEW_KJ" 'KJNodes with MiniMax H3 preview'
report_line 'Live preview: taeh3 decoder' "$(b model_ok 'Live preview decoder')" 'vae_approx/taeh3.safetensors (downloaded automatically when missing)'
if [ "$PREVIEW_KJ" != "1" ] || ! model_ok 'Live preview decoder'; then
    echo
    echo "${C_YELLOW}Live preview is ON in the workflow but is not ready on this pod (see the lines above).${C_OFF}"
    echo "${C_YELLOW}Run this installer again, or select the node LIVE PREVIEW in Group 04 and press Ctrl+B to switch the preview off.${C_OFF}"
    add_summary 'NOTE: live preview is ON by default but not ready. Run the installer again or bypass the LIVE PREVIEW node.'
fi
for lab in 'Turbo 8-step LoRA' 'Turbo 4-step LoRA' 'LoRA: fal Realism People' 'LoRA: Motion Continuity Repair' 'LoRA: Spatial Physics' 'LoRA: LMS Sharpness'; do
    report_line "$lab" "$(b model_ok "$lab")" 'optional, loras folder'
done
if [ "${#DAMAGED[@]}" -eq 0 ]; then report_line 'No damaged model files' 1 'every file found is complete'
else report_line 'No damaged model files' 0 "${#DAMAGED[@]} file(s) need to be downloaded again"; fi
UNFINISHED_COUNT="$(grep -c . "$UNFINISHED_TSV" 2>/dev/null || true)"; UNFINISHED_COUNT="${UNFINISHED_COUNT:-0}"
if [ "$UNFINISHED_COUNT" = "0" ]; then report_line 'No unfinished downloads' 1 'no .part files in the model folders'
else
    report_line 'No unfinished downloads' 0 "$UNFINISHED_COUNT file(s) still end in .part"
    echo
    echo "${C_YELLOW}These downloads are not finished. Never rename them by hand: delete them and download the file again.${C_OFF}"
    while IFS=$'\x1f' read -r u_path u_size; do
        [ -n "$u_path" ] || continue
        echo "  $u_path  ($u_size)"; add_summary "UNFINISHED: $u_path"
    done < "$UNFINISHED_TSV"
fi
if [ "$SPEED_READY" != "1" ]; then
    echo
    echo "${C_YELLOW}Sage is not ready on this pod. Workflow 01 v2 still runs, only slower:${C_OFF}"
    echo "${C_YELLOW}open Group 09 (ENGINE), select the six nodes with SAGE in their title and press Ctrl+B to bypass them.${C_OFF}"
    add_summary 'NOTE: bypass every node with SAGE in its title (Ctrl+B) because the speed stack is not ready on this pod.'
fi
[ "${#CHANGES[@]}" -eq 0 ] && add_summary 'No changes were needed.'
add_summary 'ComfyUI core, PyTorch, CUDA, Triton, NumPy, ComfyUI-Manager and workflow files were not modified by this installer.'

if [ "$REQUIRED_FAILED" = "1" ] || [ "$NODES_OK" != "1" ]; then
    add_summary 'RESULT: INCOMPLETE - a required item needs attention (see above).'
    save_summary
    echo
    echo "${C_YELLOW}$RULE${C_OFF}"
    echo "${C_YELLOW} INCOMPLETE - a REQUIRED item needs attention. Read the [WARN] lines above.${C_OFF}"
    echo "${C_YELLOW}$RULE${C_OFF}"
    echo "Snapshot/log: $STATE_ROOT"
    echo 'It is safe to run this installer again: finished items are skipped.'
    finish 2
fi
add_summary 'RESULT: SUCCESS'
save_summary
echo
echo "${C_GREEN}$RULE${C_OFF}"
if [ "${#MISSING_REQUIRED[@]}" -gt 0 ] || [ "${#DAMAGED[@]}" -gt 0 ] || [ ! -s "$MODEL_TSV" ]; then
    echo "${C_GREEN} SUCCESS - NODES AND DEPENDENCIES ARE READY. MODEL FILES STILL NEED ATTENTION.${C_OFF}"
else
    echo "${C_GREEN} SUCCESS - WORKFLOW 01 v2 IS READY${C_OFF}"
fi
echo "${C_GREEN}$RULE${C_OFF}"
echo "Snapshot/log: $STATE_ROOT"
echo '1. Restart ComfyUI so it loads the new nodes:'
echo '   ComfyUI Manager > Restart, or restart the Pod in the RunPod console.'
echo '2. Open ComfyUI (port 8188), load H3_Reference_Director_01_v2.0.json and read the amber "V2 - START HERE" note.'
echo '3. Render once with every V2 switch at its default. That is your V1 baseline.'
finish 0
