# comfyui-migrate

Rebuild a Wan 2.2 image-to-video ComfyUI environment on any rented GPU, from
scratch, in about ten minutes.

Built after a 42 GB network volume on RunPod became unusable: the volume was
pinned to a datacenter (`US-WA-1`) whose GPUs had all gone, and a network
volume cannot move between regions. Three days were lost to waiting for
capacity that never came.

The fix was to notice that **almost none of that 42 GB was worth keeping**. Of
the whole volume, the irreplaceable part was two 32 KB workflow files. The
rest was public model weights and four custom nodes — re-downloadable in
minutes.

So this repo replaces the volume. Rent whatever GPU is available, wherever it
is, on whatever provider, and rebuild.

## Use

```sh
git clone https://github.com/<you>/comfyui-migrate
cd comfyui-migrate
bash restore.sh <set> [COMFY_ROOT]      # COMFY_ROOT default: /workspace/ComfyUI
```

| set | workflow | size |
| --- | --- | --- |
| `wan` | Wan 2.2 image-to-video | 35 GB |
| `qwen-edit` | Qwen-Image-Edit 2511 | 29 GB |
| `qwen-depth` | Qwen-Image + Lotus depth + ControlNet | 35 GB |
| `all` | everything, deduplicated | 90 GB |

Then copy `workflows/*.json` into `<ComfyUI>/user/default/workflows/`, or
drag them onto the ComfyUI canvas in the browser. Set the start image and
the prompt — both are placeholders (`example.png`, `<your prompt>`).

## Workflows

`workflows/` holds sanitised templates of the graphs this repo exists to
protect. A ComfyUI workflow carries three personal things next to a lot of
stock template content: the `LoadImage` filename (Midjourney exports embed
the account name and the full prompt in it), the positive prompt, and the
viewport position. `sanitize-workflow.py` strips exactly those and nothing
else, walking subgraph nodes as well as top-level ones:

```sh
python3 sanitize-workflow.py ~/my-workflow.json workflows/my-workflow.json
bash check-workflows.sh          # what CI runs; refuses anything unsanitised
```

The raw files stay out of git (`*.json` is ignored; `workflows/` is the one
exception). `check-workflows.sh` fails on any username, local path, real
image filename or real prompt, so forgetting the sanitiser is caught before
merge rather than after.

**Pull one set, not `all`.** Three workflows come to 90 GB against a 120 GB
volume, and a session usually needs one of them. `all` exists for a machine
you intend to keep.

**Sets overlap on purpose.** `qwen-depth` and `qwen-edit` both list the Qwen
text encoder and VAE. Nothing downloads twice — a file already present at the
right size is skipped — and the alternative, a dependency graph or a "shared"
set you must remember to run first, is more machinery for a problem that
resolves itself.

Check `df -h` before starting. The usual failure is a small container disk
beside a larger volume, with ComfyUI on the wrong one.

## What it restores

All from HuggingFace, all paths verified by HTTP.

### `wan` — Wan 2.2 image-to-video

| file | size | repo |
| --- | --- | --- |
| wan2.2_i2v_high_noise_14B_fp8_scaled | 13.3 GB | Comfy-Org/Wan_2.2_ComfyUI_Repackaged |
| wan2.2_i2v_low_noise_14B_fp8_scaled | 13.3 GB | Comfy-Org/Wan_2.2_ComfyUI_Repackaged |
| umt5_xxl_fp8_e4m3fn_scaled | 6.3 GB | Comfy-Org/Wan_2.1_ComfyUI_Repackaged |
| wan_2.1_vae | 0.24 GB | Comfy-Org/Wan_2.1_ComfyUI_Repackaged |
| lightx2v_4steps_lora_v1_high_noise | 1.1 GB | Comfy-Org/Wan_2.2_ComfyUI_Repackaged |
| lightx2v_4steps_lora_v1_low_noise | 1.1 GB | Comfy-Org/Wan_2.2_ComfyUI_Repackaged |

### `qwen-edit` — Qwen-Image-Edit 2511

| file | size | repo |
| --- | --- | --- |
| qwen_image_edit_2511_fp8mixed | 19.1 GB | Comfy-Org/Qwen-Image-Edit_ComfyUI |
| qwen_2.5_vl_7b_fp8_scaled | 8.7 GB | Comfy-Org/HunyuanVideo_1.5_repackaged |
| Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16 | 0.79 GB | lightx2v/Qwen-Image-Edit-2511-Lightning |
| qwen_image_vae | 0.24 GB | Comfy-Org/Qwen-Image_ComfyUI |

