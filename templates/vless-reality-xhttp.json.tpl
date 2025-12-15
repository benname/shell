{
  "inbounds": [
    {
      "listen": "::",
      "port": ${PORT:-443},
      "protocol": "vless",
      "tag": "${TAG:-vless-reality-xhttp}",
      "settings": {
        "clients": [
          {
            "id": "${UUID}"
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
            "${REALITY_SHORT_ID:-01234567}"
          ],
          "spiderX": "/"
        },
        "tcpSettings": {
          "header": {
            "type": "http",
            "request": {
              "path": [ "${HTTP_PATH:-/}" ]
            },
            "response": {
              "version": "1.1",
              "status": "200",
              "reason": "OK",
              "headers": {
                "Content-Type": [ "application/octet-stream", "video/mpeg" ],
                "Transfer-Encoding": [ "chunked" ],
                "Connection": [ "keep-alive" ],
                "Pragma": "no-cache"
              }
            }
          }
        }
      }
    }
  ]
}
