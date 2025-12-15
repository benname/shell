#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

resolve_base() {
  local src="${BASH_SOURCE[0]}"
  while [ -h "$src" ]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ $src != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" && pwd
}

BASE_DIR="$(resolve_base)"
LIB_DIR="$BASE_DIR/lib"
TEMPLATE_DIR="${TEMPLATE_DIR:-$BASE_DIR/templates}"
USER_CONFIG="$BASE_DIR/config/user.conf"

# 默认配置，可被环境变量或 config/user.conf 覆盖
SCRIPT_VERSION="0.1.0-dev"
# 核心二进制默认放 xray-core，避免与管理命令 xray 冲突
XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray-core}"
XRAY_CONF_DIR="${XRAY_CONF_DIR:-/usr/local/etc/xray}"
XRAY_SERVICE_NAME="${XRAY_SERVICE_NAME:-xray}"
XRAY_RUN_ARGS="${XRAY_RUN_ARGS:--confdir ${XRAY_CONF_DIR}}"
MANAGEMENT_BIN="${MANAGEMENT_BIN:-/usr/local/bin/xray}"

# shellcheck source=lib/log.sh
. "$LIB_DIR/log.sh"
# shellcheck source=lib/system.sh
. "$LIB_DIR/system.sh"
# shellcheck source=lib/template.sh
. "$LIB_DIR/template.sh"

load_user_config() {
  if [[ -f "$USER_CONFIG" ]]; then
    # shellcheck disable=SC1090
    . "$USER_CONFIG"
  fi
}

print_banner() {
  cat <<'EOF'
== Xray 配置管理脚本 ==
轻量、一键、可扩展
EOF
}

usage() {
  print_banner
  cat <<EOF
用法: $0 <命令> [参数]

命令:
  install [--version=vX.X.X] [--start]  安装/更新 xray-core 与服务
  doctor                                环境检测
  add [--type=reality-vision|enc-vision|reality-xhttp] [...]  添加配置，输出分享链接
  list                                  查看配置（解析 confdir）
  remove --tag=<tag>|--file=<path>      删除配置
  render <tpl> <out>                    渲染模板文件
  deploy [opts]                         一键安装+创建节点，可选 BBR/规则
  link [--name=xray]                    安装管理命令软链到 /usr/local/bin
  uninstall [--purge]                   卸载二进制/服务，可选清理配置
  help                                  显示帮助

add 参数示例:
  --type=reality-vision (默认)
  --type=enc-vision                           VLESS Encryption + Reality + Vision（自动生成 enc 串）
  --type=reality-xhttp [--path=/]             XHTTP 回落路径
  通用: --port=443 --uuid=<uuid> --tag=my-reality --host=example.com --file=/path/to/conf.json
  reality: --sni=icloud.com --dest=icloud.com:443 --short-id=01234567 --private-key=... --public-key=...

deploy 额外示例:
  --bbr                                      启用 BBR
  --block-bt                                 路由屏蔽 BT
  --block-cn                                 路由屏蔽回国 IP (geoip:cn)
  --start                                    部署后启动服务

环境变量/自定义口子:
  XRAY_BIN=/usr/local/bin/xray           Xray 可执行文件路径
  XRAY_CONF_DIR=/usr/local/etc/xray      配置目录（confdir 模式）
  XRAY_SERVICE_NAME=xray                 systemd 服务名
  XRAY_RUN_ARGS="-confdir /usr/local/etc/xray" 运行参数（高级自定义）
  TEMPLATE_DIR=./templates               模板目录
  在 config/user.conf 中也可覆盖上述变量或自定义默认参数
EOF
}

fetch_latest_version() {
  local version
  if command -v jq >/dev/null 2>&1; then
    version="$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.tag_name' | sed 's/^v//')"
  else
    version="$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest | sed -n 's/ *\"tag_name\": \"v\\(.*\\)\".*/\\1/p' | head -n1)"
  fi
  if [[ -z "${version:-}" ]]; then
    fatal "获取最新版本失败，请检查网络"
  fi
  echo "$version"
}

ensure_dirs() {
  mkdir -p "$XRAY_CONF_DIR"
  mkdir -p /usr/local/share/xray
}

