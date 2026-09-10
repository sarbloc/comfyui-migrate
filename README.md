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
bash restore.sh /path/to/ComfyUI      # default: /workspace/ComfyUI
```

Then drop your workflow JSONs into `<ComfyUI>/user/default/workflows/`, or
drag them onto the ComfyUI canvas in the browser.

**Needs ~71 GB free** where ComfyUI lives, so a 120 GB volume. Check with
`df -h` first — the usual failure is a small container disk beside a larger
volume, with ComfyUI on the wrong one.

## What it restores

**Models** (~65 GB, from HuggingFace). Two families, one environment: the Wan
video workflow and the Qwen edit workflow are being merged, so both are
present at once rather than offered as selectable sets.

Wan 2.2 image-to-video:

| file | size | repo |
| --- | --- | --- |
| wan2.2_i2v_high_noise_14B_fp8_scaled | 13.3 GB | Comfy-Org/Wan_2.2_ComfyUI_Repackaged |
| wan2.2_i2v_low_noise_14B_fp8_scaled | 13.3 GB | Comfy-Org/Wan_2.2_ComfyUI_Repackaged |
| umt5_xxl_fp8_e4m3fn_scaled | 6.3 GB | Comfy-Org/Wan_2.1_ComfyUI_Repackaged |
| wan_2.1_vae | 0.24 GB | Comfy-Org/Wan_2.1_ComfyUI_Repackaged |
| lightx2v_4steps_lora_v1_high_noise | 1.1 GB | Comfy-Org/Wan_2.2_ComfyUI_Repackaged |
| lightx2v_4steps_lora_v1_low_noise | 1.1 GB | Comfy-Org/Wan_2.2_ComfyUI_Repackaged |

Qwen-Image-Edit 2511:

| file | size | repo |
| --- | --- | --- |
| qwen_image_edit_2511_fp8mixed | 19.1 GB | Comfy-Org/Qwen-Image-Edit_ComfyUI |
| qwen_2.5_vl_7b_fp8_scaled | 8.7 GB | Comfy-Org/HunyuanVideo_1.5_repackaged |
| Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16 | 0.79 GB | lightx2v/Qwen-Image-Edit-2511-Lightning |
| qwen_image_vae | 0.24 GB | Comfy-Org/Qwen-Image_ComfyUI |

The Qwen text encoder genuinely lives in a HunyuanVideo repo — Comfy-Org
reuses repacks across model families. Verified by HTTP; not a typo.

**Custom nodes**: ComfyUI-Manager (cloned), then KJNodes, Civicomfy and
RunpodDirect installed through Manager by name.

## Why size is checked, and why not exactly

Every download is size-checked against `models.tsv`, recorded from the
original volume. The check is deliberately **not** an equality test.

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
bash inventory.sh /path/to/ComfyUI   # writes /workspace/comfyui-extract.tgz
```

It captures workflows, custom nodes with git remotes and commits where they
exist, a model manifest, and a disk-usage breakdown. It also writes
`REVIEW.txt` listing anything under `loras/`, `embeddings/` or `checkpoints/`
that might be **yours** rather than downloaded — a trained LoRA is
indistinguishable from a fetched one by shape, and it is the one thing a
manifest cannot replace. Read that file before deleting any volume.

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
