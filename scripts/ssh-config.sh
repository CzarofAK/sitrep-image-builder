#!/bin/bash
set -e

# SitRep SSH Management Tool
# Aktiviere/Deaktiviere SSH sicher

# Farben
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check root
if [ "$EUID" -ne 0 ]; then 
    error "Bitte als root ausführen (sudo ./ssh-config.sh)"
fi

usage() {
    cat <<EOF
SitRep SSH Management Tool

Verwendung:
  $(basename $0) enable       - Aktiviere SSH (mit Sicherheitseinstellungen)
  $(basename $0) disable      - Deaktiviere SSH
  $(basename $0) status       - Zeige SSH Status
  $(basename $0) configure    - Konfiguriere SSH-Einstellungen
  $(basename $0) add-key      - Füge SSH-Key hinzu

Beispiele:
  $(basename $0) enable       # Aktiviert SSH mit sicherer Konfiguration
  $(basename $0) add-key      # Fügt SSH Public Key hinzu
EOF
    exit 1
}

enable_ssh() {
    info "Aktiviere SSH mit Sicherheitseinstellungen..."
    
    # Erstelle sichere SSH-Konfiguration
    cat > /etc/ssh/sshd_config.d/sitrep-secure.conf <<'SSHCONFIG'
# SitRep Secure SSH Configuration

# Nur Key-basierte Authentifizierung
PasswordAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes

# Nur SSH Protocol 2
Protocol 2

# Keine Root-Anmeldung mit Passwort
PermitRootLogin prohibit-password

# Keine leeren Passwörter
PermitEmptyPasswords no

# Port (Standard: 22)
Port 22

# Timeout-Einstellungen
ClientAliveInterval 300
ClientAliveCountMax 2

# Login versuche
MaxAuthTries 3
MaxSessions 5

# Keine X11 Forwarding
X11Forwarding no

# Keine TCP Forwarding (kann bei Bedarf aktiviert werden)
AllowTcpForwarding no

# Banner
Banner /etc/ssh/ssh-banner.txt
SSHCONFIG
    
    # Erstelle Banner
    cat > /etc/ssh/ssh-banner.txt <<'BANNER'
================================================
     SitRep Emergency Management System
================================================
UNAUTHORIZED ACCESS IS PROHIBITED

This system is for authorized use only.
All activities are logged and monitored.
================================================
BANNER
    
    # Erstelle .ssh Verzeichnis für pi user
    if [ ! -d /home/pi/.ssh ]; then
        mkdir -p /home/pi/.ssh
        chmod 700 /home/pi/.ssh
        chown pi:pi /home/pi/.ssh
        touch /home/pi/.ssh/authorized_keys
        chmod 600 /home/pi/.ssh/authorized_keys
        chown pi:pi /home/pi/.ssh/authorized_keys
    fi
    
    # Aktiviere SSH
    systemctl enable ssh
    systemctl restart ssh
    
    # Firewall (falls installiert)
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 22/tcp comment "SSH"
    fi
    
    info "✓ SSH aktiviert"
    warn "WICHTIG: Bitte SSH-Key hinzufügen mit: $(basename $0) add-key"
    warn "Standard-Passwort 'raspberry' sollte geändert werden!"
    
    # Zeige Zugriffsinformationen
    echo ""
    info "SSH Zugriff:"
    echo "  ssh pi@$(hostname -I | awk '{print $1}')"
    echo "  oder"
    echo "  ssh pi@sitrep.local"
    echo ""
}

disable_ssh() {
    info "Deaktiviere SSH..."
    
    read -p "SSH wirklich deaktivieren? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Abgebrochen."
        exit 0
    fi
    
    systemctl stop ssh
    systemctl disable ssh
    
    info "✓ SSH deaktiviert"
}

status_ssh() {
    info "SSH Status:"
    echo ""
    systemctl status ssh --no-pager || echo "SSH ist nicht installiert"
    echo ""
    
    if systemctl is-active --quiet ssh; then
        info "SSH ist aktiv"
        echo ""
        info "Zugriff möglich via:"
        ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print "  ssh pi@" $2}' | sed 's|/.*||'
        echo "  ssh pi@sitrep.local"
        echo ""
        
        # Zeige aktive Verbindungen
        if [ -n "$(who -a | grep pts)" ]; then
            info "Aktive SSH Verbindungen:"
            who -a | grep pts
        fi
    else
        warn "SSH ist nicht aktiv"
    fi
    
    # Zeige Konfiguration
    if [ -f /etc/ssh/sshd_config.d/sitrep-secure.conf ]; then
        echo ""
        info "Sicherheitseinstellungen aktiv:"
        cat /etc/ssh/sshd_config.d/sitrep-secure.conf | grep -v "^#" | grep -v "^$"
    fi
}

