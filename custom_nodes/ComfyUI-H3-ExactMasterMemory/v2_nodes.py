"""H3 Reference Director - Workflow 01 v2 nodes (ExactMasterMemory v0.5.0).

Node ids carry the "H3RD" (H3 Reference Director) prefix because ComfyUI-H3-Multishot
already registers a node called H3LoraStack; identical ids silently replace each other.

Everything here is ADDITIVE. No v0.4.x node changes behaviour when these nodes are
left at their defaults:

  H3RDLoraStack            six named optional LoRAs + two free slots, all OFF by default
  H3RDSpeedMode            OFF / Turbo 8-step / Turbo 4-step (LoRA + steps + sampler)
  H3RDCacheRoute           uses FirstBlockCache only when Speed Mode is OFF
  H3RDHQGate               one switch for the whole HQ pass (blocks it silently when off)
  H3RDHQPass2Latent        upscaled video + untouched audio -> joint latent, audio locked
  H3RDHQPass2Conditioning  rebuilds picture references at the HQ canvas, drops motion video
  H3RDVideo1Route          Video 1 as soft reference or as ControlNet control video (v0.6.0)
  H3RDFaceGate             one switch + source choice for the face-refine branch (v0.6.0)
  H3RDFaceAudioLock        reuses and locks the pass-1 audio latent for the face crop (v0.6.0)
"""
from __future__ import annotations

import math
import os

# --------------------------------------------------------------------------------------
# LoRA helpers
# --------------------------------------------------------------------------------------

# slot key -> (label, exact filenames, fallback substring sets, trigger words, default strength)
_LORA_SLOTS = [
    ("realism_people", "fal Realism People",
     ["h3-realism-people-t2v-i2v-r2v.safetensors"],
     [("realism-people",), ("realism_people",), ("realism", "people")],
     "r34l1sm", 1.0),
    # v0.6.1: real file names are Motion_Repair_V2 (newest) and Motion_Repair.
    ("motion_continuity", "Motion Continuity Repair",
     ["Motion_Repair_V2.safetensors", "Motion_Repair.safetensors"],
     [("motion_repair",), ("motion", "repair"), ("continuity", "repair"), ("motion", "continuity"), ("continuity",)],
     "", 0.9),
    # v0.6.1: author names clean_3000_pruned as the newest; recommends 0.3-0.5. Object physics only.
    ("spatial_physics", "Spatial Physics",
     ["wushu_spatial_physics_clean_3000_pruned.safetensors",
      "wushu_spatial_physics_v2_1000_pruned.safetensors"],
     [("spatial", "physics"), ("spatial-physics",), ("physics",)],
     "", 0.4),
    # Author's design: a second-pass sharpener that receives the finished video through
    # MiniMaxH3AddGuide. In a plain LoRA stack it runs WITHOUT that guide.
    ("lms_sharpness", "LMS Sharpness",
     ["minimax_h3_lms_v1.0_r64.safetensors", "minimax_h3_lms_v1.0_r64_r.safetensors"],
     [("minimax_h3_lms",), ("lms", "r64"), ("_lms_",)],
     "", 0.8),
]

_LORA_PAGES = {
    "realism_people": "https://huggingface.co/fal/MiniMax-H3-Realism-People-LoRA",
    "motion_continuity": "https://huggingface.co/JOKER141/MiniMax-H3-General-Motion-Continuity-Repair",
    "spatial_physics": "https://huggingface.co/Jojocodex/minimax-h3-spatial-physics-lora",
    "lms_sharpness": "https://huggingface.co/Alissonerdx/Minimax-H3-ComfyUI",
}

_TURBO = {
    "8": (["minimax_h3_ref2v_turbo_8step_v1.0_768p_comfyui_bf16.safetensors"],
          [("ref2v", "turbo", "8step"), ("ref2v", "8step"), ("ref2va", "8step")]),
    "4": (["minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors"],
          [("ref2v", "turbo", "4step"), ("ref2v", "4step"), ("ref2va", "4step")]),
}

AUTO_DETECT = "auto-detect"

_LORA_CACHE: dict = {}
_LORA_CACHE_MAX = 6


def _lora_files():
    import folder_paths
    try:
        return list(folder_paths.get_filename_list("loras"))
    except Exception:
        return []


def _find_lora(exact_names, pattern_sets, prefer=("comfyui", "pruned")):
    """Return the loras-folder relative name of the best match, or None.

    Exact filename first (any subfolder), then the first substring set that matches
    anything. Ties prefer names containing the `prefer` words, then the shortest name.
    """
    files = _lora_files()
    base = {f: os.path.basename(f).lower() for f in files}
    for name in exact_names:
        for f, b in base.items():
            if b == name.lower():
                return f
    for pats in pattern_sets:
        cands = [f for f, b in base.items() if all(p in b for p in pats)]
        if cands:
            def rank(f):
                b = base[f]
                return (-sum(1 for w in prefer if w in b), len(b), b)
            return sorted(cands, key=rank)[0]
    return None


def _lora_path(name):
    import folder_paths
    getter = getattr(folder_paths, "get_full_path_or_raise", None)
    if getter is not None:
        return getter("loras", name)
    path = folder_paths.get_full_path("loras", name)
    if path is None:
        raise FileNotFoundError(f"LoRA file not found in models/loras: {name}")
    return path


def _apply_lora(model, name, strength):
    """Model-only LoRA patch, the same call core LoraLoaderModelOnly makes."""
    import comfy.sd
    import comfy.utils

    if float(strength) == 0.0:
        return model
    path = _lora_path(name)
    key = (path, os.path.getmtime(path))
    lora = _LORA_CACHE.get(key)
    if lora is None:
        lora = comfy.utils.load_torch_file(path, safe_load=True)
        if len(_LORA_CACHE) >= _LORA_CACHE_MAX:
            _LORA_CACHE.pop(next(iter(_LORA_CACHE)))
        _LORA_CACHE[key] = lora
    patched, _ = comfy.sd.load_lora_for_models(model, None, lora, float(strength), 0.0)
    return patched


def _missing(policy, what, hint):
    msg = (f"{what} is switched ON but its file was not found in ComfyUI/models/loras. "
           f"{hint} Switch it OFF, or install the file and press 'R' to refresh ComfyUI.")
    if policy == "error":
        raise FileNotFoundError(msg)
    print("[H3 v2] WARNING: " + msg + " -> skipped.", flush=True)


