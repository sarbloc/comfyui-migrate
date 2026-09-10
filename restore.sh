#!/usr/bin/env bash
# Rebuild a ComfyUI model environment on any rented GPU.
#
#   bash restore.sh <set> [COMFY_ROOT]      COMFY_ROOT default: /workspace/ComfyUI
#
#   wan          Wan 2.2 image-to-video
#   qwen-edit    Qwen-Image-Edit 2511
#   qwen-depth   Qwen-Image + Lotus depth + ControlNet
#   all          everything, deduplicated
#
# Run with no arguments for sizes. They are summed from the tables below, not
# written here: written here, qwen-depth said ~26 GB when it was 35.
#
# SETS, BECAUSE THE DISK RAN OUT. This began as one flat list — correct when
# there was one workflow. At three it is ~90 GB against a 120 GB volume, and
# pulling all of it to run one workflow wastes both disk and download.
#
# SETS OVERLAP, AND THAT IS DELIBERATE. Each set lists EVERYTHING its workflow
# needs, including files another set also lists. Nothing is downloaded twice:
# a file already present at the right size is skipped. The alternative — a
# dependency graph, or a "shared" set you must remember to run first — is more
# machinery for a case that resolves itself.
#
# WHAT THIS ASSUMES, SO YOU CAN CHECK IT: HuggingFace repo/paths are inferred
# from filenames, not read off any volume. Every download is size-checked (see
# size_ok). A wrong guess fails loudly rather than handing you a different
# model that misbehaves three hours into a render.
set -uo pipefail

SET="${1:-}"
ROOT="${2:-/workspace/ComfyUI}"

# Sum a set's expected bytes, deduplicated by filename so `all` counts a
# shared file once. usage() prints these so the sizes cannot drift from the
# tables — the header comment used to carry them and was 9 GB out.
set_gib() {
  awk -F'|' 'NF >= 3 && !seen[$1]++ { s += $3 } END { printf "%.1f", s / 1073741824 }' <<< "$1"
}

usage() {
  cat <<EOF
usage: bash restore.sh <set> [COMFY_ROOT]      COMFY_ROOT default: /workspace/ComfyUI

  wan          Wan 2.2 image-to-video                  $(set_gib "$MODELS_WAN") GiB
  qwen-edit    Qwen-Image-Edit 2511                    $(set_gib "$MODELS_QWEN_EDIT") GiB
  qwen-depth   Qwen-Image + Lotus depth + ControlNet   $(set_gib "$MODELS_QWEN_DEPTH") GiB
  all          everything, deduplicated                $(set_gib "$MODELS_ALL") GiB
EOF
  exit 2
}

# ---------------------------------------------------------------------------
# name | dest_dir | expected_bytes | hf_repo | path_in_repo

MODELS_WAN=$(cat <<'EOF'
wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors|models/diffusion_models|14293618240|Comfy-Org/Wan_2.2_ComfyUI_Repackaged|split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors
wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors|models/diffusion_models|14293618240|Comfy-Org/Wan_2.2_ComfyUI_Repackaged|split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors
umt5_xxl_fp8_e4m3fn_scaled.safetensors|models/text_encoders|6734380928|Comfy-Org/Wan_2.1_ComfyUI_Repackaged|split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors
wan_2.1_vae.safetensors|models/vae|254002624|Comfy-Org/Wan_2.1_ComfyUI_Repackaged|split_files/vae/wan_2.1_vae.safetensors
wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors|models/loras|1226977424|Comfy-Org/Wan_2.2_ComfyUI_Repackaged|split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors
wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors|models/loras|1226977424|Comfy-Org/Wan_2.2_ComfyUI_Repackaged|split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors
EOF
)

MODELS_QWEN_EDIT=$(cat <<'EOF'
qwen_image_edit_2511_fp8mixed.safetensors|models/diffusion_models|20533762817|Comfy-Org/Qwen-Image-Edit_ComfyUI|split_files/diffusion_models/qwen_image_edit_2511_fp8mixed.safetensors
qwen_2.5_vl_7b_fp8_scaled.safetensors|models/text_encoders|9384670680|Comfy-Org/HunyuanVideo_1.5_repackaged|split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors
Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors|models/loras|849608296|lightx2v/Qwen-Image-Edit-2511-Lightning|Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors
qwen_image_vae.safetensors|models/vae|253806246|Comfy-Org/Qwen-Image_ComfyUI|split_files/vae/qwen_image_vae.safetensors
EOF
)

