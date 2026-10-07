#!/usr/bin/env bash
# Download a full Hugging Face repo via 仙宫云 (x-gpu) mirror.
# Lists files from the HF Hub API (or mirror API fallback), then wget -nc each file.
set -euo pipefail

REPO_ID="${REPO_ID:-Qwen/Qwen-Image-2.1}"
BRANCH="${BRANCH:-main}"
MIRROR_BASE="${MIRROR_BASE:-http://hf.x-gpu.com}"
# LOCAL_DIR may be set via env; positional args override below.
LOCAL_DIR="${LOCAL_DIR:-}"

# Optional positional overrides: ./download-hf-mirror.sh [REPO_ID] [LOCAL_DIR]
if [[ "${1:-}" != "" && "${1:-}" != -* ]]; then
  REPO_ID="$1"
fi
if [[ "${2:-}" != "" && "${2:-}" != -* ]]; then
  LOCAL_DIR="$2"
fi

# Default local dir: /root/ai-stack/models/<repo-name>
REPO_NAME="${REPO_ID##*/}"
if [[ -z "${LOCAL_DIR}" ]]; then
  LOCAL_DIR="/root/ai-stack/models/${REPO_NAME}"
fi

API_BASES=(
  "https://huggingface.co"
  "${MIRROR_BASE}"
)

usage() {
  cat <<EOF
Usage: REPO_ID=... LOCAL_DIR=... BRANCH=... MIRROR_BASE=... $0 [REPO_ID] [LOCAL_DIR]

Download every file in a Hugging Face model repo via the 仙宫云 mirror,
preserving the remote directory layout under LOCAL_DIR.

Defaults:
  REPO_ID      Qwen/Qwen-Image-2.1
  LOCAL_DIR    /root/ai-stack/models/<repo-name>
  BRANCH       main
  MIRROR_BASE  http://hf.x-gpu.com

Examples:
  $0
  $0 Qwen/Qwen-Image-2.1 /root/ai-stack/models/Qwen-Image-2.1
  REPO_ID=Qwen/Qwen2.5-7B-Instruct LOCAL_DIR=/data/models/Qwen2.5-7B-Instruct $0
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

for cmd in curl wget python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command not found: $cmd" >&2
    exit 1
  fi
done

echo "==> repo:        ${REPO_ID}"
echo "==> branch:      ${BRANCH}"
echo "==> mirror:      ${MIRROR_BASE}"
echo "==> local dir:   ${LOCAL_DIR}"
echo

mkdir -p "${LOCAL_DIR}"

# Recursively list all file paths via HF Hub tree API (no auth for public repos).
# Tries huggingface.co first, then the mirror API if that fails.
LIST_FILE="$(mktemp)"
trap 'rm -f "${LIST_FILE}"' EXIT

export REPO_ID BRANCH
export API_BASES_CSV
API_BASES_CSV="$(IFS=,; echo "${API_BASES[*]}")"

python3 - <<'PY' >"${LIST_FILE}"
import json
import os
import sys
import urllib.error
import urllib.request

repo_id = os.environ["REPO_ID"]
branch = os.environ["BRANCH"]
api_bases = [b.strip().rstrip("/") for b in os.environ["API_BASES_CSV"].split(",") if b.strip()]

def fetch_tree(api_base: str, path: str = ""):
    url = f"{api_base}/api/models/{repo_id}/tree/{branch}"
    if path:
        url += f"/{path}"
    req = urllib.request.Request(url, headers={"User-Agent": "download-hf-mirror/1.0"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)

def list_files(api_base: str, path: str = ""):
    entries = fetch_tree(api_base, path)
    files = []
    for entry in entries:
        etype = entry.get("type")
        epath = entry.get("path")
        if not epath:
            continue
        if etype == "file":
            files.append(epath)
        elif etype == "directory":
            files.extend(list_files(api_base, epath))
    return files

last_err = None
files = None
used_base = None
for base in api_bases:
    try:
        files = list_files(base)
        used_base = base
        break
    except Exception as exc:  # noqa: BLE001 — surface any listing failure and try next base
        last_err = exc
        print(f"warn: list via {base} failed: {exc}", file=sys.stderr)

if files is None:
    print(f"error: could not list repo files from any API base: {last_err}", file=sys.stderr)
    sys.exit(2)

print(f"info: listed {len(files)} files via {used_base}", file=sys.stderr)
for path in files:
    print(path)
PY

TOTAL="$(wc -l <"${LIST_FILE}" | tr -d ' ')"
if [[ "${TOTAL}" -eq 0 ]]; then
  echo "error: file list is empty for ${REPO_ID}@${BRANCH}" >&2
  exit 2
fi

echo "==> files to fetch: ${TOTAL}"
echo

OK=0
SKIPPED=0
FAILED=0
FAILED_PATHS=()

while IFS= read -r relpath || [[ -n "${relpath}" ]]; do
  [[ -z "${relpath}" ]] && continue

  dest="${LOCAL_DIR}/${relpath}"
  dest_dir="$(dirname "${dest}")"
  mkdir -p "${dest_dir}"

  url="${MIRROR_BASE}/${REPO_ID}/resolve/${BRANCH}/${relpath}"

  if [[ -f "${dest}" ]]; then
    echo "[skip] ${relpath}"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo "[get ] ${relpath}"
  # wget -nc: skip if exists (belt-and-suspenders with the check above)
  # --progress=dot:giga keeps logs readable for large safetensors
  if wget -nc --progress=dot:giga -O "${dest}" "${url}"; then
    OK=$((OK + 1))
  else
    FAILED=$((FAILED + 1))
    FAILED_PATHS+=("${relpath}")
    # Remove partial empty file so a retry can re-download
    if [[ -f "${dest}" && ! -s "${dest}" ]]; then
      rm -f "${dest}"
    fi
  fi
done <"${LIST_FILE}"

echo
echo "==> summary"
echo "    ok:      ${OK}"
echo "    skipped: ${SKIPPED}"
echo "    failed:  ${FAILED}"
echo "    total:   ${TOTAL}"
echo "    local:   ${LOCAL_DIR}"

if [[ "${FAILED}" -gt 0 ]]; then
  echo
  echo "==> failed paths:"
  for p in "${FAILED_PATHS[@]}"; do
    echo "    - ${p}"
  done
  exit 1
fi

echo "==> done"