class H3RDLoraStack:
    """Six named optional LoRAs plus two free slots. Everything is OFF by default."""

    @classmethod
    def INPUT_TYPES(cls):
        names = ["none"] + _lora_files()
        picks = [AUTO_DETECT] + _lora_files()
        required = {"model": ("MODEL",)}
        for key, label, _exact, _pats, _trig, strength in _LORA_SLOTS:
            required[key] = ("BOOLEAN", {
                "default": False,
                "tooltip": f"Switch the {label} LoRA on or off. The file is found automatically "
                           "in models/loras by its name."})
            required[key + "_strength"] = ("FLOAT", {
                "default": strength, "min": -2.0, "max": 2.0, "step": 0.05,
                "tooltip": f"Strength of {label}. Test in small steps with a fixed seed."})
            required[key + "_file"] = (picks, {
                "default": AUTO_DETECT,
                "tooltip": f"Which file to load for {label}. '{AUTO_DETECT}' finds it by its known names. "
                           "If your file has a different name, pick it here from your models/loras folder."})
        required["custom_lora_1"] = (names, {"default": "none"})
        required["custom_lora_1_strength"] = ("FLOAT", {"default": 1.0, "min": -2.0, "max": 2.0, "step": 0.05})
        required["custom_lora_2"] = (names, {"default": "none"})
        required["custom_lora_2_strength"] = ("FLOAT", {"default": 1.0, "min": -2.0, "max": 2.0, "step": 0.05})
        required["extra_trigger_words"] = ("STRING", {
            "default": "", "multiline": False,
            "tooltip": "Trigger words for the custom slots (comma separated). Leave empty if none."})
        required["auto_trigger_words"] = ("BOOLEAN", {
            "default": True,
            "tooltip": "Adds the trigger words of the LoRAs that are ON to the front of the prompt "
                       "(through trigger_prefix -> prompt_prefix on the Semantic Reference node)."})
        required["missing_file"] = (["error", "skip_with_warning"], {
            "default": "error",
            "tooltip": "What to do when a switched-on LoRA file is not installed. 'error' stops with a "
                       "clear message so a test is never silently run without the LoRA."})
        return {"required": required}

    RETURN_TYPES = ("MODEL", "STRING", "STRING")
    RETURN_NAMES = ("model", "trigger_prefix", "report")
    FUNCTION = "apply"
    CATEGORY = "MiniMax H3 / Workflow UI"
    DESCRIPTION = ("Optional look / motion LoRAs for MiniMax H3 with one switch each. "
                   "All OFF = the model passes through untouched.")

    def apply(self, model, missing_file="error", auto_trigger_words=True,
              extra_trigger_words="", custom_lora_1="none", custom_lora_1_strength=1.0,
              custom_lora_2="none", custom_lora_2_strength=1.0, **kw):
        out = model
        lines, triggers = [], []
        for key, label, exact, pats, trigger, _default in _LORA_SLOTS:
            if not kw.get(key, False):
                continue
            strength = float(kw.get(key + "_strength", 1.0))
            picked = kw.get(key + "_file", AUTO_DETECT)
            manual = bool(picked) and picked not in (AUTO_DETECT, "none")
            name = picked if manual else _find_lora(exact, pats)
            if name is None:
                hint = ("Expected " + (" or ".join(exact) if exact else
                                       "a file named like *" + "*".join(pats[0]) + "*.safetensors") +
                        " (any subfolder). Download page: " + _LORA_PAGES.get(key, "-") +
                        ". If the file is there under another name, pick it in the '" + key + "_file' list.")
                _missing(missing_file, f"LoRA '{label}'", hint)
                lines.append(f"{label}: ON but file missing -> skipped")
                continue
            out = _apply_lora(out, name, strength)
            lines.append(f"{label}: ON  strength {strength:g}  file {name}" + ("  (picked by hand)" if manual else ""))
            if trigger:
                triggers.append(trigger)
        for slot, name, strength in (("custom 1", custom_lora_1, custom_lora_1_strength),
                                     ("custom 2", custom_lora_2, custom_lora_2_strength)):
            if name and name != "none":
                out = _apply_lora(out, name, float(strength))
                lines.append(f"{slot}: ON  strength {float(strength):g}  file {name}")
        extra = [t.strip() for t in (extra_trigger_words or "").split(",") if t.strip()]
        prefix = ", ".join(triggers + extra) if auto_trigger_words else ", ".join(extra)
        report = "\n".join(lines) if lines else "All LoRAs OFF - model unchanged."
        print("[H3RDLoraStack]\n" + report + (f"\ntrigger prefix: {prefix}" if prefix else ""), flush=True)
        return out, prefix, report


# --------------------------------------------------------------------------------------
# Speed mode
# --------------------------------------------------------------------------------------

SPEED_MODES = [
    "OFF - full quality",
    "TURBO 8-step - Ref2V v1.0 768p LoRA",
    "TURBO 4-step - Ref2V v0.1 LoRA",
]


class H3RDSpeedMode:
    """One switch for the turbo LoRAs. OFF reproduces the v1 sampling path exactly."""

    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {
            "model": ("MODEL",),
            "base_sampler": ("SAMPLER", {"tooltip": "The normal sampler (KSamplerSelect). Used when Speed Mode is OFF."}),
            "speed_mode": (SPEED_MODES, {"default": SPEED_MODES[0]}),
            "steps": ("INT", {
                "default": 0, "min": 0, "max": 100, "step": 1,
                "tooltip": "Steps for the selected mode. Changing the mode fills in that mode's own count: "
                           "20 (OFF), 8 (TURBO 8-step), 4 (TURBO 4-step). Type any other number to use it with "
                           "the same mode, for example 8 with TURBO 4-step. 0 = use the mode's own count."}),
            "turbo_strength": ("FLOAT", {"default": 1.0, "min": 0.0, "max": 2.0, "step": 0.05}),
            "turbo_sampler": (["euler", "base_sampler"], {
                "default": "euler",
                "tooltip": "Sampler used in the turbo modes. The LoRA authors recommend Euler."}),
            "missing_file": (["error", "skip_with_warning"], {"default": "error"}),
        }}

    RETURN_TYPES = ("MODEL", "INT", "SAMPLER", "BOOLEAN", "STRING")
    RETURN_NAMES = ("model", "steps", "sampler", "use_cache", "info")
    FUNCTION = "route"
    CATEGORY = "MiniMax H3 / Workflow UI"
    DESCRIPTION = ("OFF: model and sampler pass through. TURBO: applies the matching Ref2V turbo LoRA, "
                   "switches to Euler and tells H3 Cache Route to skip FirstBlockCache. In every mode the "
                   "step count is the 'steps' value; 0 means the mode's own count (20 / 8 / 4).")

    MODE_STEPS = {"OFF": 20, "8": 8, "4": 4}

    def route(self, model, base_sampler, speed_mode, steps=0, turbo_strength=1.0,
              turbo_sampler="euler", missing_file="error", **legacy):
        # workflows saved with v0.8.1 or older send final_steps / turbo_steps instead of steps
        manual = int(steps or 0)
        if manual <= 0 and legacy:
            manual = int(legacy.get("final_steps") or 0) if speed_mode.startswith("OFF") else int(legacy.get("turbo_steps") or 0)

        if speed_mode.startswith("OFF"):
            n = manual if manual > 0 else self.MODE_STEPS["OFF"]
            info = f"Speed Mode OFF: {n} steps ({'set by hand' if manual > 0 else 'mode default'}), base sampler, FirstBlockCache allowed."
            print("[H3RDSpeedMode] " + info, flush=True)
            return model, n, base_sampler, True, info

        which = "8" if "8-step" in speed_mode else "4"
        exact, pats = _TURBO[which]
        name = _find_lora(exact, pats)
        if name is None:
            _missing(missing_file, f"Turbo {which}-step", f"Expected: {exact[0]}.")
            n = self.MODE_STEPS["OFF"]
            info = f"Turbo {which}-step LoRA missing -> fell back to OFF: {n} steps, base sampler."
            print("[H3RDSpeedMode] " + info, flush=True)
            return model, n, base_sampler, True, info

        patched = _apply_lora(model, name, float(turbo_strength))
        sampler = base_sampler
        if turbo_sampler == "euler":
            import comfy.samplers
            sampler = comfy.samplers.sampler_object("euler")
        n = manual if manual > 0 else self.MODE_STEPS[which]
        info = (f"TURBO {which}-step: LoRA {name} @ {float(turbo_strength):g}, {n} steps "
                f"({'set by hand' if manual > 0 else 'mode default'}), sampler {turbo_sampler}, FirstBlockCache skipped.")
        print("[H3RDSpeedMode] " + info, flush=True)
        return patched, n, sampler, False, info