xray_filename_for_arch() {
  local arch="$1"
  case "$arch" in
    amd64) echo "Xray-linux-64.zip" ;;
    arm64) echo "Xray-linux-arm64-v8a.zip" ;;
    armv7) echo "Xray-linux-arm32-v7a.zip" ;;
    s390x) echo "Xray-linux-s390x.zip" ;;
    *) fatal "未支持的架构: $arch" ;;
  esac
}

download_install_xray() {
  local version="$1"
  local arch="$2"
  local filename url tmpdir

  filename="$(xray_filename_for_arch "$arch")"
  url="https://github.com/XTLS/Xray-core/releases/download/v${version}/${filename}"
  tmpdir="$(mktemp -d)"

  log_info "下载 Xray: $url"
  curl -fL "$url" -o "$tmpdir/xray.zip"

  log_info "解压..."
  unzip -q "$tmpdir/xray.zip" -d "$tmpdir"

  install -m 755 "$tmpdir/xray" "$XRAY_BIN"
  install -d "$XRAY_CONF_DIR"
  install -m 644 "$tmpdir"/geo*.dat /usr/local/share/xray/ 2>/dev/null || true

  rm -rf "$tmpdir"
  log_info "Xray 安装完成: $XRAY_BIN"
}

install_systemd_service() {
  local service_path="/etc/systemd/system/${XRAY_SERVICE_NAME}.service"
  cat >"$service_path" <<EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=root
Type=simple
ExecStart=${XRAY_BIN} run ${XRAY_RUN_ARGS}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  log_info "写入 systemd 服务: $service_path"
  systemctl daemon-reload
}

ensure_minimal_config() {
  local base_cfg="${XRAY_CONF_DIR}/00-base.json"
  if [[ -f "$base_cfg" ]]; then
    return
  fi
  cat >"$base_cfg" <<'EOF'
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {
        "response": {
          "type": "http"
        }
      },
      "tag": "block"
    }
  ]
}
EOF
  log_info "创建初始配置: $base_cfg"
}

apply_rules() {
  local block_bt="$1"
  local block_cn="$2"
  local rules_file="${XRAY_CONF_DIR}/05-rules.json"

  if [[ "$block_bt" -eq 0 && "$block_cn" -eq 0 ]]; then
    # 不需要规则，若存在则保留用户自定义，不强删
    return
  fi

  local rules=()
  if [[ "$block_bt" -eq 1 ]]; then
    rules+=('{"type":"field","protocol":["bittorrent"],"outboundTag":"block"}')
  fi
  if [[ "$block_cn" -eq 1 ]]; then
    rules+=('{"type":"field","geoip":["cn"],"outboundTag":"block"}')
  fi

  cat >"$rules_file" <<EOF
{
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      $(printf "%s" "$(IFS=','; echo "${rules[*]}")")
    ]
  }
}
EOF
  log_info "写入规则: $rules_file"
}

cmd_install() {
  ensure_root
  load_user_config
  local version=""
  local auto_start=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version=*)
        version="${1#*=}"
        ;;
      --start)
        auto_start=1
        ;;
      *)
        fatal "未知参数: $1"
        ;;
    esac
    shift
  done

  local os like arch init pkg
  os="$(detect_os)"
  like="$(detect_like)"
  arch="$(detect_arch)"
  init="$(detect_init)"
  pkg="$(detect_pkg_manager)"

  log_info "系统: $os ($like), 架构: $arch, init: $init, 包管理: $pkg"

  ensure_cmd "curl"
  ensure_cmd "unzip"
  ensure_cmd "tar"
  ensure_cmd "jq"

  ensure_dirs
  ensure_minimal_config

  if [[ -z "$version" ]]; then
    version="$(fetch_latest_version)"
  fi

  download_install_xray "$version" "$arch"

  if [[ "$init" != "systemd" ]]; then
    log_warn "当前未检测到 systemd，服务安装跳过，请手动运行: ${XRAY_BIN} run ${XRAY_RUN_ARGS}"
    return 0
  fi

  install_systemd_service
  if [[ $auto_start -eq 1 ]]; then
    log_info "启动并开机自启 ${XRAY_SERVICE_NAME}"
    systemctl enable --now "${XRAY_SERVICE_NAME}"
  else
    log_info "已安装服务，未自动启动。可运行: systemctl enable --now ${XRAY_SERVICE_NAME}"
  fi

  # 默认安装管理命令到 /usr/local/bin/xray
  ln -sf "$BASE_DIR/xray.sh" "$MANAGEMENT_BIN"
  chmod +x "$MANAGEMENT_BIN"
  log_info "管理命令已就位: ${MANAGEMENT_BIN} （可直接运行 xray 管理）"
}

