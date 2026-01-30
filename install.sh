#!/bin/bash
set -e

# SitRep Offline Installation Script
# Für Raspberry Pi 4 / Odroid
# Copyright (c) 2026 - Offline Emergency Response System

INSTALL_DIR="/opt/sitrep"
CONFIG_DIR="/etc/sitrep"
HOTSPOT_SSID="${HOTSPOT_SSID:-SitRep-Emergency}"
HOTSPOT_PASSWORD="${HOTSPOT_PASSWORD:-emergency123}"
HOTSPOT_IP="192.168.50.1"

echo "=================================="
echo "SitRep Offline Installation"
echo "=================================="
echo ""

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check root
if [ "$EUID" -ne 0 ]; then 
    error "Bitte als root ausführen (sudo ./install.sh)"
fi

# Detect system
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
    info "Erkanntes System: $PRETTY_NAME"
else
    error "Konnte Betriebssystem nicht erkennen"
fi

# Check architecture
ARCH=$(uname -m)
if [[ "$ARCH" != "aarch64" && "$ARCH" != "armv7l" ]]; then
    warn "Architektur $ARCH - getestet nur auf ARM64/ARM7"
fi

info "Architektur: $ARCH"

# Check x86-64-v2 CPU support (required for newer Hasura images)
check_x86_64_v2() {
    if [[ "$ARCH" == "x86_64" ]]; then
        # x86-64-v2 requires: cx16, lahf_lm, popcnt, sse4_1, sse4_2, ssse3
        local required_flags="cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3"
        local missing_flags=""

        for flag in $required_flags; do
            if ! grep -q " $flag" /proc/cpuinfo 2>/dev/null; then
                missing_flags="$missing_flags $flag"
            fi
        done

        if [ -n "$missing_flags" ]; then
            echo ""
            warn "=============================================="
            warn "CPU unterstützt NICHT x86-64-v2!"
            warn "Fehlende CPU-Features:$missing_flags"
            warn "=============================================="
            echo ""
            warn "Das Hasura graphql-engine Image benötigt x86-64-v2."
            echo ""
            info "LÖSUNG für Proxmox VMs:"
            echo "  1. VM herunterfahren"
            echo "  2. In Proxmox: VM -> Hardware -> Processor"
            echo "  3. CPU-Typ ändern auf 'host' oder 'x86-64-v2'"
            echo "  4. VM neu starten und Installation wiederholen"
            echo ""
            read -p "Trotzdem fortfahren? (j/n): " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Jj]$ ]]; then
                error "Installation abgebrochen. Bitte CPU-Konfiguration anpassen."
            fi
            warn "Fortfahren - Hasura wird möglicherweise nicht starten!"
        else
            info "CPU unterstützt x86-64-v2 ✓"
        fi
    fi
}

check_x86_64_v2

# Installiere grundlegende Pakete (ohne Docker - wird separat geprüft)
info "Installiere grundlegende Pakete..."
apt-get update

# Prüfe ob Docker bereits installiert ist (z.B. docker-ce)
if command -v docker &> /dev/null; then
    info "Docker ist bereits installiert: $(docker --version)"
    # Nur zusätzliche Pakete installieren
    apt-get install -y \
        avahi-daemon \
        git \
        curl \
        jq
else
    # Docker noch nicht installiert - installiere docker.io
    apt-get install -y \
        docker.io \
        docker-compose \
        avahi-daemon \
        git \
        curl \
        jq
fi

# WiFi-Pakete nur installieren wenn wlan0 existiert
if ip link show wlan0 &> /dev/null; then
    info "WiFi-Interface gefunden - installiere Hotspot-Pakete..."
    apt-get install -y hostapd dnsmasq iptables
    SETUP_HOTSPOT=true
else
    warn "Kein WiFi-Interface (wlan0) gefunden - überspringe Hotspot-Setup"
    SETUP_HOTSPOT=false
fi

# Docker aktivieren
info "Aktiviere Docker..."
systemctl enable docker
systemctl start docker

# Erstelle Verzeichnisse
info "Erstelle Verzeichnisse..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p /var/lib/sitrep/postgres
mkdir -p /var/lib/sitrep/hasura
mkdir -p /var/log/sitrep

