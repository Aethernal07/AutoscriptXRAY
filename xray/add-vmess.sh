#!/bin/bash

clear
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\E[44;1;39m        Add VMess Account        \E[0m"
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"

# ambil domain
domain=$(cat /etc/xray/domain)

# public nginx port
tls="443"
none="80"
grpc="443"

# input user
read -rp "Username : " user
read -rp "Expired (days): " masaaktif
read -rp "Bug Host / Wildcard (kosongkan = tanpa wildcard, contoh: support.zoom.us): " bug

# normalisasi bug host: buang spasi, skema http(s)://, dan garis miring akhir
bug=$(echo "$bug" | tr -d '[:space:]' | sed -e 's#^https\?://##' -e 's#/$##')

# alamat + host/SNI default = domain biasa
add_host="${domain}"
host_name="${domain}"
sni_name="${domain}"
wildcard=""

if [[ -n "$bug" ]]; then
    # validasi sederhana: hostname, minimal 1 titik, bukan domain sendiri
    if ! [[ "$bug" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || [[ "$bug" != *.* ]] || [[ "$bug" == "$domain" ]]; then
        echo ""
        echo "ERROR: Bug Host tidak valid! Isi hostname saja, contoh: support.zoom.us"
        echo "Kosongkan saja kalau tidak pakai wildcard."
        exit 1
    fi
    # format trial: add = bug, host/sni = bug.domain
    wildcard="${bug}.${domain}"
    add_host="${bug}"
    host_name="${wildcard}"
    sni_name="${wildcard}"
fi

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
(.inbounds[] | select(.tag=="vmess-ws-tls").settings.clients) +=
[{"id":$uuid,"alterId":0,"email":$user}] |

(.inbounds[] | select(.tag=="vmess-ws-nontls").settings.clients) +=
[{"id":$uuid,"alterId":0,"email":$user}] |

(.inbounds[] | select(.tag=="vmess-grpc").settings.clients) +=
[{"id":$uuid,"alterId":0,"email":$user}]
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
echo "${user} ${exp} ${uuid}" >> /etc/xray/vmess.db

# generate vmess tls
vmess_json_tls=$(cat <<EOF
{
  "v":"2",
  "ps":"${user}",
  "add":"${add_host}",
  "port":"${tls}",
  "id":"${uuid}",
  "aid":"0",
  "net":"ws",
  "type":"none",
  "host":"${host_name}",
  "path":"/vmess",
  "tls":"tls",
  "sni":"${sni_name}"
}
EOF
)

# generate vmess nontls
vmess_json_none=$(cat <<EOF
{
  "v":"2",
  "ps":"${user}",
  "add":"${add_host}",
  "port":"${none}",
  "id":"${uuid}",
  "aid":"0",
  "net":"ws",
  "type":"none",
  "host":"${host_name}",
  "path":"/vmess",
  "tls":"none"
}
EOF
)

# encode vmess
vmesslink1="vmess://$(echo "$vmess_json_tls" | base64 -w 0)"
vmesslink2="vmess://$(echo "$vmess_json_none" | base64 -w 0)"

# grpc link
vmess_json_grpc=$(cat <<EOF
{
  "v":"2",
  "ps":"${user}",
  "add":"${add_host}",
  "port":"${grpc}",
  "id":"${uuid}",
  "aid":"0",
  "net":"grpc",
  "type":"gun",
  "host":"${host_name}",
  "path":"vmess-grpc",
  "tls":"tls",
  "sni":"${sni_name}"
}
EOF
)

vmesslink3="vmess://$(echo "$vmess_json_grpc" | base64 -w 0)"

clear

echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\E[44;1;39m        XRAY VMESS ACCOUNT       \E[0m"
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "Remarks        : ${user}"
echo -e "Domain         : ${domain}"
if [[ -n "$bug" ]]; then
echo -e "Bug Host       : ${bug}"
echo -e "Wildcard       : ${wildcard}"
else
echo -e "Wildcard       : - (isi Bug Host saat create untuk aktifkan)"
fi
echo -e "Port TLS       : ${tls}"
echo -e "Port none TLS  : ${none}"
echo -e "Port gRPC      : ${grpc}"
echo -e "UUID           : ${uuid}"
echo -e "Alter ID       : 0"
echo -e "Encryption     : auto"
echo -e "Network        : ws / grpc"
echo -e "Path           : /vmess"
echo -e "ServiceName    : vmess-grpc"
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "Link TLS       :"
echo -e "${vmesslink1}"
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "Link none TLS  :"
echo -e "${vmesslink2}"
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "Link gRPC      :"
echo -e "${vmesslink3}"
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "Expired On     : ${exp}"
echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"

if [[ -n "$bug" ]]; then
echo -e "CATATAN: pastikan record wildcard * di Cloudflare sudah dibuat"
echo -e "(* -> IP VPS, DNS-only), kalau belum link wildcard tidak akan konek."
echo ""
fi
echo ""
echo "Database User  : /etc/xray/vmess.db"
echo ""

read -n 1 -s -r -p "Tekan apa saja untuk kembali ke menu..."

m-vmess