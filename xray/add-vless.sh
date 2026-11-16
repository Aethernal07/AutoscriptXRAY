#!/bin/bash

clear
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\E[44;1;39m        Add VLESS Account        \E[0m"
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"

# ambil domain
domain=$(cat /etc/xray/domain)

# public port nginx
tls="443"
none="80"
grpc="443"

# input user
read -rp "Username : " user
read -rp "Expired (days): " masaaktif

uuid=$(cat /proc/sys/kernel/random/uuid)
exp=$(date -d "$masaaktif days" +"%Y-%m-%d")

# cek duplicate user
CLIENT_EXISTS=$(jq -r '.inbounds[].settings.clients[]?.email' /etc/xray/config.json | grep -w "$user" | wc -l)

if [[ ${CLIENT_EXISTS} == '1' ]]; then
    echo ""
    echo "User already exists!"
    exit 1
fi

# backup config
cp /etc/xray/config.json /etc/xray/config.json.bak

# temp file
tmpfile=$(mktemp)

# inject user ke config
if ! jq --arg uuid "$uuid" --arg user "$user" '
(.inbounds[] | select(.tag=="vless-ws-tls").settings.clients) +=
[{"id":$uuid,"email":$user}] |

(.inbounds[] | select(.tag=="vless-ws-nontls").settings.clients) +=
[{"id":$uuid,"email":$user}] |

(.inbounds[] | select(.tag=="vless-grpc").settings.clients) +=
[{"id":$uuid,"email":$user}]
' /etc/xray/config.json > "$tmpfile"; then

    echo ""
    echo "ERROR: Failed inject config!"
    rm -f "$tmpfile"
    exit 1

fi

# cek file kosong
if [[ ! -s "$tmpfile" ]]; then
    echo ""
    echo "ERROR: Config generated empty!"
    rm -f "$tmpfile"
    exit 1
fi

# validasi json
if ! jq empty "$tmpfile" >/dev/null 2>&1; then
    echo ""
    echo "ERROR: Invalid JSON!"
    rm -f "$tmpfile"
    exit 1
fi

# replace config
mv "$tmpfile" /etc/xray/config.json

# test config xray
if ! xray -test -config /etc/xray/config.json >/dev/null 2>&1; then

    echo ""
    echo "ERROR: Xray config failed!"
    echo "Restoring backup config..."

    cp /etc/xray/config.json.bak /etc/xray/config.json

    exit 1

fi

# restart xray
systemctl restart xray

# cek status xray
if ! systemctl is-active --quiet xray; then

    echo ""
    echo "ERROR: Xray failed start!"
    echo "Restoring backup config..."

    cp /etc/xray/config.json.bak /etc/xray/config.json

    systemctl restart xray

    exit 1

fi

# simpan database user
echo "${user} ${exp} ${uuid}" >> /etc/xray/vless.db

# info ISP & kota VPS (untuk kartu akun, gagal lookup = "-")
geo=$(curl -s --max-time 5 http://ip-api.com/json/)
ISP=$(echo "$geo" | jq -r '.isp // "-"' 2>/dev/null)
CITY=$(echo "$geo" | jq -r '.city // "-"' 2>/dev/null)
ISP=${ISP:-"-"}
CITY=${CITY:-"-"}

# generate vless link (format kartu provider)
vlesslink1="vless://${uuid}@${domain}:${tls}?path=/vless&security=tls&encryption=none&host=${domain}&type=ws&sni=${domain}#${user}"

vlesslink2="vless://${uuid}@${domain}:${none}?path=/vless&security=none&encryption=none&host=${domain}&type=ws#${user}"

vlesslink3="vless://${uuid}@${domain}:${grpc}?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=${domain}#${user}"

clear

echo "━━━━━━━━━━━━━━━━━━"
echo "🌐 Host:"
echo "${domain}"
echo "🏢 ISP:"
echo "${ISP}"
echo "| City:"
echo "${CITY}"
echo "🌐 NS:"
echo "-"
echo "👤 Username:"
echo "${user}"
echo "🔑 UUID:"
echo "${uuid}"
echo "⏰ Expired: ${exp}"
echo "📶 Bandwidth: Unlimited"
echo "📱 Limit IP: 2 Device"
echo "━━━━━━━━━━━━━━━━━━"
echo "🔌 Port TLS:"
echo "${tls}"
echo "🔌 Port NTLS:"
echo "${none}"
echo "🔌 Port GRPC:"
echo "${grpc}"
echo "🔌 Port SlowDNS:"
echo "5300, 53"
echo "📍 Path:"
echo "/vless"
echo "━━━━━━━━━━━━━━━━━━"
echo "🚀 SLOWDNS"
echo "🌐 NS:"
echo "-"
echo "🔑 PubKey:"
echo "-"
echo "🌐 DNS:"
echo "1.1.1.1, 8.8.8.8"
echo "━━━━━━━━━━━━━━━━━━"
echo "🔗 VLESS TLS"
echo "${vlesslink1}"
echo "🔗 VLESS Non-TLS"
echo "${vlesslink2}"
echo "🔗 VLESS gRPC"
echo "${vlesslink3}"
echo "🔗 VLESS SlowDNS (NTLS 80)"
echo "${vlesslink2}"

echo ""
echo "Database User  : /etc/xray/vless.db"
echo ""

read -n 1 -s -r -p "Tekan apa saja untuk kembali ke menu..."

m-vless
