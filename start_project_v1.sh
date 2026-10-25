#!/bin/bash

# Pastikan skrip dijalankan dari root direktori proyek (q3js / Quake3-Azure)

echo "=== Menyiapkan Environment & Menerapkan Perbaikan ==="

# 1. FIX: Hapus cache kompilasi CMake agar path direktori di-reset
echo "[1/6] Membersihkan cache build game server..."
rm -rf game/build

# 2. FIX: Bersihkan cache Next.js untuk mencegah error Turbopack "stale"
echo "[2/6] Membersihkan cache frontend..."
rm -rf website/.next node_modules website/node_modules

# Instal ulang dependensi secara bersih
echo "[3/6] Menginstal dependensi pnpm..."
pnpm install --frozen-lockfile

# 3. FIX: Pastikan variabel GA ada di .env.local
echo "[4/6] Menyiapkan environment variables..."
if [ ! -f website/.env.local ]; then
    cp website/.env.example website/.env.local 2>/dev/null || touch website/.env.local
fi
if ! grep -q "NEXT_PUBLIC_GA_MEASUREMENT_ID" website/.env.local; then
    echo "NEXT_PUBLIC_GA_MEASUREMENT_ID=G-1234567890" >> website/.env.local
    echo "  -> Menambahkan dummy NEXT_PUBLIC_GA_MEASUREMENT_ID"
fi

# 4. FIX: Jalankan Database dan Static Server menggunakan Docker Compose bawaan
echo "[5/6] Menjalankan kontainer Database dan Static Server..."
docker compose up -d database static

echo "Menunggu database siap (10 detik)..."
sleep 10

echo "[6/6] Memulai layanan Master API, Game Server, dan Frontend Website..."

# Fungsi untuk membersihkan dan mematikan semua proses saat script dihentikan (Ctrl + C)
cleanup() {
    echo ""
    echo "=== Menghentikan Semua Layanan ==="
    echo "Mematikan proses background..."
    kill $MASTER_PID $SERVER_PID $WEB_PID 2>/dev/null
    echo "Menghentikan kontainer Docker..."
    docker compose stop database static
    echo "Selesai."
    exit 0
}

# Tangkap sinyal SIGINT (Ctrl+C) dan panggil fungsi cleanup
trap cleanup SIGINT SIGTERM

# Jalankan Master API di background
echo "-> Menjalankan Master API..."
echo "Menjalankan Master Server API..."
export Q3JS_MASTER_AUTH_ADMIN_PASSWORD="adminpassword123"
export Q3JS_MASTER_VOICE_API_KEY="dummy-key"
export Q3JS_MASTER_VOICE_API_SECRET="dummy-secret"
make master-run &
MASTER_PID=$!

echo "Menunggu Master API agar siap menerima heartbeat (15 detik)..."
sleep 15

# FIX: Jalankan Game Server dengan path absolut menggunakan subshell pwd di background
echo "-> Menjalankan Game Server & WebSocket Gateway..."
Q3JS_BASEPATH="$(pwd)/Q3A" make server-run &
SERVER_PID=$!

# Jalankan Frontend Website di background
echo "-> Menjalankan Website (Next.js)..."
pnpm --dir website dev -H 0.0.0.0 &
WEB_PID=$!

echo ""
echo "========================================================"
echo "SEMUA LAYANAN BERHASIL DIJALANKAN!"
echo "Website bisa diakses di : http://localhost:3000"
echo "Master API              : http://localhost:8080"
echo "Static Server           : http://localhost:8081"
echo "========================================================"
echo "TEKAN Ctrl + C UNTUK MENGHENTIKAN SEMUA LAYANAN"
echo "========================================================"
echo ""

# Perintah wait agar skrip tetap berjalan (menunggu proses background)
wait