# Kopiere SitRep Dateien
info "Kopiere SitRep Dateien..."
if [ -d "./sitrep" ]; then
    cp -r ./sitrep/* "$INSTALL_DIR/"
else
    error "SitRep Verzeichnis nicht gefunden. Bitte Repository einbinden."
fi

# Generiere Secrets
info "Generiere Secrets..."
OAUTH2_CLIENT_SECRET=$(openssl rand -base64 32 | tr -- '+/' '-_')
OAUTH2_COOKIE_SECRET=$(openssl rand -base64 32 | tr -- '+/' '-_')
HASURA_ADMIN_SECRET=$(openssl rand -base64 32 | tr -- '+/' '-_')
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -- '+/' '-_')

# Erstelle .env Datei
info "Erstelle Konfiguration..."
cat > "$CONFIG_DIR/sitrep.env" <<EOF
# SitRep Environment Configuration
# Generiert: $(date)

# OAuth2 Proxy (Lokale Auth mit Dex)
OAUTH2_PROXY_CLIENT_ID=sitrep-local
OAUTH2_PROXY_CLIENT_SECRET=$OAUTH2_CLIENT_SECRET
OAUTH2_PROXY_COOKIE_SECRET=$OAUTH2_COOKIE_SECRET
OAUTH2_PROXY_REDIRECT_URL=http://${HOTSPOT_IP}:3000/oauth2/callback
OAUTH2_PROXY_PROVIDER=oidc
OAUTH2_PROXY_OIDC_ISSUER_URL=http://dex:5556/dex

# Hasura
HASURA_GRAPHQL_ADMIN_SECRET=$HASURA_ADMIN_SECRET
HASURA_GRAPHQL_ENABLE_CONSOLE=true
HASURA_GRAPHQL_DEV_MODE=false
HASURA_GRAPHQL_ENABLED_LOG_TYPES=startup,http-log,webhook-log,websocket-log
HASURA_GRAPHQL_DATABASE_URL=postgres://sitrep:${POSTGRES_PASSWORD}@postgres:5432/sitrep

# PostgreSQL
POSTGRES_DB=sitrep
POSTGRES_USER=sitrep
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# Redis
REDIS_URL=redis://redis:6379

# Flipt (Feature Flags)
FLIPT_STORAGE_TYPE=local

# Network
SITREP_HOST=${HOTSPOT_IP}
SITREP_PORT=3000
EOF

chmod 600 "$CONFIG_DIR/sitrep.env"

# Erstelle .env Symlink im Install-Verzeichnis (für docker-compose)
ln -sf "$CONFIG_DIR/sitrep.env" "$INSTALL_DIR/.env"

# Erstelle vollständige docker-compose.yml für offline Betrieb
# (ersetzt die minimale Version aus dem Repository)
info "Erstelle Docker Compose Konfiguration..."

# Entferne eventuell vorhandene override.yml (verursacht Fehler)
rm -f "$INSTALL_DIR/docker-compose.override.yml"

# Hole aktuelle IP-Adresse
CURRENT_IP=$(hostname -I | awk '{print $1}')

cat > "$INSTALL_DIR/docker-compose.yml" <<EOF
name: sitrep

services:
  # SitRep Frontend + Backend (vollständiges Image)
  sitrep:
    image: ghcr.io/f-eld-ch/sitrep:latest
    ports:
      - "3000:8080"
    environment:
      - GRAPHQL_ENDPOINT=http://graphql-engine:8080/v1/graphql
      - OIDC_ISSUER_URL=http://dex:5556/dex
      - PUBLIC_URL=http://${CURRENT_IP}:3000
    depends_on:
      graphql-engine:
        condition: service_healthy
      dex:
        condition: service_started
    networks:
      - sitrep
    restart: unless-stopped

  # Hasura GraphQL Engine
  graphql-engine:
    image: sitrep-graphql-engine:latest
    ports:
      - "8080:8080"
    environment:
      HASURA_GRAPHQL_DATABASE_URL: postgres://postgres:\${POSTGRES_PASSWORD}@postgres:5432/postgres
      HASURA_GRAPHQL_METADATA_DATABASE_URL: postgres://postgres:\${POSTGRES_PASSWORD}@postgres:5432/postgres
      PG_DATABASE_URL: postgres://postgres:\${POSTGRES_PASSWORD}@postgres:5432/postgres
      HASURA_GRAPHQL_ADMIN_SECRET: \${HASURA_GRAPHQL_ADMIN_SECRET}
      HASURA_GRAPHQL_ENABLE_CONSOLE: "true"
      HASURA_GRAPHQL_DEV_MODE: "false"
      HASURA_GRAPHQL_ENABLED_LOG_TYPES: startup, http-log, webhook-log, websocket-log
      HASURA_GRAPHQL_UNAUTHORIZED_ROLE: anonymous
      HASURA_GRAPHQL_JWT_SECRET: '{"jwk_url": "http://dex:5556/dex/keys", "header":{"type":"Authorization"}, "claims_map":{"x-hasura-user-id":{"path":"\$.sub"},"x-hasura-email":{"path":"\$.email"},"x-hasura-allowed-roles":["viewer","editor"],"x-hasura-default-role":"editor"}}'
    depends_on:
      postgres:
        condition: service_healthy
      dex:
        condition: service_started
    networks:
      - sitrep
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:8080/healthz"]
      interval: 10s
      timeout: 5s
      retries: 5

  # PostgreSQL Datenbank
  postgres:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    networks:
      - sitrep
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  # Dex Identity Provider
  dex:
    image: dexidp/dex:latest
    command: dex serve /etc/dex/config.yaml
    ports:
      - "5556:5556"
      - "5557:5557"
    volumes:
      - /etc/sitrep/dex-config.yaml:/etc/dex/config.yaml:ro
      - dex_data:/var/dex
    networks:
      - sitrep
    restart: unless-stopped

networks:
  sitrep:
    driver: bridge

volumes:
  postgres_data:
  dex_data:
EOF

# Hole aktuelle IP-Adresse für Dex Konfiguration
CURRENT_IP=$(hostname -I | awk '{print $1}')

# Erstelle Dex Konfiguration für lokale Auth
info "Erstelle Dex Konfiguration..."
cat > "$CONFIG_DIR/dex-config.yaml" <<EOF
issuer: http://dex:5556/dex

storage:
  type: sqlite3
  config:
    file: /var/dex/dex.db

web:
  http: 0.0.0.0:5556

staticClients:
- id: sitrep-local
  redirectURIs:
  - 'http://${CURRENT_IP}:3000/oauth2/callback'
  - 'http://sitrep.local:3000/oauth2/callback'
  - 'http://192.168.50.1:3000/oauth2/callback'
  - 'http://localhost:3000/oauth2/callback'
  name: 'SitRep Emergency System'
  secret: sitrep-client-secret

enablePasswordDB: true

staticPasswords:
- email: "admin@sitrep.local"
  hash: "\$2a\$10\$2b2cU8CPhOTaGrs1HRQuAueS7JTT5ZHsHSzYiFPm1leZck7Mc8T4W"  # password: admin
  username: "admin"
  userID: "08a8684b-db88-4b73-90a9-3cd1661f5466"
- email: "user@sitrep.local"
  hash: "\$2a\$10\$2b2cU8CPhOTaGrs1HRQuAueS7JTT5ZHsHSzYiFPm1leZck7Mc8T4W"  # password: admin
  username: "user"
  userID: "08a8684b-db88-4b73-90a9-3cd1661f5467"

expiry:
  signingKeys: "6h"
  idTokens: "24h"

logger:
  level: "info"
  format: "text"
EOF

# Lade Docker Images (falls vorhanden)
if [ -d "./docker-images" ]; then
    info "Lade vorbereitete Docker Images..."
    # Unterstütze sowohl .tar als auch .tar.gz Dateien
    for image in ./docker-images/*.tar.gz ./docker-images/*.tar; do
        if [ -f "$image" ]; then
            # Überspringe kleine/leere Dateien
            filesize=$(stat -c%s "$image" 2>/dev/null || echo "0")
            if [ "$filesize" -gt 1000 ]; then
                info "Lade $(basename $image)..."
                if [[ "$image" == *.tar.gz ]]; then
                    gunzip -c "$image" | docker load
                else
                    docker load < "$image"
                fi
            fi
        fi
    done 2>/dev/null || true
else
    warn "Keine vorbereiteten Docker Images gefunden. Diese müssen online geladen werden."
fi

# WiFi Hotspot konfigurieren (nur wenn SETUP_HOTSPOT=true)
if [ "$SETUP_HOTSPOT" = "true" ]; then
    info "Konfiguriere WiFi Hotspot..."

    # Stoppe services
    systemctl stop hostapd dnsmasq 2>/dev/null || true

    # Konfiguriere hostapd
    cat > /etc/hostapd/hostapd.conf <<EOF
interface=wlan0
driver=nl80211
ssid=$HOTSPOT_SSID
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$HOTSPOT_PASSWORD
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

    # Aktiviere hostapd
    sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

    # Konfiguriere dnsmasq
    cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
dhcp-range=192.168.50.10,192.168.50.100,255.255.255.0,24h
domain=sitrep.local
address=/sitrep.local/$HOTSPOT_IP
address=/#/$HOTSPOT_IP
# Captive Portal
EOF

    # Konfiguriere statische IP für wlan0
    cat > /etc/network/interfaces.d/wlan0 <<EOF
auto wlan0
iface wlan0 inet static
    address $HOTSPOT_IP
    netmask 255.255.255.0
EOF

    # IP Forwarding aktivieren
    grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p
else
    info "Überspringe WiFi Hotspot Konfiguration (kein wlan0)"
fi

# Bestimme Docker Compose Befehl
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="/usr/bin/docker-compose"
elif docker compose version &> /dev/null 2>&1; then
    COMPOSE_CMD="/usr/bin/docker compose"
else
    COMPOSE_CMD="/usr/bin/docker-compose"
fi

# Erstelle systemd Service
info "Erstelle Systemd Service..."
cat > /etc/systemd/system/sitrep.service <<EOF
[Unit]
Description=SitRep Emergency Management System
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$CONFIG_DIR/sitrep.env
ExecStartPre=-$COMPOSE_CMD --env-file $CONFIG_DIR/sitrep.env down
ExecStart=$COMPOSE_CMD --env-file $CONFIG_DIR/sitrep.env up -d
ExecStop=$COMPOSE_CMD --env-file $CONFIG_DIR/sitrep.env down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Erstelle Hotspot Service nur wenn WiFi vorhanden
if [ "$SETUP_HOTSPOT" = "true" ]; then
    cat > /etc/systemd/system/sitrep-hotspot.service <<EOF
[Unit]
Description=SitRep WiFi Hotspot
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/sbin/ip link set wlan0 down
ExecStartPre=/sbin/ip addr flush dev wlan0
ExecStartPre=/sbin/ip addr add $HOTSPOT_IP/24 dev wlan0
ExecStartPre=/sbin/ip link set wlan0 up
ExecStart=/usr/bin/systemctl start hostapd dnsmasq
ExecStop=/usr/bin/systemctl stop hostapd dnsmasq

[Install]
WantedBy=multi-user.target
EOF
fi

# Aktiviere Services
info "Aktiviere Services..."
systemctl daemon-reload
systemctl enable sitrep.service

if [ "$SETUP_HOTSPOT" = "true" ]; then
    systemctl enable sitrep-hotspot.service
    systemctl enable hostapd
    systemctl enable dnsmasq
    systemctl unmask hostapd
fi

# Avahi für .local Domain
info "Konfiguriere mDNS (Avahi)..."
sed -i 's/#host-name=.*/host-name=sitrep/' /etc/avahi/avahi-daemon.conf
systemctl enable avahi-daemon

