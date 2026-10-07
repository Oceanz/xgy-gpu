# 仙宫云 HuggingFace 镜像下载脚本

在 [仙宫云](https://www.x-gpu.com) GPU 实例上，通过镜像 `http://hf.x-gpu.com` 拉取 Hugging Face 模型，并按远端目录结构落到本地。

`hf download` + `HF_ENDPOINT=http://hf.x-gpu.com` 对部分仓库（尤其是 `Qwen/Qwen-Image-2.1`）会失败；`download-hf-mirror.sh` 用 Hub API 递归列文件 + `wget -nc` 从镜像拉取，作为可靠兜底。

## 依赖

```bash
# 列举 / wget 镜像路径
# bash, curl, wget, python3

# init-models.sh 里其余模型需要 hf CLI
pip install "huggingface_hub[cli]"
```

## 镜像规则

```text
http://hf.x-gpu.com/{repo_id}/resolve/main/{path}
```

例如：

```text
http://hf.x-gpu.com/Qwen/Qwen-Image-2.1/resolve/main/model_index.json
```

## 环境说明（仙宫云）

- 在 GPU 实例上运行（本机/代理环境通常解析不到 `hf.x-gpu.com`）。
- 公开仓库无需 Hugging Face token；列举优先走 `https://huggingface.co/api/...`，失败时再试镜像 API。
- 模型布局（带 org 前缀）：`/root/ai-stack/models/{org}/{name}`。

## 1. 验证：列出文件与镜像 URL

Stdlib-only Python，递归列举仓库文件并打印镜像下载地址（便于在 GPU 盒上核对）：

```bash
python3 list-hf-mirror-urls.py Qwen/Qwen-Image-2.1
python3 list-hf-mirror-urls.py Qwen/Qwen-Image-2.1 main http://hf.x-gpu.com
```

输出格式：`相对路径<TAB>镜像URL`（汇总信息打在 stderr）。

## 2. 单仓库：wget 镜像下载

```bash
chmod +x download-hf-mirror.sh
./download-hf-mirror.sh Qwen/Qwen-Image-2.1 /root/ai-stack/models/Qwen/Qwen-Image-2.1
```

已存在文件会跳过（`wget -nc`）。

## 3. 初始化：串行下载全部模型

**下载是串行的（故意如此）**：带宽有限，并行更容易不稳定。`init-models.sh` 按顺序一个接一个拉完，任一步失败即非零退出。

```bash
chmod +x init-models.sh download-hf-mirror.sh
pip install "huggingface_hub[cli]"
./init-models.sh
```

顺序与落盘：

| # | Repo | 方式 | Local dir |
|---|------|------|-----------|
| 1 | `Qwen/Qwen-Image-2.1` | `download-hf-mirror.sh` (wget) | `/root/ai-stack/models/Qwen/Qwen-Image-2.1` |
| 2 | `Qwen/Qwen-Image-2.1-PE-I2I` | `hf download` | `/root/ai-stack/models/Qwen/Qwen-Image-2.1-PE-I2I` |
| 3 | `Qwen/Qwen-Image-2.1-PE-T2I` | `hf download` | `/root/ai-stack/models/Qwen/Qwen-Image-2.1-PE-T2I` |
| 4 | `tencent/Hy-MT2-1.8B` | `hf download` | `/root/ai-stack/models/tencent/Hy-MT2-1.8B` |

`hf download` 使用：

```bash
HF_ENDPOINT=http://hf.x-gpu.com
HF_HUB_DOWNLOAD_TIMEOUT=180
```

可改根目录：

```bash
MODELS_ROOT=/data/ai-stack/models ./init-models.sh
```

每个模型完成后打印 `SUCCESS: <repo> -> <dir>`；失败打印 `ERROR:` 并退出。

## 文件

| 文件 | 说明 |
|------|------|
| `list-hf-mirror-urls.py` | 列举文件 + 打印镜像 URL（验证用） |
| `download-hf-mirror.sh` | 单仓库 wget 镜像全量下载 |
| `init-models.sh` | 串行初始化上述 4 个模型 |