class H3RDCacheRoute:
    """Pick the FirstBlockCache model only when Speed Mode allows caching."""

    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {
            "model_no_cache": ("MODEL",),
            "model_cached": ("MODEL",),
            "use_cache": ("BOOLEAN", {"forceInput": True}),
        }}

    RETURN_TYPES = ("MODEL",)
    RETURN_NAMES = ("model",)
    FUNCTION = "route"
    CATEGORY = "MiniMax H3 / Workflow UI"
    DESCRIPTION = ("Turbo LoRAs and step caching do not combine: with only 4-8 steps there is "
                   "nothing safe to skip. This routes around FirstBlockCache in the turbo modes.")

    def route(self, model_no_cache, model_cached, use_cache):
        print(f"[H3RDCacheRoute] FirstBlockCache {'ON' if use_cache else 'SKIPPED (turbo mode)'}", flush=True)
        return (model_cached if use_cache else model_no_cache,)


# --------------------------------------------------------------------------------------
# HQ pass (latent upscale + low-noise refinement)
# --------------------------------------------------------------------------------------

def _blocker():
    try:
        from comfy_execution.graph_utils import ExecutionBlocker
    except Exception:  # pragma: no cover - very old cores
        from comfy_execution.graph import ExecutionBlocker
    return ExecutionBlocker(None)


def _streams(latent, label):
    samples = latent.get("samples") if isinstance(latent, dict) else None
    if samples is None:
        raise ValueError(f"{label}: expected a LATENT with 'samples'.")
    if getattr(samples, "is_nested", False):
        return list(samples.unbind())
    return [samples]


class H3RDHQGate:
    """One switch for the whole latent-upscale group, and the choice of what it upscales."""

    SOURCES = ["normal video", "motion-refined video (needs the motion group ON)"]

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "enable_upscale": ("BOOLEAN", {
                    "default": False,
                    "tooltip": "OFF: the upscale group is skipped silently and only the normal video is saved. "
                               "ON: the finished video is upscaled in latent space, refined and saved as a second video."}),
                "source": (cls.SOURCES, {
                    "default": cls.SOURCES[0],
                    "tooltip": "What to upscale. 'motion-refined video' only produces a result when the motion "
                               "refine group is switched on as well."}),
                "latent": ("LATENT", {"tooltip": "The finished pass-1 H3 audio-video latent."}),
            },
            "optional": {
                "motion_refined_video": ("LATENT", {"lazy": True,
                                                    "tooltip": "Video-only latent of the motion-refined frames (VAE Encode)."}),
            },
        }

    RETURN_TYPES = ("LATENT", "LATENT")
    RETURN_NAMES = ("video_latent", "av_latent")
    FUNCTION = "gate"
    CATEGORY = "MiniMax H3 / Workflow UI"
    DESCRIPTION = ("Splits the finished H3 latent into its video part (for the latent upscaler) "
                   "and passes the joint latent on. When switched OFF every node after it is "
                   "skipped without an error.")

    def check_lazy_status(self, enable_upscale, source, latent=None, motion_refined_video=None, lms_latent=None):
        if enable_upscale and str(source).startswith("motion") and motion_refined_video is None:
            return ["motion_refined_video"]
        if enable_upscale and str(source).startswith("LMS") and lms_latent is None:
            return ["lms_latent"]
        return []

    def gate(self, enable_upscale, source, latent, motion_refined_video=None, lms_latent=None):
        if not enable_upscale:
            b = _blocker()
            print("[H3 Upscale Gate] upscale OFF - group skipped.", flush=True)
            return b, b
        parts = _streams(latent, "H3 Upscale Gate")
        if len(parts) < 2 or parts[0].ndim != 5 or parts[0].shape[1] != 24:
            raise ValueError("H3 Upscale Gate: expected a joint MiniMax H3 audio-video latent "
                             "(video [B,24,T,h,w] + audio).")
        video = parts[0]
        other = None
        if str(source).startswith("motion"):
            other, what = motion_refined_video, "motion-refined"
        elif str(source).startswith("LMS"):
            other, what = lms_latent, "LMS-sharpened"
        if str(source).startswith(("motion", "LMS")):
            if other is None:
                raise ValueError(f"H3 Upscale Gate: the {what} video is selected but its group gave nothing. "
                                 "Switch that group on, or choose 'normal video'.")
            import comfy.nested_tensor
            mv = _streams(other, what + " latent")[0]
            if mv.ndim != 5 or mv.shape[1] != 24 or tuple(mv.shape[2:]) != tuple(video.shape[2:]):
                raise ValueError(f"H3 Upscale Gate: the {what} latent {tuple(mv.shape)} does not match the "
                                 f"normal video latent {tuple(video.shape)}.")
            video = mv.to(device=video.device, dtype=video.dtype)
            latent = dict(latent)
            latent["samples"] = comfy.nested_tensor.NestedTensor((video, parts[1]))
            latent.pop("noise_mask", None)
        print(f"[H3 Upscale Gate] upscale ON - source '{source}', video latent {tuple(video.shape)} "
              f"({video.shape[4] * 16}x{video.shape[3] * 16}px).", flush=True)
        return {"samples": video}, latent


class H3RDHQPass2Latent:
    """Rejoin the upscaled video latent with the untouched audio latent and lock the audio."""

    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {
            "upscaled_video": ("LATENT", {"tooltip": "Video-only latent from the H3 latent upscaler."}),
            "av_latent": ("LATENT", {"tooltip": "av_latent output of H3 HQ Gate (pass-1 video + audio)."}),
        }}

    RETURN_TYPES = ("LATENT", "INT", "INT", "STRING")
    RETURN_NAMES = ("latent", "width", "height", "info")
    FUNCTION = "build"
    CATEGORY = "MiniMax H3 / Workflow UI"
    DESCRIPTION = ("Builds the pass-2 latent: upscaled video + the original audio latent. The "
                   "noise mask is 1 for video and 0 for audio, so the sampler refines the picture "
                   "and returns the audio exactly as pass 1 produced it (lip-sync is preserved).")

    def build(self, upscaled_video, av_latent):
        import torch
        import comfy.nested_tensor

        up = _streams(upscaled_video, "upscaled_video")[0]
        parts = _streams(av_latent, "av_latent")
        if len(parts) < 2:
            raise ValueError("H3 HQ Pass-2 Latent: av_latent has no audio stream.")
        src_video, audio = parts[0], parts[1]
        if up.ndim != 5 or up.shape[1] != 24:
            raise ValueError(f"H3 HQ Pass-2 Latent: upscaled video must be [B,24,T,h,w], got {tuple(up.shape)}.")
        if up.shape[2] != src_video.shape[2]:
            raise ValueError("H3 HQ Pass-2 Latent: the upscaler changed the frame count "
                             f"({src_video.shape[2]} -> {up.shape[2]} latent frames). Use a spatial-only upscaler.")
        if up.shape[3] % 2 or up.shape[4] % 2:
            raise ValueError(f"H3 HQ Pass-2 Latent: upscaled size {up.shape[4] * 16}x{up.shape[3] * 16}px "
                             "is not a multiple of 32px. Keep the upscaler's align at 32.")
        video = up.to(device=src_video.device, dtype=src_video.dtype)
        b, _, t, h, w = video.shape
        samples = comfy.nested_tensor.NestedTensor((video, audio))
        mask = comfy.nested_tensor.NestedTensor((
            torch.ones((b, 1, t, h, w), dtype=torch.float32, device=video.device),
            torch.zeros((audio.shape[0], 1, audio.shape[2], audio.shape[3]),
                        dtype=torch.float32, device=audio.device),
        ))
        out = {"samples": samples, "noise_mask": mask}
        width, height = int(w * 16), int(h * 16)
        info = (f"pass-2 latent {width}x{height}px, {t} latent frames; "
                f"was {src_video.shape[4] * 16}x{src_video.shape[3] * 16}px; audio locked.")
        print("[H3RDHQPass2Latent] " + info, flush=True)
        return out, width, height, info