cmd_doctor() {
  load_user_config
  cat <<EOF
脚本版本: ${SCRIPT_VERSION}
Xray 路径: ${XRAY_BIN}
配置目录: ${XRAY_CONF_DIR}
模板目录: ${TEMPLATE_DIR}
服务名: ${XRAY_SERVICE_NAME}
EOF
  log_info "系统: $(detect_os) ($(detect_like))"
  log_info "架构: $(detect_arch)"
  log_info "init: $(detect_init)"
  log_info "包管理: $(detect_pkg_manager)"

  for c in curl unzip tar jq; do
    if command -v "$c" >/dev/null 2>&1; then
      log_info "依赖已安装: $c"
    else
      log_warn "缺少依赖: $c"
    fi
  done

  if command -v xray >/dev/null 2>&1; then
    log_info "Xray 已安装: $(xray -version 2>/dev/null | head -n 1)"
  else
    log_warn "未检测到 Xray 二进制"
  fi
}

cmd_render() {
  load_user_config
  if [[ $# -ne 2 ]]; then
    fatal "用法: $0 render <模板路径> <输出文件>"
  fi
  local tpl="$1"
  local out="$2"
  if [[ ! -f "$tpl" ]]; then
    tpl="${TEMPLATE_DIR}/$1"
  fi
  render_template "$tpl" "$out"
  log_info "渲染完成: $out"
}

sanitize_tag() {
  echo "$1" | tr -cd 'A-Za-z0-9._-'
}

sanitize_port() {
  local p="$1"
  p="${p//[!0-9]/}"
  echo "$p"
}

find_conf_by_tag() {
  local tag="$1"
  local file
  for file in "$XRAY_CONF_DIR"/*.json; do
    [[ -e "$file" ]] || continue
    if jq -e --arg t "$tag" '.inbounds[]?|select(.tag==$t)' "$file" >/dev/null 2>&1; then
      echo "$file"
      return 0
    fi
  done
  return 1
}

build_vless_reality_vision_link() {
  local uuid="$1" host="$2" port="$3" sni="$4" pbk="$5" sid="$6" tag="$7"
  printf "vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp&headerType=none#%s\n" \
    "$uuid" "$host" "$port" "$sni" "$pbk" "$sid" "$tag"
}

build_vless_enc_link() {
  local uuid="$1" host="$2" port="$3" sni="$4" pbk="$5" sid="$6" enc="$7" tag="$8"
  printf "vless://%s@%s:%s?encryption=%s&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp&headerType=none#%s\n" \
    "$uuid" "$host" "$port" "$enc" "$sni" "$pbk" "$sid" "$tag"
}

parse_x25519_output() {
  local out="$1"
  local priv pub
  priv="$(echo "$out" | sed -n 's/^[Pp]rivate[[:space:]]*[Kk]ey[:[:space:]]*//p' | head -n1)"
  pub="$(echo "$out" | sed -n 's/^[Pp]ublic[[:space:]]*[Kk]ey[:[:space:]]*//p' | head -n1)"
  if [[ -z "$priv" || -z "$pub" ]]; then
    # 尝试抓取前两个看起来像 base64url 的字段
    priv="$(echo "$out" | grep -Eo '[A-Za-z0-9_-]{43,}' | head -n1 || true)"
    pub="$(echo "$out" | grep -Eo '[A-Za-z0-9_-]{43,}' | head -n2 | tail -n1 || true)"
  fi
  if [[ -z "$priv" || -z "$pub" ]]; then
    log_error "无法解析 x25519 输出:\n$out"
    fatal "生成 Reality 公私钥失败，请检查 xray-core"
  fi
  echo "${priv}|${pub}"
}

gen_enc_pair() {
  local bin="${XRAY_BIN:-}"
  local runner=""
  local candidates=(
    "$bin"
    "/usr/local/bin/xray-core"
    "/usr/local/bin/xray"
    "$(command -v xray-core 2>/dev/null || true)"
    "$(command -v xray 2>/dev/null || true)"
  )
  for cand in "${candidates[@]}"; do
    [[ -n "$cand" ]] || continue
    [[ -x "$cand" ]] || continue
    if "$cand" -version >/dev/null 2>/dev/null; then
      runner="$cand"
      break
    fi
  done
  if [[ -z "$runner" ]]; then
    fatal "未找到 xray-core，可先运行 install"
  fi
  local out
  if ! out="$("$runner" vlessenc 2>/dev/null)"; then
    fatal "运行 $runner vlessenc 失败，请确认核心版本支持 VLESS Encryption"
  fi
  local dec enc
  dec="$(echo "$out" | awk -F'\"' '/\"decryption\"/ {d[++i]=$4} END {print d[i]}')"
  enc="$(echo "$out" | awk -F'\"' '/\"encryption\"/ {e[++j]=$4} END {print e[j]}')"
  if [[ -z "$dec" || -z "$enc" ]]; then
    log_error "vlessenc 输出:\n$out"
    fatal "解析 vlessenc 输出失败，请升级 xray-core"
  fi
  echo "${dec}|${enc}"
}

cmd_add() {
  ensure_root
  load_user_config

  local type="reality-vision"
  local port=""
  local uuid=""
  local sni=""
  local dest=""
  local tag=""
  local short_id=""
  local priv_key=""
  local pub_key=""
  local outfile=""
  local host=""
  local http_path=""
  local enc_decryption=""
  local enc_encryption=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type=*) type="${1#*=}" ;;
      --port=*) port="${1#*=}" ;;
      --uuid=*) uuid="${1#*=}" ;;
      --sni=*) sni="${1#*=}" ;;
      --dest=*) dest="${1#*=}" ;;
      --tag=*) tag="${1#*=}" ;;
      --short-id=*) short_id="${1#*=}" ;;
      --private-key=*) priv_key="${1#*=}" ;;
      --public-key=*) pub_key="${1#*=}" ;;
      --file=*) outfile="${1#*=}" ;;
      --host=*) host="${1#*=}" ;;
      --path=*) http_path="${1#*=}" ;;
      --enc-decryption=*) enc_decryption="${1#*=}" ;;
      --enc-encryption=*) enc_encryption="${1#*=}" ;;
      *)
        fatal "未知参数: $1"
        ;;
    esac
    shift
  done

  case "$type" in
    reality-vision) ;;
    enc-vision) ;;
    reality-xhttp) ;;
    *)
      fatal "不支持的类型: $type"
      ;;
  esac

  ensure_dirs
  ensure_minimal_config

  port="$(sanitize_port "${port:-}")"
  [[ -n "$uuid" ]] || uuid="$(gen_uuid)"
  [[ -n "$port" ]] || port="$(rand_port)"
  [[ -n "$tag" ]] || tag="${type}-${port}"
  tag="$(sanitize_tag "$tag")"

  if ! check_port_free "$port"; then
    fatal "端口 $port 已被占用"
  fi

  local tpl=""
  case "$type" in
    reality-vision)
      [[ -n "$sni" ]] || sni="icloud.com"
      [[ -n "$dest" ]] || dest="icloud.com:443"
      [[ -n "$short_id" ]] || short_id="$(gen_short_id 8)"
      [[ -n "$host" ]] || host="$sni"
      if [[ -z "$priv_key" || -z "$pub_key" ]]; then
        local kp
        kp="$(gen_x25519_keypair)"
        local parsed
        parsed="$(parse_x25519_output "$kp")"
        priv_key="${parsed%%|*}"
        pub_key="${parsed##*|}"
      fi
      tpl="${TEMPLATE_DIR}/vless-reality-vision.json.tpl"
      export PORT="$port" UUID="$uuid" SERVER_NAME="$sni" DEST="$dest" REALITY_PRIVATE_KEY="$priv_key" REALITY_SHORT_ID="$short_id" TAG="$tag"
      ;;
    enc-vision)
      [[ -n "$sni" ]] || sni="icloud.com"
      [[ -n "$dest" ]] || dest="icloud.com:443"
      [[ -n "$short_id" ]] || short_id="$(gen_short_id 8)"
      [[ -n "$host" ]] || host="$sni"
      if [[ -z "$priv_key" || -z "$pub_key" ]]; then
        local kp
        kp="$(gen_x25519_keypair)"
        local parsed
        parsed="$(parse_x25519_output "$kp")"
        priv_key="${parsed%%|*}"
        pub_key="${parsed##*|}"
      fi
      if [[ -z "$enc_decryption" || -z "$enc_encryption" ]]; then
        local enc_pair
        enc_pair="$(gen_enc_pair)"
        enc_decryption="${enc_pair%%|*}"
        enc_encryption="${enc_pair##*|}"
      fi
      tpl="${TEMPLATE_DIR}/vless-enc-vision.json.tpl"
      export PORT="$port" UUID="$uuid" SERVER_NAME="$sni" DEST="$dest" REALITY_PRIVATE_KEY="$priv_key" REALITY_SHORT_ID="$short_id" TAG="$tag" ENC_DECRYPTION="$enc_decryption" ENC_ENCRYPTION="$enc_encryption"
      ;;
    reality-xhttp)
      [[ -n "$sni" ]] || sni="icloud.com"
      [[ -n "$dest" ]] || dest="icloud.com:443"
      [[ -n "$short_id" ]] || short_id="$(gen_short_id 8)"
      [[ -n "$host" ]] || host="$sni"
      [[ -n "$http_path" ]] || http_path="/"
      if [[ -z "$priv_key" || -z "$pub_key" ]]; then
        local kp
        kp="$(gen_x25519_keypair)"
        priv_key="$(echo "$kp" | awk '/Private key/ {print $3}')"
        pub_key="$(echo "$kp" | awk '/Public key/ {print $3}')"
      fi
      tpl="${TEMPLATE_DIR}/vless-reality-xhttp.json.tpl"
      export PORT="$port" UUID="$uuid" SERVER_NAME="$sni" DEST="$dest" REALITY_PRIVATE_KEY="$priv_key" REALITY_SHORT_ID="$short_id" HTTP_PATH="$http_path" TAG="$tag"
      ;;
  esac

  if [[ -z "$outfile" ]]; then
    outfile="${XRAY_CONF_DIR}/20-${tag}.json"
  fi

  log_info "生成配置: 类型=$type, 端口=$port, tag=$tag"
  render_template "$tpl" "$outfile"
  if [[ ! -f "$outfile" ]]; then
    fatal "写入配置失败: $outfile"
  fi

  log_info "写入配置文件: $outfile"
  log_info "分享链接:"
  case "$type" in
    reality-vision)
      build_vless_reality_vision_link "$uuid" "$host" "$port" "$sni" "$pub_key" "$short_id" "$tag"
      ;;
    enc-vision)
      build_vless_enc_link "$uuid" "$host" "$port" "$sni" "$pub_key" "$short_id" "$enc_encryption" "$tag"
      ;;
    reality-xhttp)
      printf "vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp&headerType=http&path=%s#%s\n" \
        "$uuid" "$host" "$port" "$sni" "$pub_key" "$short_id" "$http_path" "$tag"
      ;;
  esac
}

