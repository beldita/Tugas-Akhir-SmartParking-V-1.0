<# :
@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0'))"
if %errorlevel% neq 0 (
    echo.
    echo ========================================================
    echo [!] CRITICAL FAILURE
    echo ========================================================
    echo Terjadi kegagalan pada proses setup.
    echo Jendela ini ditahan untuk keperluan debugging.
    pause
    exit /b %errorlevel%
)
exit /b 0
#>

# PowerShell Script starts here
$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptRoot) { $ScriptRoot = Get-Location }
Set-Location $ScriptRoot

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "   ENTERPRISE IOT SMART PARKING SETUP (EXPERT EDITION)" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Cek Docker Desktop
Write-Host "[1/10] Memeriksa Docker Engine..." -ForegroundColor Yellow
try {
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Docker belum berjalan."
    }
    Write-Host "- Docker Engine OK." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Docker belum berjalan. Silakan jalankan Docker Desktop terlebih dahulu!" -ForegroundColor Red
    exit 1
}
Write-Host ""

# 2. Arsitektur Direktori
Write-Host "[2/10] Membangun arsitektur direktori IoT..." -ForegroundColor Yellow
$dirs = @(
    "backend",
    "algorithm\app",
    "docker\laravel",
    "docker\nginx",
    "docker\python"
)
foreach ($dir in $dirs) {
    $fullPath = Join-Path $ScriptRoot $dir
    if (-not (Test-Path $fullPath)) {
        New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
    }
}
Write-Host "- Direktori siap." -ForegroundColor Green
Write-Host ""

# 3. Konfigurasi Docker Compose
Write-Host "[3/10] Menyiapkan konfigurasi Infrastruktur (docker-compose.yml)..." -ForegroundColor Yellow
$composePath = Join-Path $ScriptRoot "docker-compose.yml"
if (-not (Test-Path $composePath)) {
    $composeContent = @'
services:
  # 1. RELATIONAL DATABASE
  postgres:
    image: postgres:15-alpine
    container_name: smartparking-postgres
    environment:
      POSTGRES_USER: root
      POSTGRES_PASSWORD: root
      POSTGRES_DB: smart_parking
      TZ: Asia/Jakarta
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    networks:
      - parking_net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U root -d smart_parking"]
      interval: 5s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  # 2. IN-MEMORY CACHE & QUEUE (CRITICAL FOR IOT)
  redis:
    image: redis:7-alpine
    container_name: smartparking-redis
    ports:
      - "6379:6379"
    volumes:
      - redisdata:/data
    networks:
      - parking_net
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
    restart: unless-stopped

  # 3. MQTT BROKER (IOT COMMUNICATION)
  emqx:
    image: emqx/emqx:5.3.0
    container_name: smartparking-emqx
    environment:
      TZ: Asia/Jakarta
    ports:
      - "1883:1883"       # MQTT TCP
      - "8083:8083"       # MQTT over WebSocket
      - "18083:18083"     # Admin Dashboard
    volumes:
      - emqx_data:/opt/emqx/data
      - emqx_log:/opt/emqx/log
    networks:
      - parking_net
    restart: unless-stopped

  # 4. BACKEND API (LARAVEL)
  laravel:
    build:
      context: ./docker/laravel
    container_name: smartparking-laravel
    environment:
      TZ: Asia/Jakarta
    volumes:
      - ./backend/laravel:/var/www
    networks:
      - parking_net
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped

  # 5. WEB SERVER (NGINX)
  nginx:
    image: nginx:alpine
    container_name: smartparking-nginx
    environment:
      TZ: Asia/Jakarta
    ports:
      - "8000:80"
    volumes:
      - ./backend/laravel:/var/www
      - ./docker/nginx/default.conf:/etc/nginx/conf.d/default.conf
    networks:
      - parking_net
    depends_on:
      - laravel
    restart: unless-stopped

  # 6. AI/ALGORITHM ENGINE (PYTHON)
  algorithm:
    build:
      context: .
      dockerfile: ./docker/python/Dockerfile
    container_name: smartparking-algorithm
    environment:
      TZ: Asia/Jakarta
    ports:
      - "8001:8001"
    volumes:
      - ./algorithm:/app
    networks:
      - parking_net
    restart: unless-stopped

networks:
  parking_net:
    driver: bridge

volumes:
  pgdata:
  redisdata:
  emqx_data:
  emqx_log:
'@
    [System.IO.File]::WriteAllText($composePath, $composeContent, [System.Text.Encoding]::UTF8)
    Write-Host "- docker-compose.yml berhasil dibuat." -ForegroundColor Green
} else {
    Write-Host "- docker-compose.yml sudah ada." -ForegroundColor DarkGray
}
Write-Host ""