configure_ssh() {
    info "SSH Konfiguration"
    echo ""
    
    # Port ändern
    read -p "SSH Port [Standard: 22]: " SSH_PORT
    SSH_PORT=${SSH_PORT:-22}
    
    # TCP Forwarding
    read -p "TCP Forwarding erlauben? [y/N]: " -n 1 -r
    echo ""
    TCP_FORWARD="no"
    [[ $REPLY =~ ^[Yy]$ ]] && TCP_FORWARD="yes"
    
    # Update Konfiguration
    sed -i "s/^Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config.d/sitrep-secure.conf
    sed -i "s/^AllowTcpForwarding .*/AllowTcpForwarding $TCP_FORWARD/" /etc/ssh/sshd_config.d/sitrep-secure.conf
    
    # Neustart
    systemctl restart ssh
    
    info "✓ Konfiguration aktualisiert"
    info "SSH Port: $SSH_PORT"
    info "TCP Forwarding: $TCP_FORWARD"
}

add_ssh_key() {
    info "SSH Public Key hinzufügen"
    echo ""
    
    AUTHORIZED_KEYS="/home/pi/.ssh/authorized_keys"
    
    # Erstelle Verzeichnis falls nicht vorhanden
    if [ ! -d /home/pi/.ssh ]; then
        mkdir -p /home/pi/.ssh
        chmod 700 /home/pi/.ssh
        chown pi:pi /home/pi/.ssh
        touch "$AUTHORIZED_KEYS"
        chmod 600 "$AUTHORIZED_KEYS"
        chown pi:pi "$AUTHORIZED_KEYS"
    fi
    
    echo "Bitte SSH Public Key eingeben (ssh-rsa, ssh-ed25519, etc.):"
    echo "(Mehrzeilige Eingabe mit Ctrl+D beenden)"
    echo ""
    
    # Lese Key
    TMP_KEY=$(mktemp)
    cat > "$TMP_KEY"
    
    # Validiere Key
    if ssh-keygen -l -f "$TMP_KEY" >/dev/null 2>&1; then
        cat "$TMP_KEY" >> "$AUTHORIZED_KEYS"
        chown pi:pi "$AUTHORIZED_KEYS"
        info "✓ SSH Key hinzugefügt"
        
        # Zeige Fingerprint
        echo ""
        info "Key Fingerprint:"
        ssh-keygen -l -f "$TMP_KEY"
    else
        error "Ungültiger SSH Key"
    fi
    
    rm -f "$TMP_KEY"
    
    # Zeige alle Keys
    echo ""
    info "Autorisierte Keys:"
    ssh-keygen -l -f "$AUTHORIZED_KEYS" | nl
}

generate_ssh_key() {
    info "Generiere SSH Key-Paar für Client"
    echo ""
    
    read -p "Email/Kommentar für Key: " KEY_COMMENT
    KEY_COMMENT=${KEY_COMMENT:-"sitrep@$(hostname)"}
    
    OUTPUT_DIR="/tmp/sitrep-ssh-keys"
    mkdir -p "$OUTPUT_DIR"
    
    # Generiere Key
    ssh-keygen -t ed25519 -C "$KEY_COMMENT" -f "$OUTPUT_DIR/sitrep_key" -N ""
    
    info "✓ SSH Key generiert"
    echo ""
    echo "Private Key: $OUTPUT_DIR/sitrep_key"
    echo "Public Key:  $OUTPUT_DIR/sitrep_key.pub"
    echo ""
    info "Public Key zum Hinzufügen:"
    cat "$OUTPUT_DIR/sitrep_key.pub"
    echo ""
    warn "WICHTIG: Private Key sicher aufbewahren!"
    warn "Kopiere $OUTPUT_DIR/sitrep_key auf deinen Client"
}

# Main
case "${1:-}" in
    enable)
        enable_ssh
        ;;
    disable)
        disable_ssh
        ;;
    status)
        status_ssh
        ;;
    configure)
        configure_ssh
        ;;
    add-key)
        add_ssh_key
        ;;
    generate-key)
        generate_ssh_key
        ;;
    *)
        usage
        ;;
esac
