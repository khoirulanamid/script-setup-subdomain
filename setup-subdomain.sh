#!/bin/bash

echo "==========================================="
echo "     AUTO SUBDOMAIN APACHE SETUP SCRIPT    "
echo "==========================================="

# Ask for domain
read -p "Masukkan domain utama kamu (contoh: khoirulanam.cloud): " DOMAIN

# Ask for subdomain
read -p "Masukkan nama subdomain (contoh: sneat): " SUB

# Ask for folder
read -p "Masukkan lokasi folder web (contoh: /var/www/sneat): " FOLDER

FULL_DOMAIN="$SUB.$DOMAIN"

echo ""
echo "-------------------------------------------"
echo "Subdomain yang akan dibuat: $FULL_DOMAIN"
echo "Folder target: $FOLDER"
echo "-------------------------------------------"
echo ""

# Create directory if not exists
if [ ! -d "$FOLDER" ]; then
    mkdir -p $FOLDER
    echo "Folder dibuat: $FOLDER"
else
    echo "Folder sudah ada: $FOLDER"
fi

# Create simple index file if empty
if [ -z "$(ls -A $FOLDER)" ]; then
    echo "<h1>$FULL_DOMAIN berhasil dibuat!</h1>" >> $FOLDER/index.html
fi

# Create Apache config
CONF_FILE="/etc/apache2/sites-available/$SUB.conf"

echo "<VirtualHost *:80>
    ServerName $FULL_DOMAIN
    DocumentRoot $FOLDER

    <Directory $FOLDER>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$SUB-error.log
    CustomLog \${APACHE_LOG_DIR}/$SUB-access.log combined
</VirtualHost>" | sudo tee $CONF_FILE > /dev/null

echo "Apache config dibuat: $CONF_FILE"

# Enable site
sudo a2ensite $SUB.conf
sudo systemctl reload apache2

echo ""
echo "==========================================="
echo " Subdomain $FULL_DOMAIN berhasil diaktifkan"
echo "==========================================="

# Ask for SSL
read -p "Apakah ingin pasang SSL otomatis? (y/n): " SSL_CHOICE

if [[ "$SSL_CHOICE" == "y" || "$SSL_CHOICE" == "Y" ]]; then
    sudo certbot --apache -d $FULL_DOMAIN
    echo "SSL berhasil dipasang!"
else
    echo "SSL dilewati."
fi

echo ""
echo "==========================================="
echo "     PROSES SELESAI, SUBDOMAIN AKTIF       "
echo "  BUKA: http://$FULL_DOMAIN                "
echo "==========================================="
