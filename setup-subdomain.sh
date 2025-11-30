#!/usr/bin/env bash

SITES_AVAILABLE="/etc/apache2/sites-available"
SITES_ENABLED="/etc/apache2/sites-enabled"

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "✋ Harus dijalankan dengan sudo atau sebagai root."
    echo "Contoh: sudo bash setup-site.sh"
    exit 1
  fi
}

install_dependencies() {
  echo "🔍 Cek dependency (apache2, certbot)..."
  if ! command -v apache2 >/dev/null 2>&1; then
    echo "📦 apache2 belum ada, install dulu..."
    apt update && apt install -y apache2
  fi
  if ! command -v certbot >/dev/null 2>&1; then
    echo "📦 certbot belum ada, install dulu..."
    apt install -y certbot python3-certbot-apache
  fi
}

create_vhost_file() {
  local server_name="$1"
  local doc_root="$2"
  local conf_file="$SITES_AVAILABLE/${server_name}.conf"

  cat > "$conf_file" <<EOF
<VirtualHost *:80>
    ServerName $server_name
    DocumentRoot $doc_root

    <Directory $doc_root>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${server_name}-error.log
    CustomLog \${APACHE_LOG_DIR}/${server_name}-access.log combined
</VirtualHost>
EOF

  echo "✅ VirtualHost dibuat: $conf_file"
}

enable_site() {
  local server_name="$1"
  a2ensite "${server_name}.conf" >/dev/null 2>&1 || true
  systemctl reload apache2
  echo "🔁 Apache direload."
}

ask_for_https() {
  local server_name="$1"
  read -rp "🔐 Mau pasang HTTPS (Let's Encrypt) untuk $server_name? (y/n): " use_ssl
  if [[ "$use_ssl" =~ ^[Yy]$ ]]; then
    echo "⚡ Menjalankan: certbot --apache -d $server_name"
    certbot --apache -d "$server_name"
  else
    echo "➡ Lewati pemasangan HTTPS dulu."
  fi
}

create_site_interactive() {
  echo "=== Tambah Site Baru ==="
  echo "Contoh domain:"
  echo "  - Domain utama : khoirulanam.cloud"
  echo "  - Subdomain     : portofolio.khoirulanam.cloud"
  read -rp "📝 Masukkan nama domain lengkap (FQDN): " server_name

  if [[ -z "$server_name" ]]; then
    echo "❌ Domain tidak boleh kosong."
    return
  fi

  echo
  echo "Contoh folder DocumentRoot:"
  echo "  - /var/www/portofolio"
  echo "  - /var/www/html/sneat"
  read -rp "📂 Masukkan path folder DocumentRoot: " doc_root

  if [[ -z "$doc_root" ]]; then
    echo "❌ DocumentRoot tidak boleh kosong."
    return
  fi

  if [[ ! -d "$doc_root" ]]; then
    read -rp "📁 Folder $doc_root belum ada. Buat folder ini? (y/n): " mk
    if [[ "$mk" =~ ^[Yy]$ ]]; then
      mkdir -p "$doc_root"
      chown -R www-data:www-data "$doc_root"
      chmod -R 755 "$doc_root"
      echo "<h1>$server_name</h1><p>Site baru berhasil dibuat.</p>" > "$doc_root/index.html"
      echo "✅ Folder & index.html dibuat di $doc_root"
    else
      echo "❌ Folder tidak ada, batal buat site."
      return
    fi
  fi

  create_vhost_file "$server_name" "$doc_root"
  enable_site "$server_name"
  ask_for_https "$server_name"

  echo "🎉 Selesai! Coba buka: http://$server_name"
}

create_site_noninteractive() {
  # mode: bash setup-site.sh domain.com /var/www/folder
  local server_name="$1"
  local doc_root="$2"

  if [[ -z "$server_name" || -z "$doc_root" ]]; then
    echo "❌ Argumen kurang. Contoh:"
    echo "  sudo bash setup-site.sh portofolio.khoirulanam.cloud /var/www/portofolio"
    exit 1
  fi

  if [[ ! -d "$doc_root" ]]; then
    echo "📁 Folder $doc_root belum ada, buat sekarang..."
    mkdir -p "$doc_root"
    chown -R www-data:www-data "$doc_root"
    chmod -R 755 "$doc_root"
    echo "<h1>$server_name</h1><p>Site baru berhasil dibuat.</p>" > "$doc_root/index.html"
  fi

  create_vhost_file "$server_name" "$doc_root"
  enable_site "$server_name"
  ask_for_https "$server_name"
}