class H3RDHQPass2Conditioning:
    """Rebuild the native reference blocks for the HQ canvas. The text conditioning is reused."""

    PICTURE_MODES = ["rebuild_at_hq_size", "keep_pass1_size"]
    VIDEO_MODES = ["exclude_video_keep_audio", "keep_video"]

    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {
            "positive": ("CONDITIONING", {"tooltip": "The exact pass-1 conditioning (after Free Text Encoder)."}),
            "hq_ref_pack": ("H3_HQ_REFPACK", {"tooltip": "hq_ref_pack output of the Semantic Reference node."}),
            "vae": ("VAE", {"tooltip": "H3 VIDEO VAE (never the audio VAE)."}),
            "pass2_latent": ("LATENT", {"tooltip": "latent output of H3 HQ Pass-2 Latent."}),
            "picture_refs": (cls.PICTURE_MODES, {
                "default": "rebuild_at_hq_size",
                "tooltip": "rebuild: 'match'-sized picture references are re-encoded from the original "
                           "pictures at the HQ canvas size, so they carry real high-resolution detail."}),
            "motion_video_refs": (cls.VIDEO_MODES, {
                "default": "exclude_video_keep_audio",
                "tooltip": "exclude: reference-video latents are dropped in pass 2 because the latent "
                           "already contains the motion. This saves a large number of tokens."}),
        }}

    RETURN_TYPES = ("CONDITIONING", "STRING")
    RETURN_NAMES = ("positive", "info")
    FUNCTION = "rebuild"
    CATEGORY = "MiniMax H3 / Workflow UI"
    DESCRIPTION = ("Pass-2 conditioning for the HQ refinement. Prompt, tags and text encoding are "
                   "reused unchanged (no text-encoder reload); only the native reference latents are "
                   "rebuilt for the larger canvas.")

    def rebuild(self, positive, hq_ref_pack, vae, pass2_latent,
                picture_refs="rebuild_at_hq_size", motion_video_refs="exclude_video_keep_audio"):
        from comfy_extras import nodes_minimax_h3 as h3

        video = _streams(pass2_latent, "pass2_latent")[0]
        width, height = int(video.shape[4] * 16), int(video.shape[3] * 16)
        pictures = list(hq_ref_pack.get("pictures", []))
        size_mode = hq_ref_pack.get("ref_image_size", "match")
        multiple = int(getattr(h3, "CANVAS_MULTIPLE", 32))

        stats = {"pic_rebuilt": 0, "pic_kept": 0, "video_dropped": 0, "audio_kept": 0}
        out = []
        for entry in positive:
            if (not isinstance(entry, (list, tuple)) or len(entry) < 2
                    or not isinstance(entry[1], dict) or "minimax_refs" not in entry[1]):
                out.append(entry)
                continue
            meta = entry[1].copy()
            blocks = list(meta["minimax_refs"])
            n_images = sum(1 for blk in blocks if blk.get("kind") == "image")
            if picture_refs == "rebuild_at_hq_size" and n_images != len(pictures):
                raise ValueError(
                    f"H3 HQ Pass-2 Conditioning: the conditioning holds {n_images} picture reference(s) "
                    f"but hq_ref_pack holds {len(pictures)}. Connect both inputs from the same "
                    "Semantic Reference node.")
            new_blocks, pic_i = [], 0
            for blk in blocks:
                kind = blk.get("kind")
                if kind == "image":
                    src = pictures[pic_i]["image"] if pic_i < len(pictures) else None
                    pic_i += 1
                    if picture_refs != "rebuild_at_hq_size" or size_mode != "match" or src is None:
                        new_blocks.append(blk)
                        stats["pic_kept"] += 1
                        continue
                    ih, iw = int(src.shape[1]), int(src.shape[2])
                    scale = min(1.0, math.sqrt((width * height) / float(iw * ih)))
                    tw = max(multiple, round(iw * scale / multiple) * multiple)
                    th = max(multiple, round(ih * scale / multiple) * multiple)
                    if th // 16 == blk.get("latent_h") and tw // 16 == blk.get("latent_w"):
                        new_blocks.append(blk)      # source picture is already at its full size
                        stats["pic_kept"] += 1
                        continue
                    resized = h3._resize(src[:1], tw, th, "disabled")
                    new_blocks.append({"kind": "image", "latent_h": th // 16, "latent_w": tw // 16,
                                       "latent": vae.encode(resized)})
                    stats["pic_rebuilt"] += 1
                elif kind in ("video", "video_audio"):
                    if motion_video_refs == "keep_video":
                        new_blocks.append(blk)
                        continue
                    stats["video_dropped"] += 1
                    if kind == "video_audio" and blk.get("audio_latent") is not None and blk.get("ref_audio_t", 0) > 0:
                        new_blocks.append({"kind": "audio", "ref_audio_t": blk["ref_audio_t"],
                                           "audio_latent": blk["audio_latent"]})
                        stats["audio_kept"] += 1
                else:
                    new_blocks.append(blk)
                    if kind == "audio":
                        stats["audio_kept"] += 1
            meta["minimax_refs"] = new_blocks
            meta["_h3_hq_pass2"] = True
            out.append([entry[0], meta])

        info = (f"target canvas {width}x{height}px | pictures rebuilt {stats['pic_rebuilt']}, "
                f"kept {stats['pic_kept']} | reference videos dropped {stats['video_dropped']} | "
                f"audio references kept {stats['audio_kept']}")
        print("[H3RDHQPass2Conditioning] " + info, flush=True)
        return out, info


# --------------------------------------------------------------------------------------
# ControlNet on Video 1  +  face refine  (v0.6.0)
# --------------------------------------------------------------------------------------

class H3RDVideo1Route:
    """Decides what Video 1 does: soft reference (v1 behaviour) or ControlNet control video.

    The ControlNet group in the workflow ships MUTED. While it is muted nothing arrives on
    `controlled_model`, so this node passes the model and Video 1 straight through and the
    workflow behaves exactly as before. When the group is switched on, the ControlNet model
    arrives here and Video 1 stops being a reference (unless you choose otherwise).
    """

    MODES = ["control_only", "control_and_reference"]

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "model": ("MODEL", {"tooltip": "The normal model chain (after Sage / live preview)."}),
                "video1_when_controlnet_on": (cls.MODES, {
                    "default": "control_only",
                    "tooltip": "control_only: Video 1 drives the ControlNet and is NOT a reference, so the "
                               "prompt must not mention <Video 1>. control_and_reference: Video 1 is used "
                               "both ways; the original performer's look can leak into the result."}),
            },
            "optional": {
                "video1": ("IMAGE", {"tooltip": "Frames from the VIDEO 1 loader."}),
                "controlled_model": ("MODEL", {"tooltip": "Output of Apply MiniMax H3 Fun ControlNet. "
                                                          "Empty while the ControlNet group is muted."}),
            },
        }

    RETURN_TYPES = ("MODEL", "IMAGE", "STRING")
    RETURN_NAMES = ("model", "reference_video", "info")
    FUNCTION = "route"
    CATEGORY = "MiniMax H3 / Workflow UI"
    DESCRIPTION = ("Routes Video 1 either to the reference bank (soft motion guide) or to the "
                   "ControlNet (exact structure). Do not mute or bypass this node.")

    def route(self, model, video1_when_controlnet_on="control_only", video1=None, controlled_model=None):
        # A bypassed ControlNet node hands back the very same model object; strength 0 or a missing
        # control video does too. Only a real patched clone counts as "ControlNet on".
        active = controlled_model is not None and controlled_model is not model
        if not active:
            info = "ControlNet OFF: Video 1 is a normal reference (v1 behaviour)." if video1 is not None \
                else "ControlNet OFF: no Video 1 connected."
            print("[H3RDVideo1Route] " + info, flush=True)
            return model, video1, info
        if video1_when_controlnet_on == "control_and_reference":
            info = "ControlNet ON: Video 1 drives the ControlNet AND stays a reference."
            print("[H3RDVideo1Route] " + info, flush=True)
            return controlled_model, video1, info
        info = ("ControlNet ON: Video 1 drives the ControlNet only. It is not a reference, so the prompt "
                "must not mention <Video 1>.")
        print("[H3RDVideo1Route] " + info, flush=True)
        return controlled_model, None, info


