#!/usr/bin/env bash

# Simple interactive site manager for Apache / Nginx
# Cocok untuk:
# - Domain utama (contoh: khoirulanam.web.id)
# - Subdomain (contoh: sneat.khoirulanam.web.id, portofolio.khoirulanam.web.id)
# Mendukung:
# - HTML / PHP (DocumentRoot ke folder)
# - Reverse proxy (Node.js, n8n, dsb.)

set -e

########################################
# Helper
########################################

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    echo "Script ini harus dijalankan sebagai root. Contoh:"
    echo "  sudo $0"
    exit 1
  fi
}

ask_yes_no() {
  # usage: ask_yes_no "Pesan" "default"
  local prompt="$1"
  local default="${2:-N}" # default N
  local hint="[y/N]"
  [[ "$default" == "Y" || "$default" == "y" ]] && hint="[Y/n]"

  read -rp "$prompt $hint: " ans
  ans="${ans:-$default}"
  case "$ans" in
    [Yy]) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_package() {
  local pkg="$1"
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    if ask_yes_no "Paket '$pkg' belum terinstall. Install sekarang?" "N"; then
      apt-get update
      apt-get install -y "$pkg"
    else
      echo "OK, paket '$pkg' tidak diinstall. Beberapa fitur mungkin tidak jalan."
    fi
  fi
}

detect_ip() {
  hostname -I 2>/dev/null | awk '{print $1}'
}

pause() {
  read -rp "Tekan ENTER untuk lanjut..."
}

########################################
# Server detection
########################################

detect_servers() {
  HAVE_APACHE=0
  HAVE_NGINX=0

  if command -v apache2 >/dev/null 2>&1 || [[ -x /usr/sbin/apache2 ]]; then
    HAVE_APACHE=1
  fi
  if command -v nginx >/dev/null 2>&1 || [[ -x /usr/sbin/nginx ]]; then
    HAVE_NGINX=1
  fi
}

choose_server() {
  detect_servers

  local choice=""
  while true; do
    echo ""
    echo "Pilih web server yang ingin kamu pakai:"
    if [[ $HAVE_APACHE -eq 1 ]]; then
      echo "  1) Apache"
    else
      echo "  1) Apache (belum terinstall)"
    fi
    if [[ $HAVE_NGINX -eq 1 ]]; then
      echo "  2) Nginx"
    else
      echo "  2) Nginx (belum terinstall)"
    fi
    echo "  0) Batal"

    read -rp "Pilihan [1/2/0]: " choice
    case "$choice" in
      1)
        ensure_package apache2
        HAVE_APACHE=1
        SERVER_CHOICE="apache"
        break
        ;;
      2)
        ensure_package nginx
        HAVE_NGINX=1
        SERVER_CHOICE="nginx"
        break
        ;;
      0)
        SERVER_CHOICE=""
        break
        ;;
      *)
        echo "Pilihan tidak dikenal."
        ;;
    esac
  done
}

########################################
# Config path helper
########################################

get_apache_conf_path() {
  local domain="$1"
  echo "/etc/apache2/sites-available/${domain}.conf"
}

get_nginx_conf_path() {
  local domain="$1"
  echo "/etc/nginx/sites-available/${domain}.conf"
}

########################################
# Create site
########################################