list_sites() {
  echo "=== Daftar Site (sites-available) ==="
  for f in "$SITES_AVAILABLE"/*.conf; do
    [ -e "$f" ] || { echo "Belum ada site."; return; }
    local name
    name=$(basename "$f")
    local server
    server=$(grep -m1 -i "ServerName" "$f" | awk '{print $2}')
    local status="disabled"
    if [[ -e "$SITES_ENABLED/$name" ]]; then
      status="enabled"
    fi
    printf "  %-30s  (%s)  →  %s\n" "$name" "$status" "$server"
  done
}

change_docroot() {
  echo "=== Ubah DocumentRoot Site ==="
  read -rp "📝 Masukkan domain (sesuai yang dipakai saat buat site, misal: portofolio.khoirulanam.cloud): " server_name
  local conf_file="$SITES_AVAILABLE/${server_name}.conf"

  if [[ ! -f "$conf_file" ]]; then
    echo "❌ File config tidak ditemukan: $conf_file"
    echo "Pastikan nama domain-nya sama persis."
    return
  fi

  local current_root
  current_root=$(grep -m1 "DocumentRoot" "$conf_file" | awk '{print $2}')
  echo "📂 DocumentRoot sekarang: $current_root"
  read -rp "📂 Masukkan DocumentRoot baru (misal: /var/www/html/sneat): " new_root

  if [[ -z "$new_root" ]]; then
    echo "❌ DocumentRoot baru tidak boleh kosong."
    return
  fi

  if [[ ! -d "$new_root" ]]; then
    read -rp "Folder $new_root belum ada. Buat folder ini? (y/n): " mk
    if [[ "$mk" =~ ^[Yy]$ ]]; then
      mkdir -p "$new_root"
      chown -R www-data:www-data "$new_root"
      chmod -R 755 "$new_root"
      echo "<h1>$server_name</h1><p>DocumentRoot baru: $new_root</p>" > "$new_root/index.html"
    else
      echo "❌ Batal ubah DocumentRoot."
      return
    fi
  fi

  sed -i "s|DocumentRoot $current_root|DocumentRoot $new_root|" "$conf_file"
  sed -i "s|<Directory $current_root>|<Directory $new_root>|" "$conf_file"

  echo "✅ DocumentRoot di $conf_file sudah diupdate."
  systemctl reload apache2
  echo "🔁 Apache direload."
}

delete_site() {
  echo "=== Hapus Site (Uninstall) ==="
  read -rp "📝 Masukkan domain yang mau dihapus (misal: sneat.khoirulanam.cloud): " server_name
  local conf_file="$SITES_AVAILABLE/${server_name}.conf"
  local ssl_conf_file="$SITES_AVAILABLE/${server_name}-le-ssl.conf"

  if [[ ! -f "$conf_file" && ! -f "$ssl_conf_file" ]]; then
    echo "❌ Tidak ditemukan config untuk $server_name di $SITES_AVAILABLE"
    return
  fi

  echo "⚠ Ini akan:"
  echo "  - a2dissite ${server_name}.conf"
  echo "  - hapus file .conf (dan -le-ssl.conf kalau ada)"
  read -rp "Lanjut hapus site $server_name? (y/n): " ans
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    echo "➡ Batal hapus."
    return
  fi

  a2dissite "${server_name}.conf" >/dev/null 2>&1 || true
  a2dissite "${server_name}-le-ssl.conf" >/dev/null 2>&1 || true

  rm -f "$conf_file"
  rm -f "$ssl_conf_file"
  rm -f "$SITES_ENABLED/${server_name}.conf"
  rm -f "$SITES_ENABLED/${server_name}-le-ssl.conf"

  systemctl reload apache2
  echo "✅ Site $server_name sudah di-uninstall dari Apache."

  read -rp "Sekalian hapus folder DocumentRoot-nya juga? (y/n): " delroot
  if [[ "$delroot" =~ ^[Yy]$ ]]; then
    # cari DocumentRoot terakhir yang dipake
    local doc_root
    doc_root=$(grep -m1 "DocumentRoot" "$conf_file" 2>/dev/null | awk '{print $2}')
    if [[ -n "$doc_root" && -d "$doc_root" ]]; then
      echo "⚠ Hapus folder: $doc_root"
      read -rp "Yakin? (y/n): " really
      if [[ "$really" =~ ^[Yy]$ ]]; then
        rm -rf "$doc_root"
        echo "🗑 Folder $doc_root dihapus."
      else
        echo "➡ Folder tidak dihapus."
      fi
    else
      echo "ℹ Tidak menemukan DocumentRoot atau folder sudah tidak ada."
    fi
  fi
}

main_menu() {
  while true; do
    echo
    echo "==============================="
    echo "   Apache Site Manager (Simple)"
    echo "==============================="
    echo "1) Tambah site baru (domain / subdomain)"
    echo "2) List semua site"
    echo "3) Ubah DocumentRoot site"
    echo "4) Hapus site (uninstall)"
    echo "5) Keluar"
    read -rp "Pilih menu [1-5]: " choice

    case "$choice" in
      1) create_site_interactive ;;
      2) list_sites ;;
      3) change_docroot ;;
      4) delete_site ;;
      5) echo "Bye 👋"; break ;;
      *) echo "❌ Pilihan tidak dikenal." ;;
    esac
  done
}

### MAIN PROGRAM ###

require_root
install_dependencies

# Mode 1: ada argumen → non-interaktif
# Contoh: sudo bash setup-site.sh portofolio.khoirulanam.cloud /var/www/portofolio
if [[ $# -ge 2 ]]; then
  create_site_noninteractive "$1" "$2"
else
  # Mode 2: interaktif dengan menu
  main_menu
fi