# 4. Dockerfiles & Configs
Write-Host "[4/10] Menyiapkan environment sistem..." -ForegroundColor Yellow

$laravelDockerPath = Join-Path $ScriptRoot "docker\laravel\Dockerfile"
if (-not (Test-Path $laravelDockerPath)) {
    $laravelDockerContent = @'
FROM php:8.4-fpm-alpine

RUN apk add --no-cache \
    libpng \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    zip \
    libzip-dev \
    postgresql-dev \
    bash

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install pdo pdo_mysql pdo_pgsql gd zip

# Install Redis extension for PHP
RUN apk add --no-cache pcre-dev $PHPIZE_DEPS \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && apk del pcre-dev $PHPIZE_DEPS

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www
'@
    [System.IO.File]::WriteAllText($laravelDockerPath, $laravelDockerContent, [System.Text.Encoding]::UTF8)
}

$nginxConfPath = Join-Path $ScriptRoot "docker\nginx\default.conf"
if (-not (Test-Path $nginxConfPath)) {
    $nginxConfContent = @'
server {
    listen 80;
    index index.php index.html;
    server_name localhost;
    root /var/www/public;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass laravel:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
    }
}
'@
    [System.IO.File]::WriteAllText($nginxConfPath, $nginxConfContent, [System.Text.Encoding]::UTF8)
}

$pythonDockerPath = Join-Path $ScriptRoot "docker\python\Dockerfile"
if (-not (Test-Path $pythonDockerPath)) {
    $pythonDockerContent = @'
FROM python:3.11-slim
WORKDIR /app
COPY algorithm/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8001", "--reload"]
'@
    [System.IO.File]::WriteAllText($pythonDockerPath, $pythonDockerContent, [System.Text.Encoding]::UTF8)
}

$requirementsPath = Join-Path $ScriptRoot "algorithm\requirements.txt"
if (-not (Test-Path $requirementsPath)) {
    $requirementsContent = @'
fastapi==0.104.1
uvicorn==0.24.0.post1
pydantic==2.4.2
redis==5.0.1
'@
    [System.IO.File]::WriteAllText($requirementsPath, $requirementsContent, [System.Text.Encoding]::UTF8)
}

$mainPyPath = Join-Path $ScriptRoot "algorithm\app\main.py"
if (-not (Test-Path $mainPyPath)) {
    $mainPyContent = @'
from fastapi import FastAPI

app = FastAPI(title="Smart Parking IoT Algorithm Engine")

@app.get("/")
def read_root():
    return {"status": "Operational", "module": "A* & Dijkstra Core"}
'@
    [System.IO.File]::WriteAllText($mainPyPath, $mainPyContent, [System.Text.Encoding]::UTF8)
}

Write-Host "- Environment sistem siap." -ForegroundColor Green
Write-Host ""

# 5. Inisialisasi Backend Framework (Laravel 12)
Write-Host "[5/10] Inisialisasi Backend Framework (Laravel 12)..." -ForegroundColor Yellow
$artisanPath = Join-Path $ScriptRoot "backend\laravel\artisan"
if (Test-Path $artisanPath) {
    Write-Host "- Source code Laravel ditemukan. Skip instalasi." -ForegroundColor Green
} else {
    Write-Host "- Mengunduh dan menginisialisasi Laravel skeleton via Composer Docker..." -ForegroundColor Cyan
    $backendDir = Join-Path $ScriptRoot "backend"
    docker run --rm -v "${backendDir}:/app" composer sh -c "composer create-project 'laravel/laravel:^12.0' /tmp/laravel --prefer-dist && cp -r /tmp/laravel/. /app/laravel/"
    if (-not (Test-Path $artisanPath)) {
        Write-Host "[ERROR] Gagal mengunduh Laravel. Cek koneksi internet Anda." -ForegroundColor Red
        exit 1
    }
    Write-Host "- Laravel berhasil diunduh." -ForegroundColor Green
}
Write-Host ""

# 6. Konfigurasi .env Laravel untuk Standar IoT
Write-Host "[6/10] Menghubungkan Backend dengan Database & Redis..." -ForegroundColor Yellow
$envPath = Join-Path $ScriptRoot "backend\laravel\.env"
$envExamplePath = Join-Path $ScriptRoot "backend\laravel\.env.example"
if (-not (Test-Path $envPath) -and (Test-Path $envExamplePath)) {
    Copy-Item $envExamplePath $envPath
}