class H3RDFaceGate:
    """One switch for the face-refine group, and the choice of which video to refine."""

    SOURCES = ["normal video", "upscaled video (needs the upscale group ON)",
               "motion-refined video (needs the motion group ON)"]

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "enable_face_refine": ("BOOLEAN", {
                    "default": False,
                    "tooltip": "OFF: the face-refine group is skipped silently. ON: faces are tracked, "
                               "refined and stitched back, and another video is saved."}),
                "source": (cls.SOURCES, {
                    "default": cls.SOURCES[0],
                    "tooltip": "Which video to refine. The upscaled and motion-refined options only produce a "
                               "result when that group is switched on as well."}),
            },
            "optional": {
                "normal_images": ("IMAGE", {"lazy": True}),
                "upscaled_images": ("IMAGE", {"lazy": True}),
                "motion_images": ("IMAGE", {"lazy": True}),
            },
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("images",)
    FUNCTION = "gate"
    CATEGORY = "MiniMax H3 / Workflow UI"
    DESCRIPTION = ("Switches the face-refine group on or off and picks its source video. Only the "
                   "selected source is requested, so an unused group costs nothing.")

    @staticmethod
    def _wanted(source):
        s = str(source).lower()
        if s.startswith("upscaled") or s.startswith("hq"):
            return "upscaled_images"
        if s.startswith("motion"):
            return "motion_images"
        if s.startswith("lms"):
            return "lms_images"
        return "normal_images"

    def check_lazy_status(self, enable_face_refine, source, normal_images=None, upscaled_images=None,
                          motion_images=None, lms_images=None):
        if not enable_face_refine:
            return []
        want = self._wanted(source)
        have = {"normal_images": normal_images, "upscaled_images": upscaled_images,
                "motion_images": motion_images, "lms_images": lms_images}
        return [want] if have[want] is None else []

    def gate(self, enable_face_refine, source, normal_images=None, upscaled_images=None, motion_images=None,
             lms_images=None):
        if not enable_face_refine:
            print("[H3 Face Gate] face refine OFF - group skipped.", flush=True)
            return (_blocker(),)
        images = {"normal_images": normal_images, "upscaled_images": upscaled_images,
                  "motion_images": motion_images, "lms_images": lms_images}[self._wanted(source)]
        if images is None:
            raise ValueError("H3 Face Gate: the selected source is not connected or its group is switched off. "
                             "Switch that group on, or choose 'normal video'.")
        print(f"[H3 Face Gate] face refine ON - source '{source}', {tuple(images.shape)}.", flush=True)
        return (images,)


class H3RDFaceAudioLock:
    """Put the pass-1 audio latent into the face-crop latent and lock it, so lips stay in sync."""

    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {
            "model": ("MODEL",),
            "av_latent": ("LATENT", {"tooltip": "av_latent output of 'H3 Inject Video Latent' (the face crops)."}),
            "source_av_latent": ("LATENT", {"tooltip": "The finished pass-1 latent. Its audio stream is reused "
                                                       "as it is; nothing is re-encoded."}),
        }}

    RETURN_TYPES = ("MODEL", "LATENT", "STRING")
    RETURN_NAMES = ("model", "av_latent", "info")
    FUNCTION = "lock"
    CATEGORY = "MiniMax H3 / Workflow UI"
    DESCRIPTION = ("Replaces the empty audio stream of the face-crop latent with the audio latent that "
                   "pass 1 generated and masks it from sampling. The crop is refined while jointly attending "
                   "to the speech, which is what keeps the mouth matched to the sound.")

    def lock(self, model, av_latent, source_av_latent):
        import torch
        import torch.nn.functional as F
        import comfy.nested_tensor

        parts = _streams(av_latent, "av_latent")
        src = _streams(source_av_latent, "source_av_latent")
        if len(parts) < 2 or len(src) < 2:
            raise ValueError("H3 Face Audio Lock: both inputs must be joint MiniMax H3 audio-video latents.")
        video, template = parts[0], parts[1]
        audio = src[1].to(device=template.device, dtype=template.dtype)
        if audio.shape[0] != video.shape[0]:
            raise ValueError("H3 Face Audio Lock: batch sizes differ between the crop latent and the pass-1 latent.")
        target = int(template.shape[-1])
        if audio.shape[-1] > target:
            audio = audio[..., :target]
        elif audio.shape[-1] < target:
            audio = F.pad(audio, (0, target - audio.shape[-1]))
        locked = dict(av_latent)
        locked["samples"] = comfy.nested_tensor.NestedTensor((video, audio))
        locked["noise_mask"] = comfy.nested_tensor.NestedTensor((torch.ones_like(video), torch.zeros_like(audio)))
        patched = model.clone()
        opts = patched.model_options["transformer_options"] = \
            patched.model_options.get("transformer_options", {}).copy()
        opts["minimax_h3_lock_audio_clean"] = True
        info = (f"face crop latent {tuple(video.shape)}; audio latent {tuple(audio.shape)} reused from pass 1 "
                f"and locked.")
        print("[H3RDFaceAudioLock] " + info, flush=True)
        return patched, locked, info


# --------------------------------------------------------------------------------------
# Motion refine switch  +  side-by-side compare video  (v0.7.0)
# --------------------------------------------------------------------------------------

class H3RDMotionGate:
    """One switch for the motion refine (De-RoPE) group. Gates the latent AND the model."""

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "enable_motion_refine": ("BOOLEAN", {
                    "default": False,
                    "tooltip": "OFF: the motion refine group is skipped silently. ON: fast-motion parts of the "
                               "finished video are stretched in time, re-rendered and compressed back."}),
                "latent": ("LATENT", {"tooltip": "The finished pass-1 H3 audio-video latent."}),
            },
            "optional": {
                "model": ("MODEL", {"tooltip": "The pass-1 model. Passing it through this switch means the Sage nodes "
                                               "of this group do not run while the group is OFF."}),
            },
        }

    RETURN_TYPES = ("LATENT", "MODEL")
    RETURN_NAMES = ("latent", "model")
    FUNCTION = "gate"
    CATEGORY = "MiniMax H3 / Workflow UI"
    DESCRIPTION = ("Passes the finished latent and the model into the motion refine group when ON. When OFF "
                   "every node after it is skipped without an error.")

    def gate(self, enable_motion_refine, latent, model=None):
        if not enable_motion_refine:
            print("[H3 Motion Gate] motion refine OFF - group skipped.", flush=True)
            b = _blocker()
            return b, b
        print("[H3 Motion Gate] motion refine ON.", flush=True)
        return latent, model


