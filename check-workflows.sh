#!/usr/bin/env bash
# Refuse to let a workflow with personal data into the repo.
#
#   bash check-workflows.sh [workflows/*.json]
#
# This is the guard behind sanitize-workflow.py: the sanitiser is easy to
# forget, this is not (CI runs it). Every committed workflow must parse, must
# carry no usernames or local paths, and every image/prompt slot must hold
# the sanitiser's placeholder. Exit 1 on the first file that fails.
set -uo pipefail

cd "$(dirname "$0")" || exit 1
files=("$@")
[[ ${#files[@]} -eq 0 ]] && files=(workflows/*.json)

# Strings that mean a file was not sanitised. Extend when you find a new one.
FORBIDDEN='sarbloc|/home/|/Users/|/workspace|[A-Za-z]:\\'

fail=0
for f in "${files[@]}"; do
  [[ -f "$f" ]] || { echo "  MISSING  $f" >&2; fail=1; continue; }

  if grep -Eq "$FORBIDDEN" "$f"; then
    echo "  PERSONAL  $f — matches: $(grep -Eo "$FORBIDDEN" "$f" | sort -u | tr '\n' ' ')" >&2
    fail=1
    continue
  fi

  if ! python3 - "$f" <<'EOF'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    wf = json.load(fh)

def nodes(wf):
    yield from wf.get("nodes", [])
    for sg in wf.get("definitions", {}).get("subgraphs", []):
        yield from sg.get("nodes", [])

bad = []
for n in nodes(wf):
    w = n.get("widgets_values") or []
    if not w:
        continue
    if n.get("type") == "LoadImage" and w[0] != "example.png":
        bad.append(f"LoadImage {n['id']} has a real filename")
    if n.get("type") == "CLIPTextEncode" and "negative" not in (n.get("title") or "").lower() \
            and w[0] != "<your prompt>":
        bad.append(f"CLIPTextEncode {n['id']} has a real prompt")
if "ds" in wf.get("extra", {}):
    bad.append("extra.ds viewport present")
for b in bad:
    print(f"    {b}", file=sys.stderr)
sys.exit(1 if bad else 0)
EOF
  then
    echo "  UNSANITISED  $f" >&2
    fail=1
    continue
  fi

  echo "  ok  $f"
done

exit "$fail"