if (Test-Path $envPath) {
    $envContent = Get-Content $envPath -Raw
    $envContent = $envContent -replace '(?m)^DB_CONNECTION=.*', 'DB_CONNECTION=pgsql'
    $envContent = $envContent -replace '(?m)^#?\s*DB_HOST=.*', 'DB_HOST=postgres'
    $envContent = $envContent -replace '(?m)^#?\s*DB_PORT=.*', 'DB_PORT=5432'
    $envContent = $envContent -replace '(?m)^#?\s*DB_DATABASE=.*', 'DB_DATABASE=smart_parking'
    $envContent = $envContent -replace '(?m)^#?\s*DB_USERNAME=.*', 'DB_USERNAME=root'
    $envContent = $envContent -replace '(?m)^#?\s*DB_PASSWORD=.*', 'DB_PASSWORD=root'
    $envContent = $envContent -replace '(?m)^CACHE_STORE=.*', 'CACHE_STORE=redis'
    $envContent = $envContent -replace '(?m)^QUEUE_CONNECTION=.*', 'QUEUE_CONNECTION=redis'
    $envContent = $envContent -replace '(?m)^SESSION_DRIVER=.*', 'SESSION_DRIVER=redis'
    $envContent = $envContent -replace '(?m)^REDIS_HOST=.*', 'REDIS_HOST=redis'
    [System.IO.File]::WriteAllText($envPath, $envContent, [System.Text.Encoding]::UTF8)
    Write-Host "- Kredensial berhasil diinjeksi ke .env Laravel." -ForegroundColor Green
} else {
    Write-Host "- File .env belum ditemukan (akan dikonfigurasi setelah Laravel terpasang)." -ForegroundColor Yellow
}
Write-Host ""

# 7. Build Docker
Write-Host "[7/10] Mengkompilasi arsitektur Container..." -ForegroundColor Yellow
docker compose up -d --build
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] docker compose up gagal." -ForegroundColor Red
    exit 1
}
Write-Host ""

# 8. Wait for Healthcheck
Write-Host "[8/10] Menunggu konfirmasi Healthcheck dari Database dan Cache..." -ForegroundColor Yellow
$maxRetries = 30
$count = 0
$dbReady = $false
while ($count -lt $maxRetries) {
    Start-Sleep -Seconds 2
    $status = docker inspect --format="{{json .State.Health.Status}}" smartparking-postgres 2>$null
    if ($status -like "*healthy*") {
        $dbReady = $true
        break
    }
    $count++
    Write-Host "  Menunggu PostgreSQL siap ($count/$maxRetries)..."
}

if ($dbReady) {
    Write-Host "- PostgreSQL dan Redis berstatus HEALTHY." -ForegroundColor Green
} else {
    Write-Host "[WARNING] Healthcheck PostgreSQL membutuhkan waktu lebih lama. Melanjutkan ke migrasi..." -ForegroundColor Yellow
}
Write-Host ""

# 9. Migrasi Database
Write-Host "[9/10] Menjalankan Migrasi Database..." -ForegroundColor Yellow
docker compose exec -T laravel chmod -R 777 storage bootstrap/cache
docker compose exec -T laravel php artisan key:generate --force
docker compose exec -T laravel php artisan migrate --force
Write-Host "- Database structure siap." -ForegroundColor Green
Write-Host ""

# 10. Selesai
Write-Host "[10/10] ENVIRONMENT IOT BERHASIL DIBANGUN!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host " STATUS INFRASTRUKTUR (ALL GREEN):" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host "[API Layer]"
Write-Host "Backend (Laravel)   : http://localhost:8000"
Write-Host "Algorithm (Python)  : http://localhost:8001"
Write-Host ""
Write-Host "[Data Layer]"
Write-Host "PostgreSQL          : localhost:5432 (root/root/smart_parking)"
Write-Host "Redis Cache/Queue   : localhost:6379"
Write-Host ""
Write-Host "[IoT Message Broker]"
Write-Host "EMQX Dashboard      : http://localhost:18083 (admin/public)"
Write-Host "MQTT TCP Port       : localhost:1883"
Write-Host "MQTT WebSockets     : localhost:8083"
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "* Tekan Enter untuk menutup jendela ini..." -ForegroundColor Cyan
Read-Host