#!/usr/bin/env zsh

_MLX_MODELS_DIR="$HOME/.cache/mlx-models"
_OPENCODE_CONFIG="$HOME/.config/opencode/opencode.json"

function _free_port() {
  python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()"
}

function _mlx_estimate_required_gb() {
  local model_path="$1"
  python3 - "$model_path" <<'EOF'
import json, sys, os, subprocess, re

model_path = sys.argv[1]
config_file = os.path.join(model_path, "config.json")
config = json.load(open(config_file)) if os.path.exists(config_file) else {}

# weights
weight_bytes = sum(
    os.path.getsize(os.path.join(model_path, f))
    for f in os.listdir(model_path)
    if f.endswith((".safetensors", ".npz"))
)
weights_gb = weight_bytes / 1024**3

# KV cache at 32K context, bf16
num_layers = config.get("num_hidden_layers", 32)
num_kv_heads = config.get("num_key_value_heads", config.get("num_attention_heads", 32))
hidden = config.get("hidden_size", 4096)
num_heads = config.get("num_attention_heads", 32)
head_dim = config.get("head_dim", hidden // num_heads)
context = 32768
kv_cache_gb = (num_layers * num_kv_heads * head_dim * context * 2 * 2) / 1024**3

# MoE models share experts across tokens — smaller activation footprint
is_moe = bool(config.get("num_experts"))
activation_gb = 2.0 if is_moe else 10.0

total = weights_gb + kv_cache_gb + activation_gb
print(f"{weights_gb:.1f} {kv_cache_gb:.1f} {activation_gb:.1f} {total:.1f} {'moe' if is_moe else 'dense'}")
EOF
}

function _mlx_available_ram_gb() {
  vm_stat | python3 -c "
import sys, re, subprocess
data = sys.stdin.read()
page = 16384
wired = int(re.search(r'Pages wired down:\s+(\d+)', data).group(1))
total = int(subprocess.run(['sysctl','-n','hw.memsize'], capture_output=True, text=True).stdout.strip())
# total minus wired (kernel, non-reclaimable) minus 4GB buffer for active processes
available = (total / 1024**3) - (wired * page / 1024**3) - 4
print(f'{available:.1f}')
"
}

function _mlx_check_model_fits() {
  local model_path="$1"
  local available_gb
  available_gb=$(_mlx_available_ram_gb)

  local result
  result=$(_mlx_estimate_required_gb "$model_path")
  local weights_gb kv_gb activation_gb required_gb arch
  read weights_gb kv_gb activation_gb required_gb arch <<< "$result"

  echo "Model: ${weights_gb}GB weights + ${kv_gb}GB KV cache + ${activation_gb}GB activations = ${required_gb}GB ($arch) | Available: ${available_gb}GB"

  if python3 -c "import sys; sys.exit(0 if $required_gb <= $available_gb else 1)"; then
    return 0
  else
    echo "Warning: model requires ~${required_gb}GB but only ${available_gb}GB available" >&2
    read -r "reply?Run anyway? [y/N] "
    [[ "$reply" =~ ^[Yy]$ ]] || return 1
  fi
}

function mlx_popular() {
  python3 <<'EOF'
import json, re, subprocess
from urllib.request import urlopen
from urllib.error import URLError
from concurrent.futures import ThreadPoolExecutor, as_completed

def available_ram_gb():
    vm = subprocess.run(['vm_stat'], capture_output=True, text=True).stdout
    page = 16384
    wired = int(re.search(r'Pages wired down:\s+(\d+)', vm).group(1))
    total = int(subprocess.run(['sysctl','-n','hw.memsize'], capture_output=True, text=True).stdout.strip())
    return (total / 1024**3) - (wired * page / 1024**3) - 4

def fetch_json(url):
    try:
        with urlopen(url, timeout=8) as r:
            return json.loads(r.read())
    except Exception:
        return None

def estimate(model_id):
    meta = fetch_json(f"https://huggingface.co/api/models/{model_id}")
    if not meta:
        return None
    weight_bytes = sum(
        s.get('size', 0) for s in meta.get('siblings', [])
        if s['rfilename'].endswith(('.safetensors', '.npz'))
    )
    weights_gb = weight_bytes / 1024**3
    config = fetch_json(f"https://huggingface.co/{model_id}/resolve/main/config.json") or {}
    num_layers = config.get('num_hidden_layers', 32)
    num_kv_heads = config.get('num_key_value_heads', config.get('num_attention_heads', 32))
    hidden = config.get('hidden_size', 4096)
    num_heads = config.get('num_attention_heads', 32)
    head_dim = config.get('head_dim', hidden // num_heads)
    kv_gb = (num_layers * num_kv_heads * head_dim * 32768 * 2 * 2) / 1024**3
    is_moe = bool(config.get('num_experts'))
    act_gb = 2.0 if is_moe else 10.0
    total = weights_gb + kv_gb + act_gb
    return total, 'moe' if is_moe else 'dense'

def fetch_list(url):
    data = fetch_json(url) or []
    return sorted(data, key=lambda x: -x.get('downloads', 0))

avail = available_ram_gb()

sections = [
    ("Top Coding Models (mlx-community)",
     "https://huggingface.co/api/models?author=mlx-community&search=coder&sort=downloads&limit=10"),
    ("Most Downloaded (mlx-community)",
     "https://huggingface.co/api/models?author=mlx-community&sort=downloads&limit=15"),
]

for title, url in sections:
    models = fetch_list(url)
    ids = [m['id'] for m in models]
    dls = {m['id']: m.get('downloads', 0) for m in models}

    print(f"\n=== {title} ===")
    with ThreadPoolExecutor(max_workers=8) as ex:
        futures = {ex.submit(estimate, mid): mid for mid in ids}
        results = {}
        for f in as_completed(futures):
            results[futures[f]] = f.result()

    max_id = max(len(i) for i in ids)
    req_col = 18
    print(f"  {'DOWNLOADS':>12}  {'MODEL':<{max_id}}  {'REQUIRED':<{req_col}}  FIT")
    print(f"  {'-'*12}  {'-'*max_id}  {'-'*req_col}  ---")
    for mid in ids:
        est = results.get(mid)
        if est:
            req_gb, arch = est
            fit = "[ok]" if req_gb <= avail else "[too large]"
            req_str = f"~{req_gb:.1f}GB ({arch})"
        else:
            fit = "[?]"
            req_str = "unknown"
        print(f"  {dls[mid]:>12,}  {mid:<{max_id}}  {req_str:<{req_col}}  {fit}")

print(f"\nAvailable RAM: ~{avail:.1f}GB")
print("Run: mlx_add <model-id>")
EOF
}

function mlx_remove() {
  local model="$1"

  if [[ -z "$model" ]]; then
    local models
    models=(${(f)"$(find "$_MLX_MODELS_DIR" -name config.json -maxdepth 4 2>/dev/null \
      | sed "s|$_MLX_MODELS_DIR/||;s|/config.json||" | sort)"})
    if [[ ${#models[@]} -eq 0 ]]; then
      echo "No local models found." >&2
      return 1
    fi
    local model_names=() model_sizes=() model_reqs=() model_fits=()
    local available_ram_gb
    available_ram_gb=$(_mlx_available_ram_gb)
    local max_name=0 max_size=0 max_req=0
    local mpath est req_gb arch req_label fit size
    for m in "${models[@]}"; do
      mpath="$_MLX_MODELS_DIR/$m"
      size=$(du -sh "$mpath" 2>/dev/null | awk '{print $1}')
      est=$(_mlx_estimate_required_gb "$mpath" 2>/dev/null)
      req_gb=$(echo "$est" | awk '{print $4}')
      arch=$(echo "$est" | awk '{print $5}')
      req_label="~${req_gb}GB ($arch)"
      if echo "$est" | awk -v avail="$available_ram_gb" '{exit ($4 <= avail) ? 0 : 1}'; then
        fit="[ok]"
      else
        fit="[too large]"
      fi
      model_names+=("$m") model_sizes+=("$size") model_reqs+=("$req_label") model_fits+=("$fit")
      [[ ${#m} -gt $max_name ]] && max_name=${#m}
      [[ ${#size} -gt $max_size ]] && max_size=${#size}
      [[ ${#req_label} -gt $max_req ]] && max_req=${#req_label}
    done
    echo "Downloaded models:"
    printf "     %-${max_name}s  %-${max_size}s  %-${max_req}s  %s\n" "MODEL" "SIZE" "REQUIRED" "FIT"
    printf "     %-${max_name}s  %-${max_size}s  %-${max_req}s  %s\n" "$(printf '%0.s-' $(seq 1 $max_name))" "$(printf '%0.s-' $(seq 1 $max_size))" "$(printf '%0.s-' $(seq 1 $max_req))" "---"
    local i=1
    for m in "${model_names[@]}"; do
      printf "  %d) %-${max_name}s  %-${max_size}s  %-${max_req}s  %s\n" $i "$m" "${model_sizes[$i]}" "${model_reqs[$i]}" "${model_fits[$i]}"
      i=$((i+1))
    done
    local reply
    while true; do
      read -r "reply?Select model to delete (1-${#model_names[@]}): "
      if [[ "$reply" =~ ^[0-9]+$ ]] && (( reply >= 1 && reply <= ${#model_names[@]} )); then
        model="${model_names[$reply]}"
        break
      fi
      echo "Invalid selection" >&2
    done
  fi

  local model_path="$_MLX_MODELS_DIR/$model"
  if [[ ! -d "$model_path" ]]; then
    echo "Not found: $model_path" >&2
    return 1
  fi

  local size
  size=$(du -sh "$model_path" | awk '{print $1}')
  read -r "reply?Delete $model ($size)? [y/N] "
  [[ "$reply" =~ ^[Yy]$ ]] || return 1

  rm -rf "$model_path"
  echo "Deleted $model"
}

function _mlx_ensure_uv() {
  if ! command -v uv &>/dev/null; then
    read -r "reply?uv not found. Install via brew? [y/N] "
    [[ "$reply" =~ ^[Yy]$ ]] || return 1
    brew install uv || return 1
  fi
}

function _mlx_ensure_tool() {
  local tool="$1"
  if ! uv tool list 2>/dev/null | grep -q "$tool"; then
    read -r "reply?$tool not found. Install via uv? [y/N] "
    [[ "$reply" =~ ^[Yy]$ ]] || return 1
    uv tool install "$tool" || return 1
  fi
}

function mlx_add() {
  local model="$1"

  if [[ -z "$model" ]]; then
    echo "Usage: mlx_add <hf-model-id>" >&2
    echo "Example: mlx_add mlx-community/Qwen2.5-Coder-32B-Instruct-4bit" >&2
    return 1
  fi

  _mlx_ensure_uv || return 1
  _mlx_ensure_tool mlx-lm || return 1

  echo "Downloading $model..."
  uvx --from huggingface-hub hf download "$model" --local-dir "$_MLX_MODELS_DIR/$model" || return 1
  echo "Downloaded $model"
}


function opencode_local() {
  local model="$1"

  _mlx_ensure_uv || return 1
  _mlx_ensure_tool mlx-lm || return 1

  if ! command -v jq &>/dev/null; then
    read -r "reply?jq not found. Install via brew? [y/N] "
    [[ "$reply" =~ ^[Yy]$ ]] || return 1
    brew install jq || return 1
  fi

  if [[ -z "$model" ]]; then
    local models model_names=() model_reqs=() model_fits=()
    # scan for dirs that contain config.json (model roots)
    models=(${(f)"$(find "$_MLX_MODELS_DIR" -name config.json -maxdepth 4 2>/dev/null \
      | sed "s|$_MLX_MODELS_DIR/||;s|/config.json||" | sort)"})
    if [[ ${#models[@]} -eq 0 ]]; then
      echo "No local models found in $_MLX_MODELS_DIR"
      read -r "reply?Show popular models? [y/N] "
      [[ "$reply" =~ ^[Yy]$ ]] && mlx_popular
      return 1
    fi
    local available_ram_gb
    available_ram_gb=$(_mlx_available_ram_gb)
    local mpath fit req_label est req_gb arch
    for m in "${models[@]}"; do
      mpath="$_MLX_MODELS_DIR/$m"
      fit="?" req_label="?"
      if [[ -d "$mpath" ]]; then
        local has_weights
        has_weights=$(find "$mpath" -maxdepth 1 -name "*.safetensors" -o -name "*.npz" 2>/dev/null | head -1)
        if [[ -z "$has_weights" ]]; then
          req_label="-"
          fit="[incomplete]"
        else
          est=$(_mlx_estimate_required_gb "$mpath" 2>/dev/null)
          req_gb=$(echo "$est" | awk '{print $4}')
          arch=$(echo "$est" | awk '{print $5}')
          req_label="~${req_gb}GB ($arch)"
          if echo "$est" | awk -v avail="$available_ram_gb" '{exit ($4 <= avail) ? 0 : 1}'; then
            fit="[ok]"
          else
            fit="[too large]"
          fi
        fi
      else
        req_label="-"
        fit="[not downloaded]"
      fi
      model_names+=("$m")
      model_reqs+=("$req_label")
      model_fits+=("$fit")
    done
    local max_name=0 max_req=0
    for m in "${model_names[@]}"; do [[ ${#m} -gt $max_name ]] && max_name=${#m}; done
    for r in "${model_reqs[@]}"; do [[ ${#r} -gt $max_req ]] && max_req=${#r}; done
    local n_models=${#model_names[@]}
    local opt_popular=$(( n_models + 1 ))
    local opt_add=$(( n_models + 2 ))
    local reply
    while true; do
      echo "Available models:"
      printf "     %-${max_name}s  %-${max_req}s  %s\n" "MODEL" "REQUIRED" "FIT"
      printf "     %-${max_name}s  %-${max_req}s  %s\n" "$(printf '%0.s-' $(seq 1 $max_name))" "$(printf '%0.s-' $(seq 1 $max_req))" "---"
      local i=1
      for m in "${model_names[@]}"; do
        printf "  %d) %-${max_name}s  %-${max_req}s  %s\n" $i "$m" "${model_reqs[$i]}" "${model_fits[$i]}"
        i=$((i+1))
      done
      printf "  %d) Show popular models\n" $opt_popular
      printf "  %d) Download a new model\n" $opt_add
      read -r "reply?Select (1-${opt_add}): "
      if [[ "$reply" =~ ^[0-9]+$ ]]; then
        if (( reply >= 1 && reply <= n_models )); then
          model="${model_names[$reply]}"
          break
        elif (( reply == opt_popular )); then
          mlx_popular
        elif (( reply == opt_add )); then
          read -r "reply?Model ID (e.g. mlx-community/Qwen2.5-Coder-32B-Instruct-4bit): "
          mlx_add "$reply" || return 1
          # re-scan after download
          models=(${(f)"$(find "$_MLX_MODELS_DIR" -name config.json -maxdepth 4 2>/dev/null \
            | sed "s|$_MLX_MODELS_DIR/||;s|/config.json||" | sort)"})
          model_names=() model_reqs=() model_fits=()
          available_ram_gb=$(_mlx_available_ram_gb)
          for m in "${models[@]}"; do
            mpath="$_MLX_MODELS_DIR/$m"
            fit="?" req_label="?"
            if [[ -d "$mpath" ]]; then
              est=$(_mlx_estimate_required_gb "$mpath" 2>/dev/null)
              req_gb=$(echo "$est" | awk '{print $4}')
              arch=$(echo "$est" | awk '{print $5}')
              req_label="~${req_gb}GB ($arch)"
              if echo "$est" | awk -v avail="$available_ram_gb" '{exit ($4 <= avail) ? 0 : 1}'; then
                fit="[ok]"
              else
                fit="[too large]"
              fi
            else
              req_label="-" fit="[not downloaded]"
            fi
            model_names+=("$m") model_reqs+=("$req_label") model_fits+=("$fit")
          done
          max_name=0 max_req=0
          for m in "${model_names[@]}"; do [[ ${#m} -gt $max_name ]] && max_name=${#m}; done
          for r in "${model_reqs[@]}"; do [[ ${#r} -gt $max_req ]] && max_req=${#r}; done
          n_models=${#model_names[@]}
          opt_popular=$(( n_models + 1 ))
          opt_add=$(( n_models + 2 ))
        fi
      else
        echo "Invalid selection" >&2
      fi
    done
  fi

  local model_path="$_MLX_MODELS_DIR/$model"
  if [[ ! -d "$model_path" ]]; then
    echo "$model not downloaded locally."
    read -r "reply?Download now? [y/N] "
    if [[ "$reply" =~ ^[Yy]$ ]]; then
      mlx_add "$model" || return 1
    else
      return 1
    fi
  fi

  local has_weights
  has_weights=$(find "$model_path" -maxdepth 1 -name "*.safetensors" -o -name "*.npz" 2>/dev/null | head -1)
  if [[ -z "$has_weights" ]]; then
    echo "Error: $model has no weight files — download may be incomplete." >&2
    read -r "reply?Re-download now? [y/N] "
    [[ "$reply" =~ ^[Yy]$ ]] || return 1
    mlx_add "$model" || return 1
  fi

  _mlx_check_model_fits "$model_path" || return 1

  pkill -f "mlx_lm.server" 2>/dev/null
  sleep 1

  local mlx_port
  mlx_port=$(_free_port)

  echo "Starting mlx_lm.server for $model (loading weights, may take a minute)..."
  HF_HUB_OFFLINE=1 mlx_lm.server --model "$model_path" --port "$mlx_port" \
    --chat-template-args '{"enable_thinking":false}' &>/tmp/mlx_lm.log &

  tail -f /tmp/mlx_lm.log &
  local tail_pid=$!
  local attempts=0
  until curl -sf "http://localhost:$mlx_port/v1/models" &>/dev/null; do
    if grep -q "FileNotFoundError\|No safetensors found" /tmp/mlx_lm.log 2>/dev/null; then
      kill $tail_pid 2>/dev/null
      echo "Error: model weights not found. Try: mlx_add $model" >&2
      return 1
    fi
    sleep 5
    attempts=$((attempts + 1))
    if [[ $attempts -ge 60 ]]; then
      kill $tail_pid 2>/dev/null
      echo "mlx_lm.server failed to start. Check /tmp/mlx_lm.log" >&2
      return 1
    fi
  done
  kill $tail_pid 2>/dev/null
  wait $tail_pid 2>/dev/null

  local model_id
  model_id=$(curl -sf "http://localhost:$mlx_port/v1/models" | jq -r '.data[] | select(.id | startswith("/")) | .id' | head -1)
  [[ -z "$model_id" ]] && model_id="$model"

  jq --arg base "http://localhost:$mlx_port/v1" --arg model "$model_id" --arg name "$model" '
    .provider.mlx = {
      "npm": "@ai-sdk/openai-compatible",
      "name": "MLX Local",
      "options": {"baseURL": $base},
      "models": {($model): {"name": $name}}
    }
  ' "$_OPENCODE_CONFIG" > /tmp/opencode_mlx.json && mv /tmp/opencode_mlx.json "$_OPENCODE_CONFIG"

  echo "opencode → $model via localhost:$mlx_port"
  opencode "$@"

  jq 'del(.provider.mlx)' "$_OPENCODE_CONFIG" > /tmp/opencode_mlx.json && mv /tmp/opencode_mlx.json "$_OPENCODE_CONFIG"
  pkill -f "mlx_lm.server" 2>/dev/null
}
