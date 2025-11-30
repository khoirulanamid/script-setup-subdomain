#!/usr/bin/env bash
# Simple Site Manager (Apache / Nginx)
# by ChatGPT & Khoirul Anam
# Versi: 1.0 (rebuild)

###########################
# Helper & util functions #
###########################

ask_yn() {
  # Usage: ask_yn "Pesan" default
  # default: Y atau N (tanpa huruf lain)
  local prompt default answer
  default="${2:-N}"
  if [[ "$default" == "Y" ]]; then
    prompt=" [Y/n] "
  else
    prompt=" [y/N] "
  fi
  while true; do
    read -r -p "$1$prompt" answer
    answer="${answer:-$default}"
    case "${answer}" in
      [Yy]) return 0 ;;
      [Nn]) return 1 ;;
      *) echo "Jawaban tidak dikenali. Ketik y atau n." ;;
    esac
  done
}

detect_ip() {
  hostname -I 2>/dev/null | awk '{print $1}'
}

pause() {
  read -rp "Tekan ENTER untuk lanjut..."
}

######################
# Webserver handling #
######################

WEB=""
APACHE_CONF_DIR="/etc/apache2/sites-available"
APACHE_ENABLED_DIR="/etc/apache2/sites-enabled"
NGINX_CONF_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"

detect_web() {
  if command -v apache2ctl >/dev/null 2>&1; then
    WEB="apache"
  elif command -v nginx >/dev/null 2>&1; then
    WEB="nginx"
  else
    WEB=""
  fi
}

ensure_package() {
  local pkg="$1"
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    echo "Paket $pkg belum terinstall."
    if ask_yn "Install $pkg sekarang?" "N"; then
      sudo apt-get update
      sudo apt-get install -y "$pkg"
    else
      echo "Lewati install $pkg."
    fi
  fi
}

ensure_webserver() {
  detect_web
  if [[ -z "$WEB" ]]; then
    echo "Belum ada Apache2 maupun Nginx di server ini."
    echo "1) Install Apache2"
    echo "2) Install Nginx"
    echo "0) Batal"
    read -rp "Pilih [1/2/0]: " wchoice
    case "$wchoice" in
      1)
        ensure_package apache2
        WEB="apache"
        ;;
      2)
        ensure_package nginx
        WEB="nginx"
        ;;
      *)
        echo "Batal."
        exit 1
        ;;
    esac
  else
    echo "Terdeteksi web server: $WEB"
  fi
}

reload_web() {
  if [[ "$WEB" == "apache" ]]; then
    sudo systemctl reload apache2
  elif [[ "$WEB" == "nginx" ]]; then
    sudo systemctl reload nginx
  fi
}

get_conf_path() {
  local domain="$1"
  if [[ "$WEB" == "apache" ]]; then
    echo "$APACHE_CONF_DIR/${domain}.conf"
  else
    echo "$NGINX_CONF_DIR/${domain}.conf"
  fi
}

enable_site() {
  local domain="$1"
  if [[ "$WEB" == "apache" ]]; then
    sudo a2ensite "${domain}.conf"
  else
    sudo ln -sf "$(get_conf_path "$domain")" "$NGINX_ENABLED_DIR/${domain}.conf"
  fi
  reload_web
}

disable_site() {
  local domain="$1"
  if [[ "$WEB" == "apache" ]]; then
    sudo a2dissite "${domain}.conf" || true
  else
    sudo rm -f "$NGINX_ENABLED_DIR/${domain}.conf"
  fi
  reload_web
}

###################
# Certbot helpers #
###################

ensure_certbot() {
  if ! command -v certbot >/dev/null 2>&1; then
    echo "Certbot belum terinstall."
    if ask_yn "Install certbot sekarang?" "N"; then
      if [[ "$WEB" == "apache" ]]; then
        ensure_package python3-certbot-apache
      else
        ensure_package python3-certbot-nginx
      fi
    fi
  fi
}

obtain_ssl() {
  local domain="$1"
  ensure_certbot
  if ! command -v certbot >/dev/null 2>&1; then
    echo "Certbot belum tersedia. Lewati SSL."
    return
  fi
  if ask_yn "Ingin mengaktifkan HTTPS (Let's Encrypt) untuk $domain?" "Y"; then
    if [[ "$WEB" == "apache" ]]; then
      sudo certbot --apache -d "$domain"
    else
      sudo certbot --nginx -d "$domain"
    fi
  fi
}