class H3RDLmsLora:
    """Loads the LMS sharpness LoRA for the LMS sharpen group. Small on purpose: one LoRA, one strength."""

    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {
            "model": ("MODEL",),
            "strength": ("FLOAT", {"default": 1.0, "min": 0.0, "max": 2.0, "step": 0.05,
                                   "tooltip": "The author starts at 1.0. About 0.8 keeps skin more natural."}),
            "lms_file": ([AUTO_DETECT] + _lora_files(), {
                "default": AUTO_DETECT,
                "tooltip": "'auto-detect' finds minimax_h3_lms_v1.0_r64.safetensors. If your file has another name, pick it here."}),
            "missing_file": (["error", "skip_with_warning"], {"default": "error"}),
        }}

    RETURN_TYPES = ("MODEL", "STRING")
    RETURN_NAMES = ("model", "info")
    FUNCTION = "apply"
    CATEGORY = "MiniMax H3 / Workflow UI"
    DESCRIPTION = "Applies the LMS sharpness LoRA. Used only inside the LMS sharpen group."

    def apply(self, model, strength, lms_file=AUTO_DETECT, missing_file="error"):
        slot = [x for x in _LORA_SLOTS if x[0] == "lms_sharpness"][0]
        manual = bool(lms_file) and lms_file not in (AUTO_DETECT, "none")
        name = lms_file if manual else _find_lora(slot[2], slot[3])
        if name is None:
            _missing(missing_file, "The LMS LoRA",
                     "Expected " + " or ".join(slot[2]) + " in models/loras (any subfolder). Download page: "
                     + _LORA_PAGES["lms_sharpness"] + ". If the file is there under another name, pick it in 'lms_file'.")
            return model, "LMS LoRA not found - skipped."
        info = f"LMS LoRA: strength {float(strength):g}  file {name}" + ("  (picked by hand)" if manual else "")
        print("[H3 LMS LoRA] " + info, flush=True)
        return _apply_lora(model, name, strength), info


class H3RDLmsGate:
    """One switch for the LMS sharpen group, and the choice of which video it sharpens."""

    SOURCES = ["normal video", "motion-refined video (needs the motion group ON)"]

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "enable_lms_sharpen": ("BOOLEAN", {
                    "default": False,
                    "tooltip": "OFF: the LMS sharpen group is skipped silently. ON: the chosen video is rendered again "
                               "with the LMS LoRA, using that video as an aligned guide, and saved as another video."}),
                "source": (cls.SOURCES, {
                    "default": cls.SOURCES[0],
                    "tooltip": "Which video is sharpened. 'motion-refined video' needs the motion group switched on."}),
            },
            "optional": {
                "normal_images": ("IMAGE", {"lazy": True}),
                "motion_images": ("IMAGE", {"lazy": True}),
                "model": ("MODEL", {"tooltip": "Base model. Passing it through this switch means nothing in the group "
                                               "runs while the group is OFF."}),
                "clip": ("CLIP", {"tooltip": "Text encoder. Passed through for the same reason."}),
            },
        }

    RETURN_TYPES = ("IMAGE", "MODEL", "CLIP", "INT", "INT", "INT")
    RETURN_NAMES = ("guide_images", "model", "clip", "width", "height", "length")
    FUNCTION = "gate"
    CATEGORY = "MiniMax H3 / Workflow UI"
    DESCRIPTION = ("Switches the LMS sharpen group on or off and picks its source video. Also reports the source's "
                   "size and frame count, so the new video is created at exactly the same size and length.")

    def check_lazy_status(self, enable_lms_sharpen, source, normal_images=None, motion_images=None, model=None, clip=None):
        if not enable_lms_sharpen:
            return []
        want = "motion_images" if str(source).startswith("motion") else "normal_images"
        have = {"normal_images": normal_images, "motion_images": motion_images}
        return [want] if have[want] is None else []

    def gate(self, enable_lms_sharpen, source, normal_images=None, motion_images=None, model=None, clip=None):
        if not enable_lms_sharpen:
            print("[H3 LMS Gate] LMS sharpen OFF - group skipped.", flush=True)
            b = _blocker()
            return b, b, b, b, b, b
        images = motion_images if str(source).startswith("motion") else normal_images
        if images is None:
            raise ValueError("H3 LMS Gate: the selected source is not connected or its group is switched off. "
                             "Switch that group on, or choose 'normal video'.")
        n = int(images.shape[0])
        if n < 5:
            raise ValueError(f"H3 LMS Gate: the source has only {n} frame(s); at least 5 are needed.")
        valid = n - ((n - 5) % 17)           # MiniMax H3 clip lengths are 17k + 5
        if valid != n:
            print(f"[H3 LMS Gate] source has {n} frames; using the first {valid} (the nearest valid H3 length).", flush=True)
            images = images[:valid]
        h, w = int(images.shape[1]), int(images.shape[2])
        if h % 16 or w % 16:
            raise ValueError(f"H3 LMS Gate: the source is {w}x{h}; MiniMax H3 needs sizes divisible by 16.")
        print(f"[H3 LMS Gate] LMS sharpen ON - source '{source}', {valid} frames at {w}x{h}.", flush=True)
        return images, model, clip, w, h, valid


# --------------------------------------------------------------------------------------
# Video loader with standard fields only  (v0.9.0)
# --------------------------------------------------------------------------------------

def _video_files():
    import os
    import folder_paths
    d = folder_paths.get_input_directory()
    try:
        files = [f for f in os.listdir(d) if os.path.isfile(os.path.join(d, f))]
        return sorted(folder_paths.filter_files_content_types(files, ["video"]))
    except Exception:
        return []


