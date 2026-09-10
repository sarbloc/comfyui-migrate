#!/usr/bin/env bash
# Inventory a ComfyUI install on a RunPod network volume, and extract the
# small irreplaceable parts.
#
# RUN THIS ON THE POD (CPU-only is fine — this touches no GPU).
#
#   bash inventory.sh [COMFY_ROOT] [OUT_TARBALL]
#
# It writes ONE tarball, comfyui-extract.tgz, beside the ComfyUI root unless
# you give it a path. Pull that down and you can rebuild the environment
# anywhere.
#
# The premise: a ComfyUI volume splits into two very unequal halves.
#   - models        : large, boring, RE-DOWNLOADABLE. We record NAMES, not bytes.
#   - everything else: small, and the actual work. We take it.
# Anything that looks like it is NOT a stock model gets flagged rather than
# assumed, because a trained LoRA is unrecoverable and looks just like a
# downloaded one from the outside.
set -uo pipefail

ROOT="${1:-}"
if [[ -z "$ROOT" ]]; then
  for c in /workspace/ComfyUI /workspace/comfyui /ComfyUI "$HOME/ComfyUI"; do
    [[ -d "$c" ]] && ROOT="$c" && break
  done
fi
[[ -d "$ROOT" ]] || { echo "ComfyUI root not found. Pass it: $0 /path/to/ComfyUI" >&2; exit 1; }
echo "ComfyUI root: $ROOT"
TAR="${2:-$(dirname "$ROOT")/comfyui-extract.tgz}"

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
mkdir -p "$OUT/extract"

# --- 1. WORKFLOWS — the actual work, a few MB at most ------------------------
# ComfyUI has moved these around across versions, so take every plausible
# location rather than betting on one.
echo "==> workflows"
for d in "$ROOT/user/default/workflows" "$ROOT/user/workflows" "$ROOT/workflows" "$ROOT/web/workflows"; do
  if [[ -d "$d" ]]; then
    rel="${d#"$ROOT"/}"
    mkdir -p "$OUT/extract/$rel"
    cp -a "$d/." "$OUT/extract/$rel/" 2>/dev/null
    echo "    $rel ($(find "$d" -type f | wc -l) files)"
  fi
done
# Loose workflow JSON anywhere outside models/ and custom_nodes/.
find "$ROOT" -maxdepth 2 -name '*.json' -type f \
  -not -path "*/models/*" -not -path "*/custom_nodes/*" -not -path "*/node_modules/*" \
  -exec cp -a {} "$OUT/extract/" \; 2>/dev/null

