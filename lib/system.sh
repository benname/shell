#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=lib/log.sh
. "$(dirname "${BASH_SOURCE[0]}")/log.sh"

ensure_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    fatal "请用 root 运行（sudo 或切换 root）"
  fi
}

detect_os() {
  local os=""
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os="${ID:-unknown}"
  fi
  printf "%s" "${os:-unknown}"
}

detect_like() {
  local like=""
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    like="${ID_LIKE:-${ID:-unknown}}"
  fi
  printf "%s" "${like:-unknown}"
}

detect_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv7) echo "armv7" ;;
    s390x) echo "s390x" ;;
    *) fatal "不支持的架构: $arch" ;;
  esac
}

detect_init() {
  if [[ -d /run/systemd/system ]]; then
    echo "systemd"
  elif command -v rc-status >/dev/null 2>&1; then
    echo "openrc"
  else
    echo "unknown"
  fi
}

detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  elif command -v pacman >/dev/null 2>&1; then
    echo "pacman"
  else
    echo "unknown"
  fi
}

ensure_cmd() {
  local cmd="$1"
  local pkg_manager
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  pkg_manager="$(detect_pkg_manager)"
  case "$pkg_manager" in
    apt)
      log_info "安装依赖 $cmd (apt)..."
      DEBIAN_FRONTEND=noninteractive apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y "$cmd"
      ;;
    dnf)
      log_info "安装依赖 $cmd (dnf)..."
      dnf install -y "$cmd"
      ;;
    yum)
      log_info "安装依赖 $cmd (yum)..."
      yum install -y "$cmd"
      ;;
    pacman)
      log_info "安装依赖 $cmd (pacman)..."
      pacman -Sy --noconfirm "$cmd"
      ;;
    *)
      fatal "无法自动安装依赖 $cmd，请手动安装"
      ;;
  esac
}

check_port_free() {
  local port="$1"
  if ss -tuln | awk '{print $5}' | grep -Eq "(^|:)$port$"; then
    return 1
  fi
  return 0
}

rand_port() {
  local port
  for _ in {1..10}; do
    port=$(( (RANDOM % 10000) + 30000 ))
    if check_port_free "$port"; then
      echo "$port"
      return 0
    fi
  done
  fatal "未找到可用端口"
}

gen_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  else
    ensure_cmd "openssl"
    openssl rand -hex 16 | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\)$/\1-\2-\3-\4-\5/'
  fi
}

gen_short_id() {
  local len="${1:-8}"
  if [[ "$len" -lt 1 || "$len" -gt 16 ]]; then
    len=8
  fi
  ensure_cmd "openssl"
  openssl rand -hex 8 | cut -c1-"$len"
}

gen_x25519_keypair() {
  local bin="${XRAY_BIN:-xray}"
  if [[ -x "$bin" ]]; then
    "$bin" x25519
    return
  fi
  if command -v xray >/dev/null 2>&1; then
    xray x25519
  else
    fatal "未检测到 xray，可先运行 install"
  fi
}
