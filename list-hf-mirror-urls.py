#!/usr/bin/env python3
"""List Hugging Face repo files and print 仙宫云 mirror download URLs.

Stdlib only (urllib). For verification on the GPU box before/alongside downloads.

Usage:
  python3 list-hf-mirror-urls.py Qwen/Qwen-Image-2.1
  python3 list-hf-mirror-urls.py Qwen/Qwen-Image-2.1 main http://hf.x-gpu.com
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request

DEFAULT_MIRROR = "http://hf.x-gpu.com"
HF_API = "https://huggingface.co"
USER_AGENT = "list-hf-mirror-urls/1.0"


def fetch_tree(api_base: str, repo_id: str, branch: str, path: str = "") -> list:
    url = f"{api_base.rstrip('/')}/api/models/{repo_id}/tree/{branch}"
    if path:
        url += f"/{path}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def list_files(api_base: str, repo_id: str, branch: str, path: str = "") -> list[str]:
    files: list[str] = []
    for entry in fetch_tree(api_base, repo_id, branch, path):
        etype = entry.get("type")
        epath = entry.get("path")
        if not epath:
            continue
        if etype == "file":
            files.append(epath)
        elif etype == "directory":
            files.extend(list_files(api_base, repo_id, branch, epath))
    return files


def resolve_api_base(repo_id: str, branch: str, mirror_base: str) -> str:
    candidates = [HF_API, mirror_base.rstrip("/")]
    last_err: Exception | None = None
    for base in candidates:
        try:
            fetch_tree(base, repo_id, branch)
            return base
        except Exception as exc:  # noqa: BLE001 — try next API base
            last_err = exc
            print(f"warn: list via {base} failed: {exc}", file=sys.stderr)
    raise SystemExit(f"error: could not list {repo_id}@{branch}: {last_err}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Recursively list HF repo files and print 仙宫云 mirror URLs."
    )
    parser.add_argument("repo_id", help="Hugging Face repo id, e.g. Qwen/Qwen-Image-2.1")
    parser.add_argument("branch", nargs="?", default="main", help="Branch / revision (default: main)")
    parser.add_argument(
        "mirror_base",
        nargs="?",
        default=DEFAULT_MIRROR,
        help=f"Mirror base URL (default: {DEFAULT_MIRROR})",
    )
    args = parser.parse_args()

    repo_id = args.repo_id
    branch = args.branch
    mirror = args.mirror_base.rstrip("/")

    api_base = resolve_api_base(repo_id, branch, mirror)
    files = list_files(api_base, repo_id, branch)
    files.sort()

    print(f"# repo={repo_id} branch={branch} api={api_base} count={len(files)}", file=sys.stderr)
    for path in files:
        url = f"{mirror}/{repo_id}/resolve/{branch}/{path}"
        print(f"{path}\t{url}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