delete_cert() {
  local domain="$1"
  if command -v certbot >/dev/null 2>&1; then
    echo "Menghapus sertifikat Let's Encrypt (jika ada) untuk $domain ..."
    sudo certbot delete --cert-name "$domain" >/dev/null 2>&1 || true
  fi
}

#########################
# Template virtual host #
#########################

create_vhost_file() {
  local domain="$1"
  local docroot="$2"
  local use_php="$3"      # "yes" or "no"
  local conf
  conf="$(get_conf_path "$domain")"

  if [[ "$WEB" == "apache" ]]; then
    sudo tee "$conf" >/dev/null <<EOF
<VirtualHost *:80>
    ServerName $domain
    DocumentRoot $docroot

    <Directory $docroot>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${domain}_error.log
    CustomLog \${APACHE_LOG_DIR}/${domain}_access.log combined
EOF

    if [[ "$use_php" == "yes" ]]; then
      sudo tee -a "$conf" >/dev/null <<'EOF'

    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php/php-fpm.sock|fcgi://localhost/"
    </FilesMatch>
EOF
      echo "  (Catatan: sesuaikan path socket PHP-FPM di FilesMatch jika berbeda.)"
    fi

    sudo tee -a "$conf" >/dev/null <<EOF
</VirtualHost>
EOF

  else # nginx
    sudo tee "$conf" >/dev/null <<EOF
server {
    listen 80;
    server_name $domain;

    root $docroot;
    index index.php index.html index.htm;

    access_log /var/log/nginx/${domain}_access.log;
    error_log /var/log/nginx/${domain}_error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
EOF

    if [[ "$use_php" == "yes" ]]; then
      sudo tee -a "$conf" >/dev/null <<'EOF'

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php-fpm.sock;
    }
EOF
      echo "  (Catatan: sesuaikan fastcgi_pass jika socket PHP-FPM kamu beda.)"
    fi

    sudo tee -a "$conf" >/dev/null <<'EOF'

    location ~ /\.ht {
        deny all;
    }
}
EOF
  fi

  echo "File config dibuat: $conf"
}

