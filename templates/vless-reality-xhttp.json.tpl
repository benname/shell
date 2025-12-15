{
  "inbounds": [
    {
      "listen": "::",
      "port": ${PORT},
      "protocol": "vless",
      "tag": "${TAG}",
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
          "dest": "${DEST}",
          "xver": 0,
          "serverNames": [
            "${SERVER_NAME}"
          ],
          "privateKey": "${REALITY_PRIVATE_KEY}",
          "shortIds": [
            "${REALITY_SHORT_ID}"
          ],
          "spiderX": "/"
        },
        "tcpSettings": {
          "header": {
            "type": "http",
            "request": {
              "path": [ "${HTTP_PATH}" ]
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
