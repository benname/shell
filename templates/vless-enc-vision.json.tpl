{
  "inbounds": [
    {
      "listen": "::",
      "port": ${PORT:-443},
      "protocol": "vless",
      "tag": "${TAG:-vless-enc-vision}",
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
        "security": "tls",
        "tlsSettings": {
          "serverName": "${SERVER_NAME:-www.example.com}",
          "alpn": [${ALPN:-"h2","http/1.1"}],
          "certificates": [
            {
              "certificateFile": "${TLS_CERT_FILE}",
              "keyFile": "${TLS_KEY_FILE}"
            }
          ]
        }
      }
    }
  ]
}
