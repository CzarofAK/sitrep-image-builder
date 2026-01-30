#!/bin/bash
set -e

# SitRep Hotspot Configuration Tool
# Ermöglicht einfache Änderung des WiFi Hotspots

CONFIG_DIR="/etc/sitrep"
HOTSPOT_CONF="/etc/hostapd/hostapd.conf"

# Farben
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
prompt() { echo -e "${BLUE}[?]${NC} $1"; }

# Check root
if [ "$EUID" -ne 0 ]; then 
    echo "Bitte als root ausführen (sudo ./configure-hotspot.sh)"
    exit 1
fi

echo "=================================="
echo "SitRep Hotspot Konfiguration"
echo "=================================="
echo ""

# Aktuelle Konfiguration anzeigen
if [ -f "$HOTSPOT_CONF" ]; then
    CURRENT_SSID=$(grep "^ssid=" "$HOTSPOT_CONF" | cut -d'=' -f2)
    CURRENT_CHANNEL=$(grep "^channel=" "$HOTSPOT_CONF" | cut -d'=' -f2)
    echo "Aktuelle Konfiguration:"
    echo "  SSID:    $CURRENT_SSID"
    echo "  Kanal:   $CURRENT_CHANNEL"
    echo ""
fi

# Eingabe
read -p "Neuer SSID Name [Standard: SitRep-Emergency]: " NEW_SSID
NEW_SSID=${NEW_SSID:-SitRep-Emergency}

read -sp "Neues Passwort (min. 8 Zeichen): " NEW_PASSWORD
echo ""

# Validierung
if [ ${#NEW_PASSWORD} -lt 8 ]; then
    echo "Passwort muss mindestens 8 Zeichen lang sein!"
    exit 1
fi

read -p "WiFi Kanal [1-13, Standard: 7]: " NEW_CHANNEL
NEW_CHANNEL=${NEW_CHANNEL:-7}

read -p "IP-Adresse des Hotspots [Standard: 192.168.50.1]: " NEW_IP
NEW_IP=${NEW_IP:-192.168.50.1}

echo ""
info "Neue Konfiguration:"
echo "  SSID:    $NEW_SSID"
echo "  Kanal:   $NEW_CHANNEL"
echo "  IP:      $NEW_IP"
echo ""

read -p "Fortfahren? [j/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[JjYy]$ ]]; then
    echo "Abgebrochen."
    exit 0
fi

# Stoppe Services
info "Stoppe Services..."
systemctl stop sitrep-hotspot hostapd dnsmasq 2>/dev/null || true

# Update hostapd
info "Aktualisiere hostapd Konfiguration..."
cat > "$HOTSPOT_CONF" <<EOF
interface=wlan0
driver=nl80211
ssid=$NEW_SSID
hw_mode=g
channel=$NEW_CHANNEL
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$NEW_PASSWORD
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
country_code=CH
ieee80211n=1
ieee80211d=1
EOF

# Update dnsmasq
info "Aktualisiere dnsmasq Konfiguration..."
DHCP_START=$(echo $NEW_IP | cut -d'.' -f1-3).10
DHCP_END=$(echo $NEW_IP | cut -d'.' -f1-3).100

cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
dhcp-range=$DHCP_START,$DHCP_END,255.255.255.0,24h
domain=sitrep.local
address=/sitrep.local/$NEW_IP
address=/#/$NEW_IP
dhcp-option=3,$NEW_IP
dhcp-option=6,$NEW_IP
EOF

# Update network interface
info "Aktualisiere Netzwerk-Interface..."
cat > /etc/network/interfaces.d/wlan0 <<EOF
auto wlan0
iface wlan0 inet static
    address $NEW_IP
    netmask 255.255.255.0
EOF

# Update SitRep Environment
if [ -f "$CONFIG_DIR/sitrep.env" ]; then
    info "Aktualisiere SitRep Konfiguration..."
    sed -i "s|SITREP_HOST=.*|SITREP_HOST=$NEW_IP|" "$CONFIG_DIR/sitrep.env"
    sed -i "s|OAUTH2_PROXY_REDIRECT_URL=.*|OAUTH2_PROXY_REDIRECT_URL=http://$NEW_IP:3000/oauth2/callback|" "$CONFIG_DIR/sitrep.env"
fi

# Update Dex config
if [ -f "$CONFIG_DIR/dex-config.yaml" ]; then
    info "Aktualisiere Dex Konfiguration..."
    sed -i "s|http://[0-9.]*:3000/oauth2/callback|http://$NEW_IP:3000/oauth2/callback|" "$CONFIG_DIR/dex-config.yaml"
fi

# Starte Services neu
info "Starte Services neu..."
systemctl start sitrep-hotspot
systemctl restart sitrep

# Erstelle Info-Datei
cat > /opt/sitrep/HOTSPOT-INFO.txt <<EOF
========================================
SitRep Hotspot Konfiguration
Aktualisiert: $(date)
========================================

WiFi Hotspot:
  SSID:     $NEW_SSID
  Password: $NEW_PASSWORD
  Kanal:    $NEW_CHANNEL
  IP:       $NEW_IP

Zugriff:
  Browser:  http://$NEW_IP:3000
            http://sitrep.local:3000

Login:
  admin@sitrep.local / admin

========================================
EOF

info "Konfiguration abgeschlossen!"
echo ""
cat /opt/sitrep/HOTSPOT-INFO.txt
echo ""
info "Services werden hochgefahren..."
sleep 5
systemctl status sitrep-hotspot --no-pager
