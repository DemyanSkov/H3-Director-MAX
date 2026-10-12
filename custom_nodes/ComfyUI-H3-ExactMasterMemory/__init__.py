from .nodes import (
    NODE_CLASS_MAPPINGS as _MEM_CLASSES,
    NODE_DISPLAY_NAME_MAPPINGS as _MEM_NAMES,
)
from .keyframes_stable import (
    NODE_CLASS_MAPPINGS as _KF_CLASSES,
    NODE_DISPLAY_NAME_MAPPINGS as _KF_NAMES,
)
from .ui_utils import (
    NODE_CLASS_MAPPINGS as _UI_CLASSES,
    NODE_DISPLAY_NAME_MAPPINGS as _UI_NAMES,
)
from .semantic_ref import (
    NODE_CLASS_MAPPINGS as _SEM_CLASSES,
    NODE_DISPLAY_NAME_MAPPINGS as _SEM_NAMES,
)
from .v2_nodes import (
    NODE_CLASS_MAPPINGS as _V2_CLASSES,
    NODE_DISPLAY_NAME_MAPPINGS as _V2_NAMES,
)

VERSION = "0.10.1"

NODE_CLASS_MAPPINGS = {
    **_MEM_CLASSES,
    **_KF_CLASSES,
    **_UI_CLASSES,
    **_SEM_CLASSES,
    **_V2_CLASSES,
}
NODE_DISPLAY_NAME_MAPPINGS = {
    **_MEM_NAMES,
    **_KF_NAMES,
    **_UI_NAMES,
    **_SEM_NAMES,
    **_V2_NAMES,
}

print(
    "[H3ExactMasterMemory] v0.10.1 loaded | "
    "ExactMaster + StableKeyframes + Workflow UI + Semantic REF2VA + "
    "v2 LoRA Stack / Speed Mode / Load Video / Latent Upscale / Motion Refine / Face Refine registered",
    flush=True,
)

# Browser code (web/*.js) and node help pages (web/docs/*.md) are served from here.
WEB_DIRECTORY = "./web"

__all__ = ["NODE_CLASS_MAPPINGS", "NODE_DISPLAY_NAME_MAPPINGS", "WEB_DIRECTORY"]