class H3RDLoadVideo:
    """Loads a video for the reference bank. Every field is a standard ComfyUI field, so the node draws
    correctly in both the classic and the new node renderer."""

    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {
            "force_rate": ("FLOAT", {"default": 24.0, "min": 0.0, "max": 120.0, "step": 1.0,
                                     "tooltip": "Frames per second the clip is converted to. MiniMax H3 works at 24. "
                                                "0 keeps the file's own rate."}),
            "custom_width": ("INT", {"default": 0, "min": 0, "max": 8192, "step": 8,
                                     "tooltip": "0 keeps the original width. With only one of width/height set, the "
                                                "other follows the aspect ratio. With both set, the picture is scaled "
                                                "to fill that size and cropped at the centre."}),
            "custom_height": ("INT", {"default": 0, "min": 0, "max": 8192, "step": 8,
                                      "tooltip": "0 keeps the original height. See custom_width."}),
            "frame_load_cap": ("INT", {"default": 0, "min": 0, "max": 100000, "step": 1,
                                       "tooltip": "Largest number of frames to load. 0 = no limit."}),
            "skip_first_frames": ("INT", {"default": 0, "min": 0, "max": 100000, "step": 1,
                                          "tooltip": "Frames to drop from the START, counted after the rate change."}),
            "skip_last_frames": ("INT", {"default": 0, "min": 0, "max": 100000, "step": 1,
                                         "tooltip": "Frames to drop from the END, counted after the rate change."}),
            "select_every_nth": ("INT", {"default": 1, "min": 1, "max": 1000, "step": 1,
                                         "tooltip": "1 keeps every frame. 2 keeps every second frame, and so on."}),
            # The video picker is deliberately the LAST field: ComfyUI adds its upload button as one more field,
            # and with the picker last that button always follows it, whatever the interface version.
            "video": (_video_files(), {"video_upload": True,
                                       "tooltip": "A video from ComfyUI/input. Use the upload button to add one."}),
        }}

    RETURN_TYPES = ("IMAGE", "INT", "AUDIO", "STRING")
    RETURN_NAMES = ("IMAGE", "frame_count", "audio", "info")
    FUNCTION = "load"
    CATEGORY = "MiniMax H3 / Workflow UI"
    DESCRIPTION = ("Loads a video as frames plus its soundtrack, converted to the chosen frame rate. "
                   "The soundtrack is cut to the same part of the clip as the frames. A clip without sound "
                   "gives no audio.")

    @classmethod
    def IS_CHANGED(cls, video, **kw):
        import os
        import folder_paths
        try:
            path = folder_paths.get_annotated_filepath(video)
            return f"{os.path.getmtime(path)}:{os.path.getsize(path)}"
        except Exception:
            return video

    @classmethod
    def VALIDATE_INPUTS(cls, video, **kw):
        import folder_paths
        if not video or not folder_paths.exists_annotated_filepath(video):
            return f"Video file not found in ComfyUI/input: {video}. Pick a video in this node, or upload one."
        return True

    def load(self, video, force_rate=24.0, custom_width=0, custom_height=0, frame_load_cap=0,
             skip_first_frames=0, skip_last_frames=0, select_every_nth=1, **_ignored):
        import math

        import av
        import numpy as np
        import torch
        import comfy.utils
        import folder_paths

        path = folder_paths.get_annotated_filepath(video)
        nth = max(1, int(select_every_nth))
        skip_first, skip_last, cap = int(skip_first_frames), int(skip_last_frames), int(frame_load_cap)
        frames, kept_index = [], []
        with av.open(path) as container:
            if not container.streams.video:
                raise ValueError(f"H3 Load Video: '{video}' has no video stream.")
            vs = container.streams.video[0]
            src_fps = float(vs.average_rate or vs.guessed_rate or 24.0)
            fps = float(force_rate) if float(force_rate) > 0 else src_fps
            # Frame selection follows VideoHelperSuite exactly (the loader Workflow 01 v1 used): source frames
            # are counted, not timed. A running time offset decides which source frame each output frame takes.
            base_time, target_time = 1.0 / src_fps, 1.0 / fps
            offset = target_time - base_time
            k = 0                                    # index on the output-rate timeline
            source = iter(container.decode(vs))
            frame, img_cache, done = None, None, False
            while not done:
                if offset < target_time:
                    frame = next(source, None)
                    if frame is None:
                        break
                    img_cache = None
                    offset += base_time
                if offset < target_time:
                    continue
                offset -= target_time
                if k >= skip_first and (k - skip_first) % nth == 0 and (cap <= 0 or len(frames) < cap):
                    if img_cache is None:
                        img = frame.to_ndarray(format="rgb24")
                        quad = int(round(frame.rotation // 90)) % 4 if getattr(frame, "rotation", 0) else 0
                        if quad:
                            img = np.rot90(img, k=quad, axes=(0, 1)).copy()
                        img_cache = torch.from_numpy(img)
                    frames.append(img_cache)
                    kept_index.append(k)
                k += 1
                if cap > 0 and len(frames) >= cap and skip_last <= 0:
                    done = True                      # nothing after this point can change the result
            total = k
            # ---- soundtrack ----
            wave, sr = None, 0
            if container.streams.audio:
                try:
                    container.seek(0)
                    a = container.streams.audio[0]
                    sr = int(a.sample_rate)
                    resampler = av.audio.resampler.AudioResampler(format="fltp")
                    chunks = []
                    for af in container.decode(a):
                        for r in resampler.resample(af):
                            chunks.append(r.to_ndarray())
                    for r in resampler.resample(None):
                        chunks.append(r.to_ndarray())
                    if chunks:
                        wave = torch.from_numpy(np.concatenate(chunks, axis=1)).float()
                except Exception as e:                 # a broken audio track must not block the video
                    print(f"[H3 Load Video] could not read the soundtrack of '{video}': {e}", flush=True)
                    wave = None

        if skip_last > 0:
            limit = total - skip_last
            keep = [j for j, kk in enumerate(kept_index) if kk < limit]
            frames = [frames[j] for j in keep]
            kept_index = [kept_index[j] for j in keep]
        if not frames:
            raise ValueError(f"H3 Load Video: no frames left from '{video}'. The clip has {total} frames at "
                             f"{fps:g} fps; check skip_first_frames ({skip_first}) and skip_last_frames ({skip_last}).")

        images = torch.stack(frames).float() / 255.0
        h, w = int(images.shape[1]), int(images.shape[2])
        cw, ch = int(custom_width), int(custom_height)
        if cw > 0 or ch > 0:
            if cw > 0 and ch > 0:
                tw, th, crop = cw, ch, "center"
            elif cw > 0:
                tw, th, crop = cw, max(8, int(round(h * cw / w / 8) * 8)), "disabled"
            else:
                tw, th, crop = max(8, int(round(w * ch / h / 8) * 8)), ch, "disabled"
            images = comfy.utils.common_upscale(images.movedim(-1, 1), tw, th, "lanczos", crop).movedim(1, -1).clamp(0.0, 1.0)

        n = int(images.shape[0])
        audio = None
        if wave is not None and sr > 0:
            first, last = kept_index[0], kept_index[-1] + nth
            a0, a1 = int(round(first / fps * sr)), int(round(last / fps * sr))
            cut = wave[:, a0:a1]
            need = a1 - a0
            if cut.shape[1] < need:                    # soundtrack shorter than the picture: pad with silence
                cut = torch.cat([cut, torch.zeros(cut.shape[0], need - cut.shape[1])], dim=1)
            audio = {"waveform": cut.unsqueeze(0).contiguous(), "sample_rate": sr}
        info = (f"{video}: {n} frames at {fps:g} fps ({n * nth / fps:.2f} s), {int(images.shape[2])}x{int(images.shape[1])}"
                + (f", source {src_fps:g} fps" if abs(src_fps - fps) > 1e-3 else "")
                + (", with audio" if audio is not None else ", no audio"))
        print("[H3 Load Video] " + info, flush=True)
        return images, n, audio, info


class H3RDCompareVideo:
    """Two videos in one frame, playing in step, so a before/after is judged in a single player."""

    LAYOUTS = ["side_by_side", "top_bottom"]

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "enable": ("BOOLEAN", {"default": True,
                                       "tooltip": "OFF skips this comparison. It is also skipped by itself when "
                                                  "the group that makes the second video is switched off."}),
                "images_a": ("IMAGE", {"tooltip": "The BEFORE video (shown left or on top)."}),
                "images_b": ("IMAGE", {"tooltip": "The AFTER video (shown right or below)."}),
                "label_a": ("STRING", {"default": "ORIGINAL"}),
                "label_b": ("STRING", {"default": "AFTER"}),
                "layout": (cls.LAYOUTS, {"default": "side_by_side"}),
                "fps": ("FLOAT", {"default": 24.0, "min": 1.0, "max": 120.0, "step": 1.0}),
            },
            "optional": {
                "audio": ("AUDIO",),
                "max_frames": ("INT", {"forceInput": True,
                                       "tooltip": "Trim both videos to this many frames (the delivery length)."}),
            },
        }

    RETURN_TYPES = ("VIDEO", "STRING")
    RETURN_NAMES = ("video", "info")
    FUNCTION = "compare"
    CATEGORY = "MiniMax H3 / Workflow UI"
    DESCRIPTION = ("Builds one video that shows two clips next to each other at the same moment. The smaller "
                   "clip is enlarged to the size of the larger one, so both are judged at the same scale. "
                   "Frames are encoded one at a time, so no large combined image batch is held in memory.")

    @staticmethod
    def _label_patch(text, height):
        from PIL import Image, ImageDraw, ImageFont
        import numpy as np
        size = max(16, int(height * 0.035))
        try:
            font = ImageFont.load_default(size=size)
        except TypeError:           # older Pillow: fixed-size bitmap font
            font = ImageFont.load_default()
        probe = ImageDraw.Draw(Image.new("L", (8, 8)))
        box = probe.textbbox((0, 0), text, font=font)
        pad = max(6, size // 3)
        w, h = box[2] - box[0] + 2 * pad, box[3] - box[1] + 2 * pad
        img = Image.new("L", (w, h), 0)
        ImageDraw.Draw(img).text((pad - box[0], pad - box[1]), text, fill=255, font=font)
        return np.asarray(img, dtype=np.float32) / 255.0

    def compare(self, enable, images_a, images_b, label_a="ORIGINAL", label_b="AFTER", layout="side_by_side",
                fps=24.0, audio=None, max_frames=None):
        if not enable:
            b = _blocker()
            return b, b
        import math
        import os
        import uuid
        from fractions import Fraction

        import av
        import numpy as np
        import torch
        import torch.nn.functional as F
        import folder_paths
        from comfy_api.latest import InputImpl

        n = min(int(images_a.shape[0]), int(images_b.shape[0]))
        if max_frames:
            n = min(n, int(max_frames))
        if n < 1:
            raise ValueError("H3 Compare Video: no frames to compare.")
        ha, wa = int(images_a.shape[1]), int(images_a.shape[2])
        hb, wb = int(images_b.shape[1]), int(images_b.shape[2])
        side = layout == "side_by_side"
        if side:                                   # same height, widths follow each clip's aspect
            th = max(ha, hb)
            sa, sb = (th, max(2, round(wa * th / ha))), (th, max(2, round(wb * th / hb)))
        else:                                      # same width
            tw = max(wa, wb)
            sa, sb = (max(2, round(ha * tw / wa)), tw), (max(2, round(hb * tw / wb)), tw)
        gap = 8
        W = (sa[1] + gap + sb[1]) if side else max(sa[1], sb[1])
        H = max(sa[0], sb[0]) if side else (sa[0] + gap + sb[0])
        W += W % 2
        H += H % 2

        def fit(frames, size):
            if (int(frames.shape[1]), int(frames.shape[2])) == size:
                return frames
            x = frames.movedim(-1, 1).float()
            x = F.interpolate(x, size=size, mode="bicubic", align_corners=False, antialias=False)
            return x.movedim(1, -1).clamp(0.0, 1.0)

        patches = [self._label_patch(t, H) if t else None for t in (label_a, label_b)]
        folder = folder_paths.get_temp_directory()
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, f"h3rd_compare_{uuid.uuid4().hex[:10]}.mp4")
        rate = Fraction(round(float(fps) * 1000), 1000)

        with av.open(path, mode="w") as out:
            vs = out.add_stream("libx264", rate=rate)
            vs.width, vs.height, vs.pix_fmt = W, H, "yuv420p"
            vs.options = {"crf": "17", "preset": "veryfast"}
            astream, wave, sr, a_layout = None, None, 0, "stereo"
            if audio is not None and audio.get("waveform") is not None:
                sr = int(audio["sample_rate"])
                wave = audio["waveform"][0, :, :math.ceil(sr / float(fps) * n)]
                a_layout = {1: "mono", 2: "stereo"}.get(int(wave.shape[0]), "stereo")
                if int(wave.shape[0]) > 2:
                    wave = wave[:2]
                astream = out.add_stream("aac", rate=sr, layout=a_layout)
            for i in range(0, n, 4):
                a = fit(images_a[i:i + 4][: n - i].cpu(), sa)
                b = fit(images_b[i:i + 4][: n - i].cpu(), sb)
                k = int(a.shape[0])
                canvas = torch.zeros((k, H, W, 3), dtype=torch.float32)
                canvas[:, :sa[0], :sa[1]] = a[..., :3]
                if side:
                    origin_b = (0, sa[1] + gap)
                else:
                    origin_b = (sa[0] + gap, 0)
                canvas[:, origin_b[0]:origin_b[0] + sb[0], origin_b[1]:origin_b[1] + sb[1]] = b[..., :3]
                arr = (canvas * 255.0).clamp(0, 255).byte().numpy()
                for (y0, x0), patch in zip(((0, 0), origin_b), patches):
                    if patch is None:
                        continue
                    ph, pw = min(patch.shape[0], H - y0), min(patch.shape[1], W - x0)
                    region = arr[:, y0:y0 + ph, x0:x0 + pw].astype(np.float32)
                    alpha = patch[:ph, :pw, None]
                    arr[:, y0:y0 + ph, x0:x0 + pw] = (region * 0.35 * (1 - alpha) + 255.0 * alpha).astype(np.uint8)
                for j in range(k):
                    frame = av.VideoFrame.from_ndarray(arr[j], format="rgb24").reformat(format="yuv420p")
                    out.mux(vs.encode(frame))
            out.mux(vs.encode(None))
            if astream is not None:
                af = av.AudioFrame.from_ndarray(wave.float().cpu().contiguous().numpy(), format="fltp", layout=a_layout)
                af.sample_rate = sr
                af.pts = 0
                out.mux(astream.encode(af))
                out.mux(astream.encode(None))
        info = (f"{label_a} {wa}x{ha} | {label_b} {wb}x{hb} -> {W}x{H}, {n} frames, {layout}"
                + (", with audio" if astream is not None else ""))
        print("[H3 Compare Video] " + info, flush=True)
        return InputImpl.VideoFromFile(path), info


