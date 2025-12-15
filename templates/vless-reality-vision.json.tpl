{
  "inbounds": [
    {
      "listen": "::",
      "port": ${PORT:-443},
      "protocol": "vless",
      "tag": "${TAG:-vless-reality-vision}",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none",
        "fallbacks": []
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DEST:-www.cloudflare.com:443}",
          "xver": 0,
          "serverNames": [
            "${SERVER_NAME:-www.cloudflare.com}"
          ],
          "privateKey": "${REALITY_PRIVATE_KEY}",
          "shortIds": [
            "${REALITY_SHORT_ID:-0123456789abcdef}"
          ],
          "spiderX": "/"
        }
      }
    }
  ]
}