# --- 2. CUSTOM NODES — pinned, or your workflows break on restore ------------
# Re-cloning at HEAD is NOT the same environment. Record the commit.
echo "==> custom_nodes"
{
  echo "# name<TAB>remote<TAB>commit"
  if [[ -d "$ROOT/custom_nodes" ]]; then
    for n in "$ROOT/custom_nodes"/*/; do
      [[ -d "$n" ]] || continue
      name=$(basename "$n")
      remote=$(git -C "$n" config --get remote.origin.url 2>/dev/null || echo "NOT-A-GIT-CHECKOUT")
      commit=$(git -C "$n" rev-parse HEAD 2>/dev/null || echo "-")
      printf '%s\t%s\t%s\n' "$name" "$remote" "$commit"
    done
  fi
} > "$OUT/extract/custom_nodes.tsv"
echo "    $(($(wc -l < "$OUT/extract/custom_nodes.tsv") - 1)) nodes"

# --- 3. MODEL MANIFEST — names and sizes, NOT the bytes ----------------------
echo "==> model manifest"
{
  echo "# size_bytes<TAB>sha256_first_1MB<TAB>path"
  if [[ -d "$ROOT/models" ]]; then
    find "$ROOT/models" -type f \
      \( -name '*.safetensors' -o -name '*.ckpt' -o -name '*.pt' -o -name '*.pth' \
         -o -name '*.bin' -o -name '*.gguf' -o -name '*.onnx' -o -name '*.sft' \) \
      -printf '%s\t%p\n' 2>/dev/null | sort -rn | while IFS=$'\t' read -r size path; do
        # Hashing 50GB would dominate runtime for no benefit. The first MB is
        # enough to tell two same-size files apart ON THIS VOLUME — the two
        # Wan LoRAs are byte-identical in size. It is NOT a restore-side
        # check: upstream re-packs change the safetensors header, and
        # `hf download` already verifies the full sha256 against HuggingFace.
        h=$(head -c 1048576 "$path" 2>/dev/null | sha256sum | cut -d' ' -f1)
        printf '%s\t%s\t%s\n' "$size" "$h" "${path#"$ROOT"/}"
      done
  fi
} > "$OUT/extract/models.tsv"
echo "    $(($(wc -l < "$OUT/extract/models.tsv") - 1)) model files"

# --- 4. WHAT MIGHT NOT BE RE-DOWNLOADABLE -----------------------------------
# Flagged, never assumed. Anything here you should look at before deleting the
# volume: a trained LoRA is indistinguishable from a downloaded one by shape.
echo "==> possible non-stock weights (REVIEW THESE)"
{
  echo "# Files that may be YOURS rather than downloaded. Review before deleting the volume."
  for d in loras embeddings checkpoints; do
    [[ -d "$ROOT/models/$d" ]] || continue
    # Skip hf's own .cache, Comfy's put_*_here placeholders and empty files —
    # on the first real run they were 7 of 10 lines, and a noisy list of
    # "review these" gets skimmed.
    find "$ROOT/models/$d" -type f -size +0 \
      -not -path '*/.cache/*' -not -name 'put_*_here' \
      -printf '%TY-%Tm-%Td\t%s\t%p\n' 2>/dev/null
  done
  echo "# --- output/ (listed only: renders, reproducible from workflow + input) ---"
  [[ -d "$ROOT/output" ]] && du -sh "$ROOT/output" 2>/dev/null
} > "$OUT/extract/REVIEW.txt"

# --- 4b. INPUT IMAGES — small, and as unrecoverable as the workflows --------
# The start frame of an image-to-video graph is yours; the render is not.
# Taken when small. Above the cap it is listed in REVIEW.txt and you decide.
INPUT_CAP_MB=200
if [[ -d "$ROOT/input" ]]; then
  input_mb=$(du -sm "$ROOT/input" 2>/dev/null | cut -f1)
  input_mb=${input_mb:-0}
  if (( input_mb <= INPUT_CAP_MB )); then
    mkdir -p "$OUT/extract/input"
    cp -a "$ROOT/input/." "$OUT/extract/input/" 2>/dev/null
    echo "==> input/ (${input_mb} MB, taken)"
  else
    echo "==> input/ (${input_mb} MB, over the ${INPUT_CAP_MB} MB cap — listed in REVIEW.txt, NOT taken)"
    {
      echo "# --- input/ NOT taken: ${input_mb} MB exceeds ${INPUT_CAP_MB} MB. Copy what matters by hand. ---"
      # Every file, not a top-N: this is the only record of them once the
      # volume is gone, and the small ones are the likeliest to matter.
      find "$ROOT/input" -type f -printf '%s\t%p\n' 2>/dev/null | sort -rn
    } >> "$OUT/extract/REVIEW.txt"
  fi
fi

# --- 5. SIZE PICTURE — what you are actually paying for ---------------------
echo "==> disk usage"
{
  echo "# top-level usage under $ROOT"
  du -sh "$ROOT"/* 2>/dev/null | sort -rh
  echo
  echo "# models breakdown"
  du -sh "$ROOT"/models/* 2>/dev/null | sort -rh
  echo
  echo "# whole volume"
  df -h "$ROOT" 2>/dev/null
} > "$OUT/extract/usage.txt"

# --- 6. one small tarball ----------------------------------------------------
tar -czf "$TAR" -C "$OUT" extract || { echo "could not write $TAR" >&2; exit 1; }
echo
echo "DONE -> $TAR  ($(du -h "$TAR" | cut -f1))"
echo "Pull it down, then: runpodctl send $TAR"