The template's own note asks for `qwen_image_edit_2511_bf16` (38 GB). This
uses **fp8mixed** (19 GB) instead: 38 GB plus an 8.7 GB text encoder does not
fit in 48 GB of VRAM, and an fp8-capable card is exactly what the mixed
variant is for. If the node loads red, open it and pick the fp8mixed file.

The Qwen text encoder genuinely lives in a HunyuanVideo repo — Comfy-Org
reuses repacks across model families. Verified by HTTP; not a typo.

### `qwen-depth` — Qwen-Image + Lotus depth + ControlNet

| file | size | repo |
| --- | --- | --- |
| qwen_image_fp8_e4m3fn | 19.0 GB | Comfy-Org/Qwen-Image_ComfyUI |
| qwen_2.5_vl_7b_fp8_scaled | 8.7 GB | Comfy-Org/HunyuanVideo_1.5_repackaged |
| Qwen-Image-InstantX-ControlNet-Union | 3.3 GB | Comfy-Org/Qwen-Image-InstantX-ControlNets |
| lotus-depth-d-v1-1 | 1.6 GB | Comfy-Org/lotus |
| Qwen-Image-Lightning-4steps-V1.0 | 1.6 GB | lightx2v/Qwen-Image-Lightning |
| vae-ft-mse-840000-ema-pruned | 0.33 GB | stabilityai/sd-vae-ft-mse-original |
| qwen_image_vae | 0.24 GB | Comfy-Org/Qwen-Image_ComfyUI |

`qwen_image_fp8_e4m3fn` is base Qwen-Image, a **different model** from
`qwen_image_edit_2511_fp8mixed` in the set above, despite the similar name and
size. Both are needed if you run both workflows.

The text encoder and `qwen_image_vae` in this set are **inferred, not
observed**: ComfyUI's missing-models list did not name them because they were
already on disk from `qwen-edit` when the workflow was first opened. A
missing-models list reports what is missing, not what a workflow needs, so it
is never a complete set description. If a fresh `qwen-depth` restore leaves a
red node, this is the first place to look.

**Custom nodes**: ComfyUI-Manager (cloned), then KJNodes, Civicomfy and
RunpodDirect installed through Manager by name.

## Why size is checked, and why not exactly

Every download is size-checked against the byte count in `restore.sh`'s own
tables — the Wan sizes recorded from the original volume, the Qwen ones from
HuggingFace when the paths were verified. `models.tsv` is the inventory
snapshot of that volume, not the restore's input; its first-MB hash column
exists to tell same-size files apart on the source (the two Wan LoRAs), and
is not used on restore because upstream re-packs change the safetensors
header. The check is deliberately **not** an equality test.

The first version demanded exact bytes and would have rejected all four
diffusion/encoder files: Comfy-Org had re-packed them upstream, about 0.01%
larger. That is a newer revision of the same model, not a wrong file.

So the rule is: **more than 2% off fails, anything less is reported and
accepted**. A wrong path yields a file orders of magnitude off, not 0.01%.
`hf` verifies its own download integrity; this guards against the path
pointing at a different model entirely.

Verified 2026-09-10 — all six paths resolve, both LoRAs byte-exact, the other
four newer re-packs. First real run completed clean.

## inventory.sh

The other half: run it on an existing install to produce the manifests here.

```sh
bash inventory.sh /path/to/ComfyUI [out.tgz]   # default: comfyui-extract.tgz beside the root
```

It captures workflows, `input/` (the start frames are yours; taken when
under 200 MB, listed for you to decide when over), custom nodes with git
remotes and commits where they exist, a model manifest, and a disk-usage
breakdown. It also writes `REVIEW.txt` listing anything under `loras/`,
`embeddings/` or `checkpoints/` that might be **yours** rather than
downloaded — a trained LoRA is indistinguishable from a fetched one by shape,
and it is the one thing a manifest cannot replace. Read that file before
deleting any volume. `output/` is only measured, not taken: renders are
reproducible from workflow plus input.

## Notes on renting

Stateless changes the economics, and not marginally:

- **Storage costs more than bandwidth.** On Vast.ai a 60 GB volume runs about
  $18/month kept alive, while re-downloading 36 GB costs roughly $0.15 at
  $4.16/TB. Break-even is over a hundred restores a month. Destroy the
  instance; don't stop it.
- **Network speed matters more than hourly rate.** A host with 13.8 Gbps
  restores in about a minute; one at 312 Mbps takes a quarter of an hour,
  every session. That gap dwarfs a few cents an hour.
- **Nothing pins you to a region**, which is the entire point.

## Licence

MIT. Model weights and custom nodes carry their own licences.
