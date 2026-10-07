#!/usr/bin/env bash
# Serial bootstrap of 仙宫云 AI stack models (one repo after another).
# Bandwidth is limited — do NOT parallelize these downloads.
#
# Prerequisites on the GPU box:
#   - bash, wget, curl, python3
#   - huggingface_hub CLI:  pip install "huggingface_hub[cli]"
#   - this repo's download-hf-mirror.sh next to this script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIRROR_DOWNLOAD="${SCRIPT_DIR}/download-hf-mirror.sh"
MODELS_ROOT="${MODELS_ROOT:-/root/ai-stack/models}"
HF_ENDPOINT="${HF_ENDPOINT:-http://hf.x-gpu.com}"
HF_HUB_DOWNLOAD_TIMEOUT="${HF_HUB_DOWNLOAD_TIMEOUT:-180}"
export HF_ENDPOINT HF_HUB_DOWNLOAD_TIMEOUT

usage() {
  cat <<EOF
Usage: MODELS_ROOT=... HF_ENDPOINT=... $0

Serially download the project model set under MODELS_ROOT (default: /root/ai-stack/models).

Order (serial, stop on first failure):
  1. Qwen/Qwen-Image-2.1          via download-hf-mirror.sh (wget mirror)
  2. Qwen/Qwen-Image-2.1-PE-I2I   via hf download
  3. Qwen/Qwen-Image-2.1-PE-T2I   via hf download
  4. tencent/Hy-MT2-1.8B          via hf download

Requires: pip install "huggingface_hub[cli]"
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -x "${MIRROR_DOWNLOAD}" ]]; then
  if [[ -f "${MIRROR_DOWNLOAD}" ]]; then
    chmod +x "${MIRROR_DOWNLOAD}"
  else
    echo "error: missing ${MIRROR_DOWNLOAD}" >&2
    exit 1
  fi
fi

if ! command -v hf >/dev/null 2>&1; then
  echo "error: 'hf' CLI not found. Install with:" >&2
  echo '  pip install "huggingface_hub[cli]"' >&2
  exit 1
fi

echo "==> MODELS_ROOT=${MODELS_ROOT}"
echo "==> HF_ENDPOINT=${HF_ENDPOINT}"
echo "==> HF_HUB_DOWNLOAD_TIMEOUT=${HF_HUB_DOWNLOAD_TIMEOUT}"
echo "==> downloads are SERIAL (one model after another)"
echo

download_via_mirror() {
  local repo_id="$1"
  local local_dir="$2"
  echo "------------------------------------------------------------------------"
  echo "==> [mirror/wget] ${repo_id}"
  echo "==> local: ${local_dir}"
  mkdir -p "${local_dir}"
  if ! REPO_ID="${repo_id}" LOCAL_DIR="${local_dir}" BRANCH=main \
    MIRROR_BASE="${HF_ENDPOINT}" \
    "${MIRROR_DOWNLOAD}" "${repo_id}" "${local_dir}"; then
    echo "ERROR: failed downloading ${repo_id} via mirror wget" >&2
    exit 1
  fi
  echo "SUCCESS: ${repo_id} -> ${local_dir}"
  echo
}

download_via_hf() {
  local repo_id="$1"
  local local_dir="$2"
  echo "------------------------------------------------------------------------"
  echo "==> [hf download] ${repo_id}"
  echo "==> local: ${local_dir}"
  mkdir -p "${local_dir}"
  if ! hf download "${repo_id}" --local-dir "${local_dir}"; then
    echo "ERROR: failed downloading ${repo_id} via hf download" >&2
    exit 1
  fi
  echo "SUCCESS: ${repo_id} -> ${local_dir}"
  echo
}

# 1) Qwen-Image-2.1 — wget mirror (hf download is unreliable for this repo)
download_via_mirror \
  "Qwen/Qwen-Image-2.1" \
  "${MODELS_ROOT}/Qwen/Qwen-Image-2.1"

# 2–4) remaining models — hf download through mirror endpoint
download_via_hf \
  "Qwen/Qwen-Image-2.1-PE-I2I" \
  "${MODELS_ROOT}/Qwen/Qwen-Image-2.1-PE-I2I"

download_via_hf \
  "Qwen/Qwen-Image-2.1-PE-T2I" \
  "${MODELS_ROOT}/Qwen/Qwen-Image-2.1-PE-T2I"

download_via_hf \
  "tencent/Hy-MT2-1.8B" \
  "${MODELS_ROOT}/tencent/Hy-MT2-1.8B"

echo "========================================================================"
echo "SUCCESS: all models downloaded under ${MODELS_ROOT}"
echo "  - ${MODELS_ROOT}/Qwen/Qwen-Image-2.1"
echo "  - ${MODELS_ROOT}/Qwen/Qwen-Image-2.1-PE-I2I"
echo "  - ${MODELS_ROOT}/Qwen/Qwen-Image-2.1-PE-T2I"
echo "  - ${MODELS_ROOT}/tencent/Hy-MT2-1.8B"
