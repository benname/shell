# Xray 一键配置脚本（轻量版）

> 目标：一键安装/管理 Xray，快速生成 VLESS 组合（支持 Reality+Vision / enc+Vision / Reality+XHTTP，后续再扩）。安装完直接用 `xray` 管理（管理脚本），核心二进制为 `xray-core`。

## 快速开始

公开仓库一键安装（示例: main 分支 tarball，安装核心+服务+管理命令 xray）：
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/benname/shell/main/install.sh)
```

手动/离线方式：
```bash
git clone <your repo> xray && cd xray
chmod +x xray.sh lib/*.sh scripts/selftest.sh install.sh
sudo ./xray.sh install --start      # 安装核心(xray-core)+systemd+管理命令 xray
xray doctor                         # 查看环境与默认目录

# 生成节点并输出分享链接
sudo ./xray.sh add --type=reality-vision --port=443 --sni=www.cloudflare.com
sudo ./xray.sh add --type=enc-vision --port=8443 --cert=/path/cert.pem --key=/path/key.pem
sudo ./xray.sh add --type=reality-xhttp --path=/ --sni=www.cloudflare.com

# 查看/删除
./xray.sh list
sudo ./xray.sh remove --tag=reality-vision-443
```

## 命令

- `install [--version=vX.X.X] [--start]`：下载 Xray（自动选架构）、创建 `confdir`、写入 systemd 服务，并自动把管理命令软链到 `/usr/local/bin/xray`（核心二进制为 `xray-core`）。`--start` 自动启用并启动。
- `doctor`：打印脚本版本、路径、系统信息和依赖状态。
- `add [--type=reality-vision|enc-vision|reality-xhttp] [...]`：生成配置文件并打印 VLESS 分享链接。
  - 通用参数：`--port`、`--uuid`、`--tag`、`--host`（链接显示用）、`--file`（输出路径）。
  - Reality: `--sni`、`--dest`、`--short-id`、`--private-key/--public-key`（缺省自动生成）。
  - enc+Vision: `--cert`、`--key`、`--alpn="\"h2\",\"http/1.1\""`。
  - Reality+XHTTP: `--path`（默认 `/`）。
- `deploy [opts]`：一键安装+创建节点，可选 `--bbr`（启用 BBR）、`--block-bt`、`--block-cn`、`--start`、`--version=...` 以及所有 `add` 通用参数。
- `list`：扫描 `XRAY_CONF_DIR/*.json`，显示端口/UUID/tag。
- `remove --tag=<tag> | --file=<path>`：删除对应配置文件。
- `render <tpl> <out>`：将模板渲染为配置（可自定义环境变量）。
- `link [--name=xray]`：在 `/usr/local/bin` 创建管理命令软链，默认名 `xray`（管理脚本），不会影响核心二进制 `xray-core`。
- `uninstall [--purge]`：卸载二进制/服务，`--purge` 额外清理配置目录和 geo 数据。
- `help`：帮助。

## 自测

```bash
./scripts/selftest.sh
```
会执行语法检查、运行 doctor，并渲染模板到 /tmp。

## 将管理命令放到 PATH

```bash
sudo ./xray.sh link --name=xray   # 默认已在 install 时创建
```

## 自定义口子

可通过环境变量或 `config/user.conf` 覆盖默认值：

- `XRAY_BIN=/usr/local/bin/xray-core`
- `XRAY_CONF_DIR=/usr/local/etc/xray`
- `XRAY_SERVICE_NAME=xray`
- `XRAY_RUN_ARGS="-confdir /usr/local/etc/xray"`
- `TEMPLATE_DIR=./templates`

示例 `config/user.conf`：

```bash
XRAY_CONF_DIR=/etc/xray
XRAY_RUN_ARGS="-confdir /etc/xray"
```

## 模板

- `templates/vless-reality-vision.json.tpl`：VLESS + Reality + Vision 入站，占位符 `PORT`、`UUID`、`SERVER_NAME`、`DEST`、`REALITY_PRIVATE_KEY`、`REALITY_SHORT_ID`、`TAG`
- `templates/vless-enc-vision.json.tpl`：VLESS + TLS(enc) + Vision，占位符 `PORT`、`UUID`、`SERVER_NAME`、`ALPN`、`TLS_CERT_FILE`、`TLS_KEY_FILE`、`TAG`
- `templates/vless-reality-xhttp.json.tpl`：VLESS + Reality + XHTTP，占位符 `PORT`、`UUID`、`SERVER_NAME`、`DEST`、`REALITY_PRIVATE_KEY`、`REALITY_SHORT_ID`、`HTTP_PATH`、`TAG`

## 工作流建议

1. 先 `install` 安装核心与服务。
2. 使用 `add` 生成节点，链接输出后即可在客户端导入。
3. 通过 `list`/`remove` 管理 confdir 内的配置。

## 已完成功能

- 一键安装/更新 Xray 核心（xray-core）、systemd 服务，管理命令软链为 `xray`
- 协议生成：VLESS Reality+Vision、enc+Vision、Reality+XHTTP（分享链接输出）
- 一键部署：install + add，支持 BBR、禁 BT、禁回国 IP
- 规则管理：生成 `05-rules.json`（BT/geoip:cn），保留 direct/blackhole 出站
- 卸载：删除服务/二进制/geo 数据，可选 purge 配置
- 自测脚本：语法检查、doctor、模板渲染
