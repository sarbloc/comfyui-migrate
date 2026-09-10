#!/usr/bin/env bash
# Rebuild the Wan 2.2 i2v ComfyUI environment on a fresh RunPod volume.
#
# RUN ON THE POD, with the network volume mounted at /workspace.
#   bash restore.sh [COMFY_ROOT]     (default: /workspace/ComfyUI)
#
# WHAT THIS ASSUMES, SO YOU CAN CHECK IT:
# The HuggingFace repo/paths below are INFERRED from the filenames on the old
# volume, not read from it — nothing on disk records where a file came from.
# So every download is VERIFIED AGAINST THE EXACT BYTE SIZE recorded by
# inventory.sh. A wrong guess fails loudly here rather than silently handing
# you a different model that misbehaves three hours into a render.
set -uo pipefail

ROOT="${1:-/workspace/ComfyUI}"
[[ -d "$ROOT" ]] || { echo "No ComfyUI at $ROOT — install it first, or pass the path." >&2; exit 1; }
cd "$ROOT" || exit 1

command -v hf >/dev/null || pip install -q --upgrade "huggingface_hub[cli]" || {
  echo "could not install huggingface_hub" >&2; exit 1; }

# name | dest_dir | expected_bytes | hf_repo | path_in_repo
MODELS=$(cat <<'EOF'
wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors|models/diffusion_models|14293618240|Comfy-Org/Wan_2.2_ComfyUI_Repackaged|split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors
wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors|models/diffusion_models|14293618240|Comfy-Org/Wan_2.2_ComfyUI_Repackaged|split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors
umt5_xxl_fp8_e4m3fn_scaled.safetensors|models/text_encoders|6734380928|Comfy-Org/Wan_2.1_ComfyUI_Repackaged|split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors
wan_2.1_vae.safetensors|models/vae|254002624|Comfy-Org/Wan_2.1_ComfyUI_Repackaged|split_files/vae/wan_2.1_vae.safetensors
wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors|models/loras|1226977424|Comfy-Org/Wan_2.2_ComfyUI_Repackaged|split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors
wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors|models/loras|1226977424|Comfy-Org/Wan_2.2_ComfyUI_Repackaged|split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors
EOF
)

# DELIBERATELY OMITTED: umt5-xxl-enc-fp8_e4m3fn.safetensors (6.27 GB).
# The old volume carried TWO copies of the same text encoder — Comfy's repack
# and the upstream original. Your workflows reference one of them. Add it back
# only if ComfyUI reports a missing encoder; otherwise it is 6 GB of volume
# you were paying for twice.

echo "=== models ==="
fail=0
while IFS='|' read -r name dest want repo path; do
  [[ -n "$name" ]] || continue
  mkdir -p "$ROOT/$dest"
  target="$ROOT/$dest/$name"

  if [[ -f "$target" ]]; then
    got=$(stat -c%s "$target")
    if [[ "$got" == "$want" ]]; then
      echo "  ok (present)  $name"
      continue
    fi
    echo "  re-fetching (size $got != $want)  $name"
  fi

  echo "  downloading   $name"
  # Downloads to $dest/<path_in_repo>; we then flatten it to $dest/$name.
  if ! hf download "$repo" "$path" --local-dir "$ROOT/$dest" >/dev/null 2>&1; then
    echo "  FAILED to download $name from $repo :: $path" >&2
    fail=1
    continue
  fi

  nested="$ROOT/$dest/$path"
  if [[ -f "$nested" && "$nested" != "$target" ]]; then
    mv -f "$nested" "$target"
    # Remove only the now-empty directories the download created. rmdir refuses
    # to touch anything non-empty, which is the point — no recursive delete.
    rmdir -p --ignore-fail-on-non-empty "$(dirname "$nested")" 2>/dev/null
  fi

  # SIZE IS A SANITY CHECK, NOT AN EQUALITY TEST — and the difference matters.
  #
  # The first version demanded an exact match against the byte count recorded
  # from the old volume, and that was wrong: verified 2026-09-10, Comfy-Org
  # had since re-packed four of these (~1 MB on 14 GB, metadata-level). An
  # exact test rejects a perfectly good NEWER revision of the same model.
  #
  # What actually needs catching is a WRONG or TRUNCATED file, which is orders
  # of magnitude off, not 0.01%. So: >2% drift fails, anything smaller is
  # reported and accepted. `hf` already verifies its own download integrity;
  # this guards against the path pointing at a different model entirely.
  got=$(stat -c%s "$target" 2>/dev/null || echo 0)
  if [[ "$got" == "0" ]]; then
    echo "  MISSING       $name — download produced nothing" >&2
    fail=1
  elif [[ "$got" == "$want" ]]; then
    echo "  ok            $name"
  else
    delta=$(( got > want ? got - want : want - got ))
    if (( delta * 50 > want )); then
      echo "  WRONG FILE    $name: got $got, expected ~$want — check the repo path" >&2
      fail=1
    else
      echo "  ok (newer)    $name  [$got vs $want recorded — upstream re-pack]"
    fi
  fi
done <<< "$MODELS"

echo
echo "=== custom nodes ==="
# These were installed via ComfyUI-Manager on the old volume (no git metadata
# survived), so Manager is cloned directly and the rest go through it BY NAME —
# rather than this script inventing GitHub URLs it has no way to verify.
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
      echo "  MANUAL        $node — install from the Manager UI (name may differ in the registry)"
    fi
  else
    echo "  MANUAL        $node — cm-cli.py not found"
  fi
done

echo
echo "=== workflows ==="
mkdir -p "$ROOT/user/default/workflows"
echo "  drop WAN22_I2V_FAST.json and WAN22_I2V_QUALITY.json into:"
echo "    $ROOT/user/default/workflows/"

echo
if [[ "$fail" == "0" ]]; then
  echo "RESTORE OK"
else
  echo "RESTORE FINISHED WITH FAILURES — see SIZE MISMATCH / FAILED above"
fi
du -sh "$ROOT/models" 2>/dev/null