create_site() {
  echo ""
  echo "=== Buat Site Baru (Domain / Subdomain) ==="
  echo ""
  echo "Contoh domain:"
  echo "  - Domain utama : khoirulanam.web.id"
  echo "  - Subdomain    : sneat.khoirulanam.web.id"
  echo ""

  read -rp "Masukkan domain lengkap (wajib, contoh: sneat.khoirulanam.web.id): " DOMAIN
  if [[ -z "$DOMAIN" ]]; then
    echo "Domain tidak boleh kosong."
    return
  fi

  echo ""
  echo "Folder website (DocumentRoot) adalah tempat file index.php / index.html kamu."
  echo "Contoh:"
  echo "  - /var/www/sneat"
  echo "  - /var/www/html/sneat"
  echo ""
  read -rp "Masukkan path folder website (DocumentRoot): " DOCROOT
  if [[ -z "$DOCROOT" ]]; then
    echo "DocumentRoot tidak boleh kosong."
    return
  fi

  if [[ ! -d "$DOCROOT" ]]; then
    if ask_yes_no "Folder '$DOCROOT' belum ada. Buat sekarang?" "Y"; then
      mkdir -p "$DOCROOT"
      chown -R www-data:www-data "$DOCROOT"
    else
      echo "Batal membuat site karena folder belum ada."
      return
    fi
  fi

  echo ""
  echo "Pilih mode site:"
  echo "  1) HTML / PHP biasa (file langsung dari folder DocumentRoot)"
  echo "  2) Reverse proxy (untuk Node.js, n8n, dsb. di port tertentu)"
  read -rp "Mode [1/2]: " MODE
  case "$MODE" in
    1) SITE_MODE="static" ;;
    2) SITE_MODE="proxy" ;;
    *)
      echo "Pilihan tidak dikenal, default ke mode 'static HTML/PHP'."
      SITE_MODE="static"
      ;;
  esac

  if [[ "$SITE_MODE" == "proxy" ]]; then
    echo ""
    echo "Contoh port aplikasi:"
    echo "  - Node / Express : 3000"
    echo "  - n8n            : 5678"
    echo ""
    read -rp "Masukkan port aplikasi tujuan (contoh 3000): " APP_PORT
    if [[ -z "$APP_PORT" ]]; then
      echo "Port tidak boleh kosong."
      return
    fi
  fi

  # pilih server
  choose_server
  if [[ -z "$SERVER_CHOICE" ]]; then
    echo "Tidak ada server yang dipilih. Batal."
    return
  fi

  if [[ "$SERVER_CHOICE" == "apache" ]]; then
    create_site_apache
  else
    create_site_nginx
  fi

  local IP
  IP=$(detect_ip)
  echo ""
  echo "=== INFO DNS ==="
  echo "Arahkan DNS A record di Cloudflare / panel domain kamu seperti ini:"
  echo "  Tipe : A"
  echo "  Nama : ${DOMAIN} (atau bagian depannya saja jika panel butuh, contoh 'sneat')"
  echo "  IP   : ${IP}"
  echo ""
  echo "Setelah DNS mengarah ke VPS, site bisa diakses via:"
  echo "  http://${DOMAIN}"
  echo "Jika ingin HTTPS, jalankan (di VPS):"
  echo "  sudo certbot --apache  -d ${DOMAIN}    # jika pakai Apache"
  echo "  sudo certbot --nginx   -d ${DOMAIN}    # jika pakai Nginx"
  echo ""
}

create_site_apache() {
  ensure_package apache2

  local CONF
  CONF=$(get_apache_conf_path "$DOMAIN")

  # aktifkan modul penting
  a2enmod rewrite >/dev/null 2>&1 || true
  if [[ "$SITE_MODE" == "proxy" ]]; then
    a2enmod proxy proxy_http headers >/dev/null 2>&1 || true
  fi

  echo ""
  echo "Mau aktifkan support PHP-FPM untuk file .php? (butuh php-fpm)"
  if ask_yes_no "Aktifkan PHP-FPM di Apache untuk site ini?" "N"; then
    USE_PHPFPM=1
    # cari socket php-fpm
    PHPFPM_SOCK=$(ls /run/php/php*-fpm.sock 2>/dev/null | head -n1 || true)
    if [[ -z "$PHPFPM_SOCK" ]]; then
      echo "Socket php-fpm tidak ditemukan. Pastikan php-fpm sudah diinstall (php8.x-fpm)."
      echo "Contoh: sudo apt-get install php-fpm"
      USE_PHPFPM=0
    else
      echo "PHP-FPM socket terdeteksi: $PHPFPM_SOCK"
    fi
  else
    USE_PHPFPM=0
  fi

  echo "Membuat file config Apache: $CONF"

  if [[ "$SITE_MODE" == "static" ]]; then
    cat >"$CONF" <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    DocumentRoot ${DOCROOT}

    <Directory ${DOCROOT}>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_access.log combined
EOF

    if [[ $USE_PHPFPM -eq 1 && -n "$PHPFPM_SOCK" ]]; then
      cat >>"$CONF" <<EOF

    <FilesMatch "\.php$">
        SetHandler "proxy:unix:${PHPFPM_SOCK}|fcgi://localhost/"
    </FilesMatch>
EOF
    fi

    echo "</VirtualHost>" >>"$CONF"

  else
    # reverse proxy
    cat >"$CONF" <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN}

    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}

    ProxyPass        /  http://127.0.0.1:${APP_PORT}/
    ProxyPassReverse /  http://127.0.0.1:${APP_PORT}/

    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_access.log combined