create_reverse_proxy_vhost() {
  local domain="$1"
  local target="$2"
  local conf
  conf="$(get_conf_path "$domain")"

  if [[ "$WEB" == "apache" ]]; then
    sudo tee "$conf" >/dev/null <<EOF
<VirtualHost *:80>
    ServerName $domain

    ProxyPreserveHost On
    ProxyPass / $target/
    ProxyPassReverse / $target/

    ErrorLog \${APACHE_LOG_DIR}/${domain}_proxy_error.log
    CustomLog \${APACHE_LOG_DIR}/${domain}_proxy_access.log combined
</VirtualHost>
EOF
  else
    sudo tee "$conf" >/dev/null <<EOF
server {
    listen 80;
    server_name $domain;

    location / {
        proxy_pass $target;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    access_log /var/log/nginx/${domain}_proxy_access.log;
    error_log /var/log/nginx/${domain}_proxy_error.log;
}
EOF
  fi

  echo "File config proxy dibuat: $conf"
}

#########################
# Menu: Create new site #
#########################

menu_create_site() {
  echo "=== Buat site baru (domain / subdomain) ==="
  echo "Contoh domain: khoirulanam.web.id"
  echo "Contoh subdomain: profile.khoirulanam.web.id"
  read -rp "Masukkan nama domain / subdomain: " domain
  [[ -z "$domain" ]] && { echo "Domain tidak boleh kosong."; return; }

  echo
  echo "Contoh folder:"
  echo "  /var/www/html/profile    (untuk subdomain profile)"
  echo "  /var/www/wordpress       (untuk WordPress)"
  read -rp "Masukkan path DocumentRoot (folder web): " docroot
  [[ -z "$docroot" ]] && { echo "DocumentRoot tidak boleh kosong."; return; }

  if [[ ! -d "$docroot" ]]; then
    echo "Folder $docroot belum ada."
    if ask_yn "Buat folder $docroot sekarang?" "Y"; then
      sudo mkdir -p "$docroot"
      sudo chown -R "$USER":"$USER" "$docroot"
    else
      echo "Batal buat site."
      return
    fi
  fi

  local use_php="no"
  if ask_yn "Apakah site ini memakai PHP (WordPress, Laravel, dll)?" "N"; then
    use_php="yes"
    ensure_package php-fpm
  fi

  create_vhost_file "$domain" "$docroot" "$use_php"
  enable_site "$domain"
  echo "Site $domain aktif. Coba buka: http://$domain"

  local ip
  ip="$(detect_ip)"
  echo "IP server terdeteksi: $ip"
  echo "Pastikan di Cloudflare / DNS:"
  echo "  A $domain → $ip"

  obtain_ssl "$domain"
}

#########################
# Menu: Reverse proxy   #
#########################

menu_reverse_proxy() {
  echo "=== Buat site Reverse Proxy (Node, n8n, dsb.) ==="
  read -rp "Masukkan domain / subdomain (contoh: n8n.khoirulanam.web.id): " domain
  [[ -z "$domain" ]] && { echo "Domain tidak boleh kosong."; return; }

  echo "Masukkan target URL aplikasi (contoh: http://127.0.0.1:5678 atau http://localhost:3000)"
  read -rp "Target URL: " target
  [[ -z "$target" ]] && { echo "Target tidak boleh kosong."; return; }

  create_reverse_proxy_vhost "$domain" "$target"
  enable_site "$domain"

  local ip
  ip="$(detect_ip)"
  echo "IP server: $ip"
  echo "Atur DNS: A $domain → $ip"

  obtain_ssl "$domain"
}

#########################
# Menu: List all sites  #
#########################

menu_list_sites() {
  echo "=== Daftar site (vhost) ==="
  if [[ "$WEB" == "apache" ]]; then
    ls -1 "$APACHE_CONF_DIR"
  else
    ls -1 "$NGINX_CONF_DIR"
  fi
}

#########################
# Menu: Uninstall site  #
#########################

menu_uninstall_site() {
  echo "=== Uninstall site ==="
  read -rp "Masukkan domain / subdomain yang mau dihapus: " domain
  [[ -z "$domain" ]] && { echo "Tidak boleh kosong."; return; }

  local conf
  conf="$(get_conf_path "$domain")"

  if [[ ! -f "$conf" ]]; then
    echo "File config $conf tidak ditemukan."
    return
  fi

  echo "Akan menghapus site $domain."
  echo "Config: $conf"

  if ask_yn "Lanjut hapus site ini?" "N"; then
    disable_site "$domain"
    sudo rm -f "$conf"
    echo "Config vhost dihapus."

    if ask_yn "Hapus juga folder DocumentRoot (jika yakin)?" "N"; then
      # cari DocumentRoot / root dari conf
      local docroot
      if [[ "$WEB" == "apache" ]]; then
        docroot=$(grep -i "DocumentRoot" "$conf" 2>/dev/null | awk '{print $2}' | head -n1)
      else
        docroot=$(grep -i "root " "$conf" 2>/dev/null | awk '{print $2}' | sed 's/;//' | head -n1)
      fi
      if [[ -n "$docroot" && -d "$docroot" ]]; then
        echo "Menghapus folder $docroot ..."
        sudo rm -rf "$docroot"
      else
        echo "DocumentRoot tidak ditemukan / folder sudah hilang."
      fi
    fi

    delete_cert "$domain"
    echo "Uninstall selesai."
  else
    echo "Batal uninstall."
  fi
}

############################
# Menu: Change DocumentRoot #
############################

menu_change_docroot() {
  echo "=== Ubah DocumentRoot site ==="
  read -rp "Masukkan domain / subdomain: " domain
  [[ -z "$domain" ]] && { echo "Tidak boleh kosong."; return; }

  local conf current_docroot
  conf="$(get_conf_path "$domain")"

  if [[ ! -f "$conf" ]]; then
    echo "Config $conf tidak ditemukan."
    return
  fi

  if [[ "$WEB" == "apache" ]]; then
    current_docroot=$(grep -i "DocumentRoot" "$conf" | awk '{print $2}' | head -n1)
  else
    current_docroot=$(grep -i "root " "$conf" | awk '{print $2}' | sed 's/;//' | head -n1)
  fi

  echo "DocumentRoot saat ini: ${current_docroot:-tidak ditemukan}"
  echo "Contoh baru:"
  echo "  /var/www/html/profile → /var/www/profile"
  read -rp "Masukkan DocumentRoot baru: " new_docroot
  [[ -z "$new_docroot" ]] && { echo "Tidak boleh kosong."; return; }

  if [[ ! -d "$new_docroot" ]]; then
    if ask_yn "Folder $new_docroot belum ada. Buat sekarang?" "Y"; then
      sudo mkdir -p "$new_docroot"
      sudo chown -R "$USER":"$USER" "$new_docroot"
    else
      echo "Batal mengubah DocumentRoot."
      return
    fi
  fi

  if [[ -n "$current_docroot" && -d "$current_docroot" ]]; then
    if ask_yn "Pindahkan semua isi dari $current_docroot ke $new_docroot?" "N"; then
      sudo rsync -a "$current_docroot"/ "$new_docroot"/
      echo "File telah dipindahkan."
    fi
  fi

  if [[ "$WEB" == "apache" ]]; then
    sudo sed -i "s#DocumentRoot $current_docroot#DocumentRoot $new_docroot#g" "$conf"
  else
    sudo sed -i "s#root $current_docroot;#root $new_docroot;#g" "$conf"
  fi

  reload_web
  echo "DocumentRoot untuk $domain sudah diubah menjadi $new_docroot."
}

###########################
# Menu: Domain Migrator   #
###########################

menu_domain_migrator() {
  echo "=== Migrasi domain (search & replace di file) ==="
  echo "Ini TIDAK langsung menyentuh database."
  echo "Untuk WordPress, tetap disarankan pakai WP-CLI search-replace."
  echo
  echo "Contoh:"
  echo "  Domain lama: wordpress.khoirulanam.web.id"
  echo "  Domain baru: wordpress.khoirulanam.web.id"
  echo "  Folder     : /var/www/wordpress"
  read -rp "Masukkan domain lama: " old_domain
  read -rp "Masukkan domain baru: " new_domain
  read -rp "Masukkan folder yang ingin di-scan (misal /var/www/wordpress): " folder

  if [[ -z "$old_domain" || -z "$new_domain" || -z "$folder" ]]; then
    echo "Input tidak boleh kosong."
    return
  fi
  if [[ ! -d "$folder" ]]; then
    echo "Folder $folder tidak ada."
    return
  fi

  echo
  echo "Ringkasan:"
  echo "  Ganti '$old_domain' → '$new_domain' di semua file teks di $folder"
  if ! ask_yn "Lanjut proses? (Backup manual dulu sebelum jalanin!)" "N"; then
    echo "Batal migrasi."
    return
  fi

  sudo grep -rl --exclude-dir=".git" "$old_domain" "$folder" | sudo xargs sed -i "s#$old_domain#$new_domain#g"
  echo "Search & replace selesai."
}

############
# Main menu #
############

main_menu() {
  while true; do
    echo
    echo "==================================="
    echo "   Simple Site Manager (Apache/Nginx)"
    echo "==================================="
    echo "Web server aktif : $WEB"
    echo "IP server        : $(detect_ip)"
    echo
    echo "1) Buat site baru (domain / subdomain)"
    echo "2) Migrasi domain (search & replace file)"
    echo "3) Uninstall site (hapus vhost + opsional folder + certbot)"
    echo "4) List semua site"
    echo "5) Ubah DocumentRoot"
    echo "6) Buat site Reverse Proxy (n8n, Node, dsb.)"
    echo "0) Keluar"
    read -rp "Pilih menu [0-6]: " choice

    case "$choice" in
      1) menu_create_site ;;
      2) menu_domain_migrator ;;
      3) menu_uninstall_site ;;
      4) menu_list_sites ;;
      5) menu_change_docroot ;;
      6) menu_reverse_proxy ;;
      0) echo "Keluar."; break ;;
      *) echo "Pilihan tidak dikenali." ;;
    esac
    pause
  done
}

################
# Entry point  #
################

ensure_webserver
main_menu