cmd_list() {
  load_user_config
  ensure_cmd "jq"
  shopt -s nullglob
  local any=0
  printf "目录: %s\n" "$XRAY_CONF_DIR"
  printf "%-30s %-8s %-36s %-25s\n" "FILE" "PORT" "UUID" "TAG"
  local file
  for file in "$XRAY_CONF_DIR"/*.json; do
    [[ -e "$file" ]] || continue
    local port uuid tag
    port="$(jq -r '.inbounds[0].port // empty' "$file" 2>/dev/null || true)"
    uuid="$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$file" 2>/dev/null || true)"
    tag="$(jq -r '.inbounds[0].tag // empty' "$file" 2>/dev/null || true)"
    if [[ -n "$port" && -n "$uuid" && -n "$tag" ]]; then
      printf "%-30s %-8s %-36s %-25s\n" "$(basename "$file")" "$port" "$uuid" "$tag"
      any=1
    fi
  done
  if [[ $any -eq 0 ]]; then
    log_warn "未找到可显示的配置（检查 ${XRAY_CONF_DIR}/*.json）"
  fi
}

cmd_remove() {
  ensure_root
  load_user_config
  ensure_cmd "jq"
  local tag="" file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tag=*) tag="${1#*=}" ;;
      --file=*) file="${1#*=}" ;;
      *)
        fatal "未知参数: $1"
        ;;
    esac
    shift
  done

  if [[ -z "$tag" && -z "$file" ]]; then
    fatal "用法: $0 remove --tag=<tag> 或 --file=<path>"
  fi

  if [[ -n "$tag" ]]; then
    file="$(find_conf_by_tag "$tag" || true)"
    [[ -n "$file" ]] || fatal "未找到 tag=$tag 的配置"
  fi

  if [[ ! -f "$file" ]]; then
    fatal "文件不存在: $file"
  fi

  rm -f "$file"
  log_info "已删除配置: $file"
}

enable_bbr() {
  log_info "尝试启用 BBR"
  sysctl -w net.core.default_qdisc=fq >/dev/null
  sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null
  cat >/etc/sysctl.d/99-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl -p /etc/sysctl.d/99-bbr.conf >/dev/null
  log_info "BBR 已尝试启用"
}

cmd_deploy() {
  ensure_root
  load_user_config

  local do_bbr=0 block_bt=0 block_cn=0
  local install_args=()
  local add_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bbr) do_bbr=1 ;;
      --block-bt) block_bt=1 ;;
      --block-cn) block_cn=1 ;;
      --version=*|--start)
        install_args+=("$1")
        ;;
      *)
        add_args+=("$1")
        ;;
    esac
    shift
  done

  cmd_install "${install_args[@]}"

  if [[ "$do_bbr" -eq 1 ]]; then
    enable_bbr
  fi

  apply_rules "$block_bt" "$block_cn"

  cmd_add "${add_args[@]}"

  log_info "部署完成"
}

cmd_link() {
  ensure_root
  local name="xray-manage"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name=*) name="${1#*=}" ;;
      *)
        fatal "未知参数: $1"
        ;;
    esac
    shift
  done
  local target="/usr/local/bin/${name}"
  ln -sf "$BASE_DIR/xray.sh" "$target"
  chmod +x "$target"
  log_info "已创建管理命令: $target"
  if [[ "$name" != "xray" ]]; then
    log_info "可在 shell 中设置 alias xray=${target} 便于直接使用"
  fi
}

cmd_uninstall() {
  ensure_root
  load_user_config
  local purge=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --purge) purge=1 ;;
      *)
        fatal "未知参数: $1"
        ;;
    esac
    shift
  done

  local service_path="/etc/systemd/system/${XRAY_SERVICE_NAME}.service"
  if [[ -f "$service_path" ]]; then
    systemctl disable --now "${XRAY_SERVICE_NAME}" 2>/dev/null || true
    rm -f "$service_path"
    systemctl daemon-reload || true
    log_info "已删除 systemd 服务: $service_path"
  fi

  if [[ -x "$XRAY_BIN" ]]; then
    rm -f "$XRAY_BIN"
    log_info "已删除 Xray 二进制: $XRAY_BIN"
  fi

  if [[ -d /usr/local/share/xray ]]; then
    rm -rf /usr/local/share/xray
    log_info "已删除 geo 数据目录 /usr/local/share/xray"
  fi

  for m in "$MANAGEMENT_BIN" /usr/local/bin/xray-manage; do
    if [[ -f "$m" && "$(readlink "$m")" == "$BASE_DIR/xray.sh" ]]; then
      rm -f "$m"
      log_info "已删除管理命令软链 $m"
    fi
  done

  if [[ "$purge" -eq 1 ]]; then
    rm -rf "$XRAY_CONF_DIR"
    log_info "已清理配置目录: $XRAY_CONF_DIR"
  else
    log_info "保留配置目录: $XRAY_CONF_DIR"
  fi
}

prompt_default() {
  local prompt="$1" default="$2" var
  read -r -p "$prompt [${default}]: " var
  if [[ -z "$var" ]]; then
    echo "$default"
  else
    echo "$var"
  fi
}

interactive_menu() {
  print_banner
  cat <<'EOF'
请选择操作:
 1) 安装/更新并启动
 2) 新增 VLESS + Reality + Vision
 3) 新增 VLESS + ENC + Vision（Reality，无需证书）
 4) 新增 VLESS + Reality + XHTTP
 5) 一键部署 VLESS + Reality + Vision (BBR+禁BT+禁回国)
 6) 查看配置 (list)
 7) 删除配置 (remove)
 8) 卸载 (uninstall)
 0) 退出
EOF
  read -r -p "输入编号: " choice
  case "$choice" in
    1)
      cmd_install --start
      ;;
    2)
      local port sni dest tag
      port="$(prompt_default "端口 (留空自动)" "")"
      sni="$(prompt_default "SNI" "icloud.com")"
      dest="$(prompt_default "回源目标" "${sni}:443")"
      tag="$(prompt_default "标识 tag" "reality-vision-${port:-auto}")"
      cmd_add --type=reality-vision ${port:+--port="$port"} --sni="$sni" --dest="$dest" --tag="$tag"
      ;;
    3)
      local port sni dest tag
      port="$(prompt_default "端口 (留空自动)" "")"
      sni="$(prompt_default "SNI" "icloud.com")"
      dest="$(prompt_default "回源目标" "${sni}:443")"
      tag="$(prompt_default "标识 tag" "enc-vision-${port:-auto}")"
      cmd_add --type=enc-vision ${port:+--port="$port"} --sni="$sni" --dest="$dest" --tag="$tag"
      ;;
    4)
      local port sni dest path tag
      port="$(prompt_default "端口 (留空自动)" "")"
      sni="$(prompt_default "SNI" "icloud.com")"
      dest="$(prompt_default "回源目标" "${sni}:443")"
      path="$(prompt_default "XHTTP path" "/")"
      tag="$(prompt_default "标识 tag" "reality-xhttp-${port:-auto}")"
      cmd_add --type=reality-xhttp ${port:+--port="$port"} --sni="$sni" --dest="$dest" --path="$path" --tag="$tag"
      ;;
    5)
      cmd_deploy --start --bbr --block-bt --block-cn --type=reality-vision
      ;;
    6)
      cmd_list
      ;;
    7)
      local tag
      tag="$(prompt_default "要删除的 tag" "")"
      if [[ -z "$tag" ]]; then
        log_warn "未输入 tag，已取消"
      else
        cmd_remove --tag="$tag"
      fi
      ;;
    8)
      local purge
      purge="$(prompt_default "是否 purge 配置目录? (y/N)" "N")"
      if [[ "$purge" =~ ^[Yy]$ ]]; then
        cmd_uninstall --purge
      else
        cmd_uninstall
      fi
      ;;
    0)
      exit 0
      ;;
    *)
      echo "无效选项"
      ;;
  esac
}

main() {
  if [[ $# -lt 1 ]]; then
    interactive_menu
    exit 0
  fi

  case "$1" in
    install) shift; cmd_install "$@" ;;
    doctor) shift; cmd_doctor "$@" ;;
    add) shift; cmd_add "$@" ;;
    list) shift; cmd_list "$@" ;;
    remove) shift; cmd_remove "$@" ;;
    deploy) shift; cmd_deploy "$@" ;;
    link) shift; cmd_link "$@" ;;
    uninstall) shift; cmd_uninstall "$@" ;;
    render) shift; cmd_render "$@" ;;
    help|-h|--help) usage ;;
    version|-v|--version) echo "$SCRIPT_VERSION" ;;
    *)
      fatal "未知命令: $1"
      ;;
  esac
}

main "$@"