</VirtualHost>
EOF
  fi

  a2ensite "${DOMAIN}.conf"
  systemctl reload apache2
  echo ""
  echo "Site Apache untuk ${DOMAIN} sudah dibuat dan di-enable."
}

create_site_nginx() {
  ensure_package nginx

  local CONF
  CONF=$(get_nginx_conf_path "$DOMAIN")

  echo ""
  echo "Kalau kamu pakai PHP dengan Nginx, disarankan pakai PHP-FPM."
  if ask_yes_no "Aktifkan blok PHP-FPM di Nginx untuk site ini?" "N"; then
    USE_PHPFPM=1
    PHPFPM_SOCK=$(ls /run/php/php*-fpm.sock 2>/dev/null | head -n1 || true)
    if [[ -z "$PHPFPM_SOCK" ]]; then
      echo "Socket php-fpm tidak ditemukan. Pastikan php-fpm sudah diinstall."
      echo "Contoh: sudo apt-get install php-fpm"
      USE_PHPFPM=0
    else
      echo "PHP-FPM socket terdeteksi: $PHPFPM_SOCK"
    fi
  else
    USE_PHPFPM=0
  fi

  echo "Membuat file config Nginx: $CONF"

  if [[ "$SITE_MODE" == "static" ]]; then
    cat >"$CONF" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    root ${DOCROOT};
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
EOF

    if [[ $USE_PHPFPM -eq 1 && -n "$PHPFPM_SOCK" ]]; then
      cat >>"$CONF" <<EOF

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHPFPM_SOCK};
    }
EOF
    fi

    echo "}" >>"$CONF"

  else
    # reverse proxy
    cat >"$CONF" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
  fi

  ln -sf "$CONF" "/etc/nginx/sites-enabled/${DOMAIN}.conf"
  nginx -t && systemctl reload nginx
  echo ""
  echo "Site Nginx untuk ${DOMAIN} sudah dibuat dan di-enable."
}

########################################
# List sites
########################################

list_sites() {
  echo ""
  echo "=== Daftar Site (Apache & Nginx) ==="
  echo ""

  if [[ -d /etc/apache2/sites-available ]]; then
    echo "Apache:"
    ls /etc/apache2/sites-available/*.conf 2>/dev/null | sed 's#.*/##' || echo "  (tidak ada)"
    echo ""
  fi

  if [[ -d /etc/nginx/sites-available ]]; then
    echo "Nginx:"
    ls /etc/nginx/sites-available/*.conf 2>/dev/null | sed 's#.*/##' || echo "  (tidak ada)"
    echo ""
  fi

  pause
}

########################################
# Delete site
########################################

delete_site() {
  echo ""
  echo "=== Hapus Site (Uninstall) ==="
  echo "Contoh domain: sneat.khoirulanam.web.id"
  read -rp "Masukkan domain yang ingin dihapus: " DOMAIN
  if [[ -z "$DOMAIN" ]]; then
    echo "Domain tidak boleh kosong."
    return
  fi

  choose_server
  if [[ -z "$SERVER_CHOICE" ]]; then
    echo "Tidak ada server yang dipilih. Batal."
    return
  fi

  if [[ "$SERVER_CHOICE" == "apache" ]]; then
    local CONF
    CONF=$(get_apache_conf_path "$DOMAIN")
    if [[ ! -f "$CONF" ]]; then
      echo "Config Apache tidak ditemukan: $CONF"
      return
    fi
    a2dissite "${DOMAIN}.conf" || true
    rm -f "$CONF"
    systemctl reload apache2
    echo "Site Apache ${DOMAIN} sudah dihapus."

  else
    local CONF
    CONF=$(get_nginx_conf_path "$DOMAIN")
    if [[ ! -f "$CONF" ]]; then
      echo "Config Nginx tidak ditemukan: $CONF"
      return
    fi
    rm -f "$CONF"
    rm -f "/etc/nginx/sites-enabled/${DOMAIN}.conf"
    nginx -t && systemctl reload nginx
    echo "Site Nginx ${DOMAIN} sudah dihapus."
  fi

  if ask_yes_no "Hapus juga folder DocumentRoot? (BERBAHAYA, hati-hati)" "N"; then
    read -rp "Masukkan path folder yang akan dihapus (contoh /var/www/sneat): " FOLDER
    if [[ -n "$FOLDER" && -d "$FOLDER" ]]; then
      rm -rf "$FOLDER"
      echo "Folder $FOLDER sudah dihapus."
    else
      echo "Folder tidak ditemukan atau kosong. Tidak dihapus."
    fi
  fi
}

