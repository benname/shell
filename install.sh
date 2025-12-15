#!/usr/bin/env bash

set -euo pipefail

# 安装包地址（可用环境变量覆盖）
# 默认指向公开仓库 benname/shell main 分支 tarball
# 离线/内网可改为预签名或自定义 HTTP 链接
REPO_TARBALL="${REPO_TARBALL:-https://github.com/benname/shell/archive/refs/heads/main.tar.gz}"
INSTALL_DIR="${INSTALL_DIR:-/opt/xray}"

run_as_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    sudo "$@"
  else
    "$@"
  fi
}

main() {
  local tmp
  tmp="$(mktemp -d)"
  echo "[INFO] 下载安装包: $REPO_TARBALL"
  curl -fL "$REPO_TARBALL" -o "$tmp/xray.tar.gz"

  echo "[INFO] 解压到临时目录"
  tar -xzf "$tmp/xray.tar.gz" -C "$tmp"

  local src_dir
  # 优先匹配 xray 前缀，否则取第一个目录
  src_dir="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d -name "*xray*" ! -path "$tmp" | head -n1)"
  if [[ -z "$src_dir" ]]; then
    src_dir="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d ! -path "$tmp" | head -n1)"
  fi
  if [[ -z "$src_dir" ]]; then
    echo "[ERROR] 未找到解压目录" >&2
    exit 1
  fi

  echo "[INFO] 安装到 $INSTALL_DIR"
  run_as_root mkdir -p "$INSTALL_DIR"
  run_as_root rm -rf "${INSTALL_DIR:?}/"*
  run_as_root cp -r "$src_dir"/. "$INSTALL_DIR"/

  run_as_root chmod +x "$INSTALL_DIR"/xray.sh "$INSTALL_DIR"/lib/*.sh "$INSTALL_DIR"/scripts/*.sh

  echo "[INFO] 运行安装并启动服务"
  run_as_root "$INSTALL_DIR/xray.sh" install --start

  echo "[INFO] 安装完成，可直接使用: xray doctor / xray add ..."
}

main "$@"