# Hole aktuelle IP-Adresse für INFO
CURRENT_IP=$(hostname -I | awk '{print $1}')

# Erstelle Info-Datei
cat > "$INSTALL_DIR/INFO.txt" <<EOF
========================================
SitRep Emergency System
Offline Installation
========================================
EOF

if [ "$SETUP_HOTSPOT" = "true" ]; then
cat >> "$INSTALL_DIR/INFO.txt" <<EOF

WiFi Hotspot:
  SSID:     $HOTSPOT_SSID
  Password: $HOTSPOT_PASSWORD
  IP:       $HOTSPOT_IP
EOF
fi

cat >> "$INSTALL_DIR/INFO.txt" <<EOF

Zugriff:
  Browser:  http://${CURRENT_IP}:3000
            http://sitrep.local:3000
EOF

if [ "$SETUP_HOTSPOT" = "true" ]; then
cat >> "$INSTALL_DIR/INFO.txt" <<EOF
            http://$HOTSPOT_IP:3000
EOF
fi

cat >> "$INSTALL_DIR/INFO.txt" <<EOF

Standard-Login:
  Benutzer: admin@sitrep.local
  Passwort: admin

Weitere Benutzer:
  user@sitrep.local / admin

WICHTIG: Bitte Passwort nach erstem Login ändern!

Services:
  sudo systemctl status sitrep
  sudo systemctl start sitrep
  sudo systemctl stop sitrep

Logs:
  sudo journalctl -u sitrep -f
  cd $INSTALL_DIR && docker compose logs -f

Konfiguration:
  $CONFIG_DIR/sitrep.env
  $CONFIG_DIR/dex-config.yaml

Secrets gespeichert in: $CONFIG_DIR/sitrep.env

========================================
Installation abgeschlossen: $(date)
========================================
EOF

info "Installation abgeschlossen!"
echo ""
cat "$INSTALL_DIR/INFO.txt"
echo ""

if [ "$SETUP_HOTSPOT" = "true" ]; then
    warn "System wird in 10 Sekunden neu gestartet..."
    warn "Nach dem Neustart können Sie sich mit dem WiFi '$HOTSPOT_SSID' verbinden"
    sleep 10
    reboot
else
    info "Starte SitRep Services..."
    systemctl start sitrep
    echo ""
    info "SitRep ist jetzt erreichbar unter: http://${CURRENT_IP}:3000"
    info "Oder: http://sitrep.local:3000"
fi