NODE_CLASS_MAPPINGS = {
    "H3RDLoraStack": H3RDLoraStack,
    "H3RDSpeedMode": H3RDSpeedMode,
    "H3RDCacheRoute": H3RDCacheRoute,
    "H3RDHQGate": H3RDHQGate,
    "H3RDHQPass2Latent": H3RDHQPass2Latent,
    "H3RDHQPass2Conditioning": H3RDHQPass2Conditioning,
    "H3RDVideo1Route": H3RDVideo1Route,
    "H3RDFaceGate": H3RDFaceGate,
    "H3RDFaceAudioLock": H3RDFaceAudioLock,
    "H3RDMotionGate": H3RDMotionGate,
    "H3RDLoadVideo": H3RDLoadVideo,
    "H3RDLmsGate": H3RDLmsGate,
    "H3RDLmsLora": H3RDLmsLora,
    "H3RDCompareVideo": H3RDCompareVideo,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "H3RDLoraStack": "H3 LoRA Stack (v2)",
    "H3RDSpeedMode": "H3 Speed Mode - Turbo Switch (v2)",
    "H3RDCacheRoute": "H3 Cache Route (v2)",
    "H3RDHQGate": "H3 Upscale Gate - Latent Upscale On/Off (v2)",
    "H3RDHQPass2Latent": "H3 Upscale Pass-2 Latent - Audio Locked (v2)",
    "H3RDHQPass2Conditioning": "H3 Refine Conditioning - References at Target Size (v2)",
    "H3RDVideo1Route": "H3 Video 1 Route (retired in v0.7.0 - kept so older saved workflows still open)",
    "H3RDFaceGate": "H3 Face Gate - Face Refine On/Off (v2)",
    "H3RDFaceAudioLock": "H3 Face Audio Lock (v2)",
    "H3RDMotionGate": "H3 Motion Gate - Motion Refine On/Off (v2)",
    "H3RDLoadVideo": "H3 Load Video (v2)",
    "H3RDLmsGate": "H3 LMS Gate (retired in v0.9.0 - kept so older saved workflows still open)",
    "H3RDLmsLora": "H3 LMS LoRA Loader (retired in v0.9.0 - kept so older saved workflows still open)",
    "H3RDCompareVideo": "H3 Compare Video (retired in v0.9.0 - kept so older saved workflows still open)",
}
