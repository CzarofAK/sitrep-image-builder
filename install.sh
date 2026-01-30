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

# Installiere grundlegende Pakete
info "Installiere grundlegende Pakete..."
apt-get update
apt-get install -y \
    hostapd \
    dnsmasq \
    iptables \
    docker.io \
    docker-compose \
    avahi-daemon \
    git \
    curl \
    jq

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

# Erstelle angepasste docker-compose.yml für offline Betrieb
info "Erstelle Docker Compose Konfiguration..."
cat > "$INSTALL_DIR/docker-compose.override.yml" <<'EOF'
version: '3.8'

services:
  # Dex für lokale Authentifizierung
  dex:
    image: ghcr.io/dexidp/dex:v2.37.0
    command: dex serve /etc/dex/config.yaml
    ports:
      - "5556:5556"
    volumes:
      - /etc/sitrep/dex-config.yaml:/etc/dex/config.yaml:ro
    networks:
      - sitrep
    restart: unless-stopped

  # OAuth2 Proxy
  oauth2-proxy:
    environment:
      - OAUTH2_PROXY_HTTP_ADDRESS=0.0.0.0:4180
      - OAUTH2_PROXY_UPSTREAMS=http://hasura:8080
      - OAUTH2_PROXY_EMAIL_DOMAINS=*
      - OAUTH2_PROXY_SKIP_PROVIDER_BUTTON=true
    ports:
      - "4180:4180"
    depends_on:
      - dex
      - hasura

  # Hasura mit angepassten Einstellungen
  hasura:
    environment:
      - HASURA_GRAPHQL_UNAUTHORIZED_ROLE=anonymous
      - HASURA_GRAPHQL_ENABLE_REMOTE_SCHEMA_PERMISSIONS=true

  # UI angepasst für lokalen Zugriff
  ui:
    environment:
      - REACT_APP_GRAPHQL_ENDPOINT=http://${SITREP_HOST:-192.168.50.1}:8080/v1/graphql
      - REACT_APP_OFFLINE_MODE=true
    ports:
      - "3000:80"

networks:
  sitrep:
    driver: bridge
EOF

# Erstelle Dex Konfiguration für lokale Auth
info "Erstelle Dex Konfiguration..."
cat > "$CONFIG_DIR/dex-config.yaml" <<'EOF'
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
  - 'http://192.168.50.1:3000/oauth2/callback'
  - 'http://sitrep.local:3000/oauth2/callback'
  name: 'SitRep Emergency System'
  secret: sitrep-client-secret

enablePasswordDB: true

staticPasswords:
- email: "admin@sitrep.local"
  hash: "$2a$10$2b2cU8CPhOTaGrs1HRQuAueS7JTT5ZHsHSzYiFPm1leZck7Mc8T4W"  # password: admin
  username: "admin"
  userID: "08a8684b-db88-4b73-90a9-3cd1661f5466"
- email: "user@sitrep.local"
  hash: "$2a$10$2b2cU8CPhOTaGrs1HRQuAueS7JTT5ZHsHSzYiFPm1leZck7Mc8T4W"  # password: admin
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
    for image in ./docker-images/*.tar; do
        if [ -f "$image" ]; then
            info "Lade $(basename $image)..."
            docker load < "$image"
        fi
    done
else
    warn "Keine vorbereiteten Docker Images gefunden. Diese müssen online geladen werden."
fi

# WiFi Hotspot konfigurieren
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
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

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
ExecStartPre=-/usr/bin/docker-compose down
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Erstelle Hotspot Service
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

# Aktiviere Services
info "Aktiviere Services..."
systemctl daemon-reload
systemctl enable sitrep.service
systemctl enable sitrep-hotspot.service
systemctl enable hostapd
systemctl enable dnsmasq
systemctl unmask hostapd

# Avahi für .local Domain
info "Konfiguriere mDNS (Avahi)..."
sed -i 's/#host-name=.*/host-name=sitrep/' /etc/avahi/avahi-daemon.conf
systemctl enable avahi-daemon

# Erstelle Info-Datei
cat > "$INSTALL_DIR/INFO.txt" <<EOF
========================================
SitRep Emergency System
Offline Installation
========================================

WiFi Hotspot:
  SSID:     $HOTSPOT_SSID
  Password: $HOTSPOT_PASSWORD
  IP:       $HOTSPOT_IP

Zugriff:
  Browser:  http://$HOTSPOT_IP:3000
            http://sitrep.local:3000

Standard-Login:
  Benutzer: admin@sitrep.local
  Passwort: admin

Weitere Benutzer:
  user@sitrep.local / admin

WICHTIG: Bitte Passwort nach erstem Login ändern!

Services:
  sudo systemctl status sitrep
  sudo systemctl status sitrep-hotspot
  
Logs:
  sudo journalctl -u sitrep -f
  sudo docker-compose -f $INSTALL_DIR/docker-compose.yml logs -f

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
warn "System wird in 10 Sekunden neu gestartet..."
warn "Nach dem Neustart können Sie sich mit dem WiFi '$HOTSPOT_SSID' verbinden"
sleep 10
reboot