########################################
# Change DocumentRoot
########################################

change_docroot() {
  echo ""
  echo "=== Ubah DocumentRoot Site ==="
  echo "Fitur ini hanya aman untuk config yang dibuat oleh script ini."
  read -rp "Masukkan domain site yang ingin diubah: " DOMAIN
  if [[ -z "$DOMAIN" ]]; then
    echo "Domain tidak boleh kosong."
    return
  fi

  choose_server
  if [[ -z "$SERVER_CHOICE" ]]; then
    echo "Tidak ada server yang dipilih. Batal."
    return
  fi

  read -rp "Masukkan DocumentRoot baru (contoh /var/www/html/sneat): " NEWROOT
  if [[ -z "$NEWROOT" ]]; then
    echo "DocumentRoot baru tidak boleh kosong."
    return
  fi
  if [[ ! -d "$NEWROOT" ]]; then
    if ask_yes_no "Folder '$NEWROOT' belum ada. Buat sekarang?" "Y"; then
      mkdir -p "$NEWROOT"
      chown -R www-data:www-data "$NEWROOT"
    else
      echo "Batal mengubah DocumentRoot."
      return
    fi
  fi

  if [[ "$SERVER_CHOICE" == "apache" ]]; then
    local CONF
    CONF=$(get_apache_conf_path "$DOMAIN")
    if [[ ! -f "$CONF" ]]; then
      echo "Config Apache tidak ditemukan: $CONF"
      return
    fi
    # ganti DocumentRoot dan <Directory ...>
    sed -i "s#^ *DocumentRoot .*#    DocumentRoot ${NEWROOT}#g" "$CONF"
    sed -i "s#^ *<Directory .*#    <Directory ${NEWROOT}>#g" "$CONF"
    systemctl reload apache2
    echo "DocumentRoot Apache untuk ${DOMAIN} sudah diupdate menjadi: ${NEWROOT}"

  else
    local CONF
    CONF=$(get_nginx_conf_path "$DOMAIN")
    if [[ ! -f "$CONF" ]]; then
      echo "Config Nginx tidak ditemukan: $CONF"
      return
    fi
    sed -i "s#^ *root .*#    root ${NEWROOT};#g" "$CONF"
    nginx -t && systemctl reload nginx
    echo "root Nginx untuk ${DOMAIN} sudah diupdate menjadi: ${NEWROOT}"
  fi
}

########################################
# Main menu
########################################

main_menu() {
  while true; do
    echo ""
    echo "======================================="
    echo "  Site Manager (Apache / Nginx)"
    echo "======================================="
    echo "1) Buat site baru (domain / subdomain)"
    echo "2) List semua site"
    echo "3) Hapus site (uninstall)"
    echo "4) Ubah DocumentRoot site"
    echo "0) Keluar"
    echo "---------------------------------------"
    read -rp "Pilih menu [1-4/0]: " MENU

    case "$MENU" in
      1) create_site ;;
      2) list_sites ;;
      3) delete_site ;;
      4) change_docroot ;;
      0)
        echo "Keluar. Bye!"
        break
        ;;
      *)
        echo "Pilihan tidak dikenal."
        ;;
    esac
  done
}

########################################
# RUN
########################################

require_root
main_menu
