#!/usr/bin/env python3
"""Strip the personal parts out of a ComfyUI workflow so it can be committed.

    python3 sanitize-workflow.py <in.json> <out.json>

A ComfyUI workflow carries three things that are YOURS and should not go in a
public repo, sitting next to a lot that is stock template content and is fine:

  - LoadImage filenames. Midjourney-style exports embed the account name and
    the full prompt in the filename.
  - Positive prompt text.
  - The viewport (`extra.ds`) — not personal, just per-session noise that
    makes every diff dirty.

Everything else (model names, sampler settings, the stock negative prompt,
the template's notes) is what makes the file useful and is left alone.

Nodes live in two places: the top-level `nodes` list, and inside every
subgraph under `definitions.subgraphs[*].nodes`. Both are walked. Nothing is
inferred from position or wiring — only node type and title are used, so a
graph this script has never seen is handled by the same rules.
"""
import json
import sys

PLACEHOLDER_IMAGE = "example.png"
PLACEHOLDER_PROMPT = "<your prompt>"


def iter_nodes(workflow):
    yield from workflow.get("nodes", [])
    for subgraph in workflow.get("definitions", {}).get("subgraphs", []):
        yield from subgraph.get("nodes", [])


def sanitize_node(node):
    """Return a short description of what changed, or None."""
    widgets = node.get("widgets_values")
    if not widgets:
        return None
    node_type = node.get("type")
    title = node.get("title") or ""

    if node_type == "LoadImage":
        if widgets[0] == PLACEHOLDER_IMAGE:
            return None
        widgets[0] = PLACEHOLDER_IMAGE
        return f"LoadImage {node['id']}: filename -> {PLACEHOLDER_IMAGE}"

    if node_type == "CLIPTextEncode":
        # The stock negative prompt is template content, not yours. Anything
        # not explicitly titled as negative is treated as a prompt you wrote.
        if "negative" in title.lower():
            return None
        if widgets[0] == PLACEHOLDER_PROMPT:
            return None
        widgets[0] = PLACEHOLDER_PROMPT
        return f"CLIPTextEncode {node['id']} ({title or 'untitled'}): prompt -> {PLACEHOLDER_PROMPT}"

    return None


def iter_graphs(workflow):
    """The root graph and every subgraph — each carries its own `extra.ds`."""
    yield "root", workflow
    for subgraph in workflow.get("definitions", {}).get("subgraphs", []):
        yield f"subgraph {subgraph.get('name') or subgraph.get('id')}", subgraph


def sanitize(workflow):
    changes = [c for c in map(sanitize_node, iter_nodes(workflow)) if c]
    for label, graph in iter_graphs(workflow):
        if graph.get("extra", {}).pop("ds", None) is not None:
            changes.append(f"{label}: extra.ds viewport dropped")
    return changes


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    src, dst = argv[1], argv[2]
    with open(src, encoding="utf-8") as f:
        workflow = json.load(f)
    changes = sanitize(workflow)
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(workflow, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"{src} -> {dst}")
    for change in changes:
        print(f"  {change}")
    if not changes:
        print("  (nothing to strip)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