# The last two entries were NOT in ComfyUI's missing-models list for this
# workflow — because they were already on disk from qwen-edit when it was
# loaded. A missing-models list only reports what is MISSING, so it is not a
# complete set description. On a fresh box this workflow needs the Qwen text
# encoder and VAE like any other Qwen-Image graph, so they are listed here.
# INFERRED, not observed: if a fresh `qwen-depth` restore leaves a red node,
# this is the first place to look.
MODELS_QWEN_DEPTH=$(cat <<'EOF'
qwen_image_fp8_e4m3fn.safetensors|models/diffusion_models|20430635136|Comfy-Org/Qwen-Image_ComfyUI|split_files/diffusion_models/qwen_image_fp8_e4m3fn.safetensors
Qwen-Image-InstantX-ControlNet-Union.safetensors|models/controlnet|3536027816|Comfy-Org/Qwen-Image-InstantX-ControlNets|split_files/controlnet/Qwen-Image-InstantX-ControlNet-Union.safetensors
lotus-depth-d-v1-1.safetensors|models/diffusion_models|1735197352|Comfy-Org/lotus|lotus-depth-d-v1-1.safetensors
Qwen-Image-Lightning-4steps-V1.0.safetensors|models/loras|1698951104|lightx2v/Qwen-Image-Lightning|Qwen-Image-Lightning-4steps-V1.0.safetensors
vae-ft-mse-840000-ema-pruned.safetensors|models/vae|334641190|stabilityai/sd-vae-ft-mse-original|vae-ft-mse-840000-ema-pruned.safetensors
qwen_2.5_vl_7b_fp8_scaled.safetensors|models/text_encoders|9384670680|Comfy-Org/HunyuanVideo_1.5_repackaged|split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors
qwen_image_vae.safetensors|models/vae|253806246|Comfy-Org/Qwen-Image_ComfyUI|split_files/vae/qwen_image_vae.safetensors
EOF
)

MODELS_ALL="$MODELS_WAN"$'\n'"$MODELS_QWEN_EDIT"$'\n'"$MODELS_QWEN_DEPTH"

[[ -z "$SET" ]] && usage
case "$SET" in
  wan)        MODELS="$MODELS_WAN" ;;
  qwen-edit)  MODELS="$MODELS_QWEN_EDIT" ;;
  qwen-depth) MODELS="$MODELS_QWEN_DEPTH" ;;
  all)        MODELS="$MODELS_ALL" ;;
  *)          echo "unknown set: $SET" >&2; usage ;;
esac

# DELIBERATELY OMITTED from `wan`: umt5-xxl-enc-fp8_e4m3fn.safetensors.
# The original volume carried TWO copies of the same text encoder — Comfy's
# repack and the upstream original. Add it back only if ComfyUI reports a
# missing encoder.

[[ -d "$ROOT" ]] || { echo "No ComfyUI at $ROOT — install it first, or pass the path." >&2; exit 1; }
cd "$ROOT" || exit 1
command -v hf >/dev/null || {
  pip install -q --upgrade "huggingface_hub[cli]" || { echo "could not install huggingface_hub" >&2; exit 1; }
  hash -r
  command -v hf >/dev/null || { echo "huggingface_hub installed but 'hf' is not on PATH — add pip's bin dir" >&2; exit 1; }
}

# Is an on-disk size close enough to the recorded one to be the same model?
#
# NOT an equality test, deliberately. Verified 2026-09-10: Comfy-Org had
# re-packed four of these upstream, ~0.01% larger, which is a newer revision
# of the same model rather than a wrong file. What needs catching is a WRONG
# or TRUNCATED download, which is orders of magnitude off, not a fraction of
# a percent. `hf` verifies its own download integrity; this guards against a
# path pointing at a different model entirely.
#
# One owner for the rule, because the "already present" check and the
# "download finished" check MUST agree — when they did not, every run
# re-downloaded 39 GB to reproduce files that were already correct.
size_ok() {
  local got="$1" want="$2" delta
  [[ "$got" == "0" || -z "$got" ]] && return 1
  [[ "$got" == "$want" ]] && return 0
  delta=$(( got > want ? got - want : want - got ))
  (( delta * 50 <= want ))
}

