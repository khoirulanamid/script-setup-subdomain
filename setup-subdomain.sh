#!/bin/bash

# =========================================
#   AUTO SUBDOMAIN SETUP FOR APACHE2
#   Usage: bash setup-subdomain.sh sneat /var/www/sneat
# =========================================

if [ "$#" -ne 2 ]; then
    echo "Cara pakai:"
    echo "  bash $0 subdomain folder_path"
    echo "Contoh:"
    echo "  bash $0 sneat /var/www/sneat"
    exit 1
fi

SUBDOMAIN=$1
FOLDER=$2
DOMAIN="khoirulanam.cloud"

FULL_DOMAIN="$SUBDOMAIN.$DOMAIN"
CONF_FILE="/etc/apache2/sites-available/$SUBDOMAIN.conf"

echo "-------------------------------------------"
echo " Membuat subdomain: $FULL_DOMAIN"
echo " Folder DocumentRoot: $FOLDER"
echo "-------------------------------------------"

# Buat folder jika belum ada
if [ ! -d "$FOLDER" ]; then
    echo "Folder belum ada, membuat folder..."
    sudo mkdir -p "$FOLDER"
    sudo chown -R www-data:www-data "$FOLDER"
fi

# Membuat file konfigurasi Apache
echo "Membuat file konfigurasi Apache..."

sudo bash -c "cat > $CONF_FILE" << EOF
<VirtualHost *:80>
    ServerName $FULL_DOMAIN
    DocumentRoot $FOLDER

    <Directory $FOLDER>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$SUBDOMAIN-error.log
    CustomLog \${APACHE_LOG_DIR}/$SUBDOMAIN-access.log combined
</VirtualHost>
EOF

echo "Mengaktifkan VirtualHost..."
sudo a2ensite "$SUBDOMAIN.conf"

echo "Reload Apache..."
sudo systemctl reload apache2

echo ""
echo "-------------------------------------------"
echo " Subdomain sudah aktif di HTTP"
echo " URL: http://$FULL_DOMAIN"
echo "-------------------------------------------"
echo ""

read -p "Apakah ingin mengaktifkan HTTPS + SSL Let's Encrypt? (y/n): " SSL_CHOICE

if [ "$SSL_CHOICE" == "y" ]; then
    echo "Mengaktifkan SSL menggunakan Certbot..."
    sudo certbot --apache -d "$FULL_DOMAIN"
else
    echo "SSL dilewati..."
fi

echo ""
echo "-------------------------------------------"
echo " SETUP SELESAI!"
echo " Akses sekarang:"
echo "   http://$FULL_DOMAIN"
echo "-------------------------------------------"
