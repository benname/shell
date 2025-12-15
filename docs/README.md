# Xray 一键配置脚本（开发中）

## 快速开始

```bash
chmod +x xray.sh
sudo ./xray.sh install --start    # 安装/更新 Xray 二进制与服务
sudo ./xray.sh doctor             # 检查环境

# 生成节点
sudo ./xray.sh add --type=reality-vision --port=443 --sni=www.cloudflare.com
sudo ./xray.sh add --type=enc-vision --cert=/path/cert.pem --key=/path/key.pem
sudo ./xray.sh add --type=reality-xhttp --path=/ --sni=www.cloudflare.com
```

自定义默认值：在 `config/user.conf` 中写入变量即可覆盖，如：

```bash
XRAY_CONF_DIR=/etc/xray
XRAY_RUN_ARGS="-confdir /etc/xray"
```

## 自测

```bash
./scripts/selftest.sh
```
执行 bash 语法检查、doctor，以及模板渲染。

## 目录规划

- `xray.sh`：主入口，命令行解析、安装、渲染、add/list/remove
- `deploy`：一键安装+生成节点，可选 BBR/规则
- `lib/`：日志、系统检测、模板渲染等函数
- `templates/`：协议模板（Reality+Vision、enc+Vision、Reality+XHTTP）
- `docs/`：文档
- `config/user.conf`：可选的本地默认配置覆盖
- `link`：软链管理命令到 /usr/local/bin（推荐名 xray-manage）

## PATH 中使用管理命令

```bash
sudo ./xray.sh link --name=xray   # 默认 install 已创建
```

## 下一步

- 一键部署命令：安装+默认节点+BBR/规则开关。
- 规则配置（禁 BT/回国 IP/WARP）开关。
- 参数校验、回滚与更丰富分享链接输出。