echo "=== models [$SET] ==="
fail=0
while IFS='|' read -r name dest want repo path; do
  [[ -n "$name" ]] || continue
  mkdir -p "$ROOT/$dest"
  target="$ROOT/$dest/$name"

  # Present at the right size — skip. This is how overlapping sets avoid
  # downloading a shared model twice.
  if [[ -f "$target" ]] && size_ok "$(stat -c%s "$target")" "$want"; then
    echo "  ok (present)  $name"
    continue
  fi
  [[ -f "$target" ]] && echo "  re-fetching (size $(stat -c%s "$target") vs $want)  $name"

  echo "  downloading   $name"
  # </dev/null: this loop reads $MODELS on stdin; a child that reads stdin
  # would eat the remaining lines.
  if ! hf download "$repo" "$path" --local-dir "$ROOT/$dest" >/dev/null 2>&1 </dev/null; then
    echo "  FAILED to download $name from $repo :: $path" >&2
    fail=1
    continue
  fi

  # `hf` recreates the repo's directory structure, so a path with a
  # `split_files/...` prefix lands nested and ComfyUI never sees it.
  nested="$ROOT/$dest/$path"
  if [[ -f "$nested" && "$nested" != "$target" ]]; then
    mv -f "$nested" "$target"
    # rmdir refuses to touch anything non-empty, which is the point.
    rmdir -p --ignore-fail-on-non-empty "$(dirname "$nested")" 2>/dev/null
  fi
  # `hf --local-dir` leaves its own .cache/huggingface beside the model. Not
  # ours, and it shows up in the next inventory's REVIEW.txt as noise.
  rm -rf "$ROOT/$dest/.cache"

  got=$(stat -c%s "$target" 2>/dev/null || echo 0)
  if [[ "$got" == "0" ]]; then
    echo "  MISSING       $name — download produced nothing" >&2
    fail=1
  elif ! size_ok "$got" "$want"; then
    echo "  WRONG FILE    $name: got $got, expected ~$want — check the repo path" >&2
    fail=1
  elif [[ "$got" == "$want" ]]; then
    echo "  ok            $name"
  else
    echo "  ok (newer)    $name  [$got vs $want recorded — upstream re-pack]"
  fi
done <<< "$MODELS"

echo
echo "=== custom nodes ==="
# Installed via ComfyUI-Manager on the original volume (no git metadata
# survived), so Manager is cloned directly and the rest go through it BY NAME —
# rather than this script inventing GitHub URLs it cannot verify. Not
# per-set: the same four serve every workflow and they are ~200 MB total.
mkdir -p "$ROOT/custom_nodes"
if [[ ! -d "$ROOT/custom_nodes/ComfyUI-Manager" ]]; then
  git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager \
    "$ROOT/custom_nodes/ComfyUI-Manager" 2>&1 | tail -1
fi
CM="$ROOT/custom_nodes/ComfyUI-Manager/cm-cli.py"
for node in ComfyUI-KJNodes Civicomfy ComfyUI-RunpodDirect; do
  if [[ -d "$ROOT/custom_nodes/$node" ]]; then
    echo "  ok (present)  $node"
    continue
  fi
  if [[ -f "$CM" ]]; then
    if python3 "$CM" install "$node" >/dev/null 2>&1; then
      echo "  installed     $node"
    else
      echo "  MANUAL        $node — install from the Manager UI (name may differ)"
    fi
  else
    echo "  MANUAL        $node — cm-cli.py not found"
  fi
done

echo
if [[ "$fail" == "0" ]]; then
  echo "RESTORE OK [$SET]"
else
  echo "RESTORE FINISHED WITH FAILURES — see above"
fi
du -sh "$ROOT/models" 2>/dev/null
df -h "$ROOT" 2>/dev/null | tail -1
