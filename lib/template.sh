#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=lib/log.sh
. "$(dirname "${BASH_SOURCE[0]}")/log.sh"

render_template() {
  local tpl="$1"
  local out="$2"

  if [[ ! -f "$tpl" ]]; then
    fatal "模板不存在: $tpl"
  fi

  if command -v envsubst >/dev/null 2>&1; then
    envsubst <"$tpl" >"$out"
  else
    log_warn "未找到 envsubst，使用简单替换"
    # 简单替换占位符 ${VAR}; 对复杂模板建议安装 envsubst
    local tmp="$tpl"
    while IFS= read -r line; do
      eval "echo \"$line\""
    done <"$tmp" >"$out"
  fi
}
