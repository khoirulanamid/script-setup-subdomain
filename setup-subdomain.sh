#!/usr/bin/env bash
# setup-subdomain.sh
# Script “pintar” untuk bikin VirtualHost Apache + (opsional) HTTPS Let's Encrypt
# Bisa untuk domain utama atau subdomain.
# Contoh pakai:
#   sudo bash setup-subdomain.sh
#   sudo bash setup-subdomain.sh sneat /var/www/sneat
#   sudo bash setup-subdomain.sh sneat.khoirulanam.cloud /var/www/html/sneat

set -e

# --- Cek harus root ---
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Jalankan script ini sebagai root: sudo bash setup-subdomain.sh"
  exit 1
fi

# --- Cek OS pakai apt (Ubuntu/Debian) ---
if ! command -v apt >/dev/null 2>&1; then
  echo "❌ Script ini dibuat untuk Ubuntu/Debian (pakai apt)."
  exit 1
fi

echo "➡️  Update paket & cek Apache/PHP/Certbot..."
apt update -y

# Install Apache, PHP, Certbot kalau belum ada
apt install -y apache2 php libapache2-mod-php certbot python3-certbot-apache

# Aktifkan modul penting Apache
a2enmod rewrite ssl headers proxy proxy_http proxy_wstunnel >/dev/null 2>&1 || true

# --- Ambil argumen / input user ---
RAW_DOMAIN="$1"
DOCROOT="$2"

# Fungsi tanya dengan default
ask() {
  local prompt="$1"
  local default="$2"
  local var
  if [ -n "$default" ]; then
    read -rp "$prompt [$default]: " var
    var="${var:-$default}"
  else
    read -rp "$prompt: " var
  fi
  echo "$var"
}

echo ""
echo "============================================"
echo "   Setup VirtualHost Apache (domain/subdomain)"
echo "============================================"
echo ""

# 1) Tentukan domain FQDN (misal: khoirulanam.cloud atau sneat.khoirulanam.cloud)
FQDN=""

if [ -n "$RAW_DOMAIN" ]; then
  if [[ "$RAW_DOMAIN" == *.* ]]; then
    # Argumen sudah full domain, contoh: sneat.khoirulanam.cloud
    FQDN="$RAW_DOMAIN"
  else
    echo "Argumen pertama hanya subdomain (tanpa domain utama): $RAW_DOMAIN"
    MAIN_DOMAIN=$(ask "Masukkan domain utama kamu (contoh: khoirulanam.cloud)" "")
    if [ -z "$MAIN_DOMAIN" ]; then
      echo "❌ Domain utama tidak boleh kosong."
      exit 1
    fi
    FQDN="${RAW_DOMAIN}.${MAIN_DOMAIN}"
  fi
else
  # Interaktif: tanya langsung domain lengkap
  FQDN=$(ask "Masukkan domain lengkap (contoh: khoirulanam.cloud atau sneat.khoirulanam.cloud)" "")
fi

if [ -z "$FQDN" ]; then
  echo "❌ Domain tidak boleh kosong."
  exit 1
fi

echo "✅ Domain yang akan dikonfigurasi: $FQDN"

# 2) Tentukan DocumentRoot (folder web)
if [ -z "$DOCROOT" ]; then
  # Coba tebak default dari domain
  LABEL="${FQDN%%.*}"   # ambil bagian pertama sebelum titik
  DEFAULT_DOCROOT="/var/www/${LABEL}"
  DOCROOT=$(ask "Masukkan folder untuk file web (DocumentRoot)" "$DEFAULT_DOCROOT")
fi

echo "✅ DocumentRoot: $DOCROOT"

# --- Buat folder jika belum ada ---
if [ ! -d "$DOCROOT" ]; then
  echo "📁 Folder $DOCROOT belum ada, membuat..."
  mkdir -p "$DOCROOT"
fi

# Ubah ownership ke www-data (user Apache)
chown -R www-data:www-data "$DOCROOT"
chmod -R 755 "$DOCROOT"

# --- Buat index default jika folder kosong ---
if [ -z "$(ls -A "$DOCROOT")" ]; then
  echo "ℹ️  Folder masih kosong, membuat index.php sederhana..."
  cat > "$DOCROOT/index.php" <<EOF
<?php
  // Halaman default sementara
  phpinfo();
EOF
fi

# --- Buat file VirtualHost Apache ---
CONF_NAME="${FQDN//./-}.conf"   # ganti titik jadi dash untuk nama file
CONF_PATH="/etc/apache2/sites-available/${CONF_NAME}"

echo "📝 Membuat konfigurasi Apache: $CONF_PATH"

cat > "$CONF_PATH" <<EOF
<VirtualHost *:80>
    ServerName ${FQDN}
    DocumentRoot ${DOCROOT}

    <Directory ${DOCROOT}>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${FQDN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${FQDN}_access.log combined
</VirtualHost>
EOF

# --- Enable site & reload Apache ---
echo "🔗 Mengaktifkan site di Apache..."
a2ensite "$CONF_NAME" >/dev/null
systemctl reload apache2

echo ""
echo "✅ VirtualHost HTTP untuk ${FQDN} sudah dibuat."
echo "   Coba akses:  http://${FQDN}"
echo ""

# --- Tanya mau pasang HTTPS atau tidak ---
echo "🔒 Mau pasang HTTPS (Let's Encrypt) untuk ${FQDN}?"
echo "    Pastikan DNS A record untuk ${FQDN} sudah mengarah ke IP VPS ini,"
echo "    dan di Cloudflare sebaiknya sementara DNS Only (awan abu-abu) saat run certbot."
USE_SSL=$(ask "Pasang SSL sekarang? (y/n)" "y")

if [[ "$USE_SSL" =~ ^[Yy]$ ]]; then
  echo "🚀 Menjalankan certbot untuk $FQDN ..."
  certbot --apache -d "$FQDN"
  echo "✅ HTTPS selesai. Coba akses: https://${FQDN}"
else
  echo "ℹ️  HTTPS dilewati. Kamu bisa pasang nanti dengan:"
  echo "    sudo certbot --apache -d ${FQDN}"
fi

echo ""
echo "🎉 Selesai! Domain/subdomain ${FQDN} sekarang pointing ke ${DOCROOT}"
echo ""
