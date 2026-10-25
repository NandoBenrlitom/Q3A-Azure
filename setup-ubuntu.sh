#!/usr/bin/env bash
# ==============================================================================
# Script Setup Pertama Kali untuk Quake3-Azure (Q3JS)
# Target Platform: Ubuntu 24.04 LTS (Azure VM / Server)
# ==============================================================================

set -Eeuo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

echo -e "${CYAN}===================================================================${NC}"
echo -e "${CYAN}  Inisialisasi & Setup Lingkungan Ubuntu 24.04 (Azure VM)         ${NC}"
echo -e "${CYAN}  Project: Quake3-Azure (Q3JS)                                    ${NC}"
echo -e "${CYAN}===================================================================${NC}"

# ------------------------------------------------------------------------------
# 1. Validasi OS Ubuntu 24.04
# ------------------------------------------------------------------------------
log_info "Memeriksa versi sistem operasi..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    log_info "OS Terdeteksi: $NAME $VERSION"
    if [[ "$ID" != "ubuntu" && "${ID_LIKE:-}" != *"ubuntu"* && "${ID_LIKE:-}" != *"debian"* ]]; then
        log_warn "Sistem bukan Ubuntu/Debian murni. Melanjutkan, pastikan paket kompatibel."
    fi
else
    log_warn "Tidak dapat mendeteksi /etc/os-release."
fi

# ------------------------------------------------------------------------------
# 2. Instalasi Dependensi Sistem & Build Toolchain
# ------------------------------------------------------------------------------
log_info "Memperbarui repositori paket apt..."
sudo apt-get update -y

log_info "Memasang paket prasyarat esensial (compiler, toolchain, curl, zip, jdk-17)..."
sudo apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    build-essential \
    cmake \
    ninja-build \
    zip \
    unzip \
    git \
    libcurl4 \
    libcurl4-openssl-dev \
    openjdk-17-jdk-headless

# ------------------------------------------------------------------------------
# 3. Instalasi Node.js (NodeSource v24 LTS / current) & pnpm
# ------------------------------------------------------------------------------
log_info "Memeriksa Node.js..."
NEED_NODE_INSTALL=true
if command -v node >/dev/null 2>&1; then
    NODE_MAJOR=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_MAJOR" -ge 20 ]; then
        log_success "Node.js sudah terpasang: $(node -v)"
        NEED_NODE_INSTALL=false
    fi
fi

if [ "$NEED_NODE_INSTALL" = true ]; then
    log_info "Mengunduh dan memasang Node.js 24.x LTS..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
    sudo apt-get update -y
    sudo apt-get install -y nodejs
    log_success "Node.js berhasil dipasang: $(node -v)"
fi

log_info "Memasang dan memperbarui pnpm ke versi 11.2.2..."
sudo npm install -g pnpm@11.2.2
log_success "pnpm terpasang: $(pnpm -v)"

# ------------------------------------------------------------------------------
# 4. Instalasi Docker & Docker Compose Plugin
# ------------------------------------------------------------------------------
log_info "Memeriksa instalasi Docker..."
if ! command -v docker >/dev/null 2>&1; then
    log_info "Memasang Docker CE & Docker Compose plugin via official Docker repository..."
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    UBUNTU_CODENAME="${UBUNTU_CODENAME:-noble}"
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $UBUNTU_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker
    log_success "Docker berhasil dipasang: $(docker --version)"
else
    log_success "Docker sudah terpasang: $(docker --version)"
fi

CURRENT_USER=$(id -un)
if ! groups "$CURRENT_USER" | grep -q '\bdocker\b'; then
    log_info "Menambahkan user '$CURRENT_USER' ke grup 'docker'..."
    sudo usermod -aG docker "$CURRENT_USER"
    log_warn "User ditambahkan ke grup docker. Jika perintah docker tanpa sudo gagal, silakan relogin atau jalankan 'newgrp docker'."
fi

# ------------------------------------------------------------------------------
# 5. Instalasi Dependensi Node.js Proyek via pnpm
# ------------------------------------------------------------------------------
log_info "Memasang dependensi JavaScript pnpm workspace..."
pnpm install --frozen-lockfile

# ------------------------------------------------------------------------------
# 6. Menyiapkan Konfigurasi Environment (.env.local)
# ------------------------------------------------------------------------------
if [ ! -f "$PROJECT_ROOT/website/.env.local" ]; then
    log_info "Membuat file konfigurasi website/.env.local dari template .env.example..."
    cp "$PROJECT_ROOT/website/.env.example" "$PROJECT_ROOT/website/.env.local"
    log_success "File website/.env.local telah dibuat."
else
    log_info "File website/.env.local sudah tersedia."
fi

# ------------------------------------------------------------------------------
# 7. Membangun Binary Game Server Native (ioq3ded & WebSocket Gateway)
# ------------------------------------------------------------------------------
log_info "Melakukan build game server ioq3ded & gateway package..."
./game/server/build.sh
log_success "Game server ioquake3 native dan gateway berhasil di-build ke game/server/dist/"

# ------------------------------------------------------------------------------
# 8. Verifikasi Quake3 Base Data (quake3-data)
# ------------------------------------------------------------------------------
if [ -d "$PROJECT_ROOT/quake3-data/baseq3" ]; then
    PAK0_PATH="$PROJECT_ROOT/quake3-data/baseq3/pak0.pk3"
    if [ -f "$PAK0_PATH" ]; then
        log_success "Aset game ditemukan di quake3-data/baseq3/pak0.pk3"
    else
        log_warn "Direktori quake3-data/baseq3 ada namun 'pak0.pk3' tidak ditemukan. Harap unggah aset game Quake 3 Arena Anda."
    fi
else
    log_warn "Direktori quake3-data/baseq3 belum ada. Buat folder dan salin file .pk3 Quake 3 Arena ke dalamnya."
fi

# ------------------------------------------------------------------------------
# Selesai
# ------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}===================================================================${NC}"
echo -e "${GREEN}  Setup Pertama Kali Selesai dengan Sukses!                        ${NC}"
echo -e "${GREEN}===================================================================${NC}"
echo -e "Langkah berikutnya untuk menjalankan layanan di VM Azure:"
echo -e "💡 ${BOLD}Jalankan SEMUA layanan sekaligus dengan 1 perintah:${NC}"
echo -e "   ${CYAN}./run.sh${NC}  (atau: ${CYAN}make run${NC} / ${CYAN}./start.sh${NC})"
echo ""
echo -e "Atau dengan IP Publik Azure VM Anda:"
echo -e "   ${CYAN}./run.sh --ip <IP_PUBLIK_AZURE>${NC}"
echo ""
echo -e "Perintah manajemen lainnya:"
echo -e "   Status Layanan:   ${CYAN}./run.sh status${NC}"
echo -e "   Hentikan Semua:   ${CYAN}./run.sh stop${NC}"
echo -e "   Lihat Live Log:   ${CYAN}./run.sh logs${NC}"
echo -e "   Mode Background:  ${CYAN}./run.sh start${NC}"
echo ""
echo -e "Pastikan port Azure NSG dibuka: 3000, 8080, 8081, 27961 (TCP), 27960 (UDP)."
echo ""
