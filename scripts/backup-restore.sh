#!/bin/bash
set -e

# SitRep Backup & Restore Tool
# Für komplette Datensicherung des Systems

BACKUP_DIR="/var/backups/sitrep"
INSTALL_DIR="/opt/sitrep"
CONFIG_DIR="/etc/sitrep"
DATA_DIR="/var/lib/sitrep"

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
    error "Bitte als root ausführen (sudo ./backup-restore.sh)"
fi

usage() {
    cat <<EOF
SitRep Backup & Restore Tool

Verwendung:
  $(basename $0) backup [destination]     - Erstelle Backup
  $(basename $0) restore <backup-file>    - Stelle Backup wieder her
  $(basename $0) list                     - Liste Backups
  $(basename $0) auto-backup              - Richte automatisches Backup ein

Beispiele:
  $(basename $0) backup                   # Backup nach $BACKUP_DIR
  $(basename $0) backup /mnt/usb          # Backup auf USB-Stick
  $(basename $0) restore backup.tar.gz    # Stelle wieder her
EOF
    exit 1
}

create_backup() {
    local destination=${1:-$BACKUP_DIR}
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="sitrep-backup-$timestamp.tar.gz"
    
    info "Erstelle Backup..."
    mkdir -p "$destination"
    
    # Temporäres Verzeichnis
    local tmp_dir=$(mktemp -d)
    
    # PostgreSQL Dump
    info "Sichere Datenbank..."
    docker exec sitrep_postgres_1 pg_dump -U sitrep sitrep > "$tmp_dir/database.sql" || warn "Datenbank-Backup fehlgeschlagen"
    
    # Docker Volumes
    info "Sichere Docker Volumes..."
    docker run --rm -v sitrep_postgres_data:/data -v "$tmp_dir":/backup alpine tar czf /backup/postgres_data.tar.gz -C /data . || warn "Postgres Volume Backup fehlgeschlagen"
    
    # Konfigurationsdateien
    info "Sichere Konfiguration..."
    cp -r "$CONFIG_DIR" "$tmp_dir/config" 2>/dev/null || warn "Config Backup fehlgeschlagen"
    cp -r "$INSTALL_DIR" "$tmp_dir/install" 2>/dev/null || warn "Install-Dir Backup fehlgeschlagen"
    
    # System-Informationen
    info "Sammle System-Informationen..."
    cat > "$tmp_dir/system-info.txt" <<SYSINFO
SitRep Backup Information
=========================
Datum: $(date)
Hostname: $(hostname)
System: $(uname -a)
Docker Version: $(docker --version)
Docker Compose Version: $(docker-compose --version)

Docker Container:
$(docker ps -a)

Docker Images:
$(docker images)

WiFi Konfiguration:
$(cat /etc/hostapd/hostapd.conf 2>/dev/null || echo "Nicht gefunden")

Netzwerk:
$(ip addr)
SYSINFO
    
    # Erstelle Archiv
    info "Erstelle Archiv..."
    tar czf "$destination/$backup_file" -C "$tmp_dir" .
    
    # Cleanup
    rm -rf "$tmp_dir"
    
    info "✓ Backup erstellt: $destination/$backup_file"
    ls -lh "$destination/$backup_file"
    
    # Alte Backups aufräumen (behalte nur letzte 5)
    info "Räume alte Backups auf..."
    cd "$destination"
    ls -t sitrep-backup-*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm
    
    echo ""
    info "Backup abgeschlossen!"
}

restore_backup() {
    local backup_file=$1
    
    if [ ! -f "$backup_file" ]; then
        error "Backup-Datei nicht gefunden: $backup_file"
    fi
    
    warn "ACHTUNG: Dies überschreibt die aktuelle Installation!"
    read -p "Fortfahren? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Abgebrochen."
        exit 0
    fi
    
    # Stoppe Services
    info "Stoppe SitRep..."
    systemctl stop sitrep 2>/dev/null || true
    docker-compose -f "$INSTALL_DIR/docker-compose.yml" down 2>/dev/null || true
    
    # Temporäres Verzeichnis
    local tmp_dir=$(mktemp -d)
    
    # Entpacke Backup
    info "Entpacke Backup..."
    tar xzf "$backup_file" -C "$tmp_dir"
    
    # Restore Datenbank
    if [ -f "$tmp_dir/database.sql" ]; then
        info "Stelle Datenbank wieder her..."
        # Starte nur Postgres
        docker-compose -f "$INSTALL_DIR/docker-compose.yml" up -d postgres
        sleep 5
        docker exec -i sitrep_postgres_1 psql -U sitrep sitrep < "$tmp_dir/database.sql"
    fi
    
    # Restore Volumes
    if [ -f "$tmp_dir/postgres_data.tar.gz" ]; then
        info "Stelle Postgres Volume wieder her..."
        docker run --rm -v sitrep_postgres_data:/data -v "$tmp_dir":/backup alpine tar xzf /backup/postgres_data.tar.gz -C /data
    fi
    
    # Restore Konfiguration
    if [ -d "$tmp_dir/config" ]; then
        info "Stelle Konfiguration wieder her..."
        cp -r "$tmp_dir/config/"* "$CONFIG_DIR/"
    fi
    
    # Restore Installation
    if [ -d "$tmp_dir/install" ]; then
        info "Stelle Installation wieder her..."
        cp -r "$tmp_dir/install/"* "$INSTALL_DIR/"
    fi
    
    # Cleanup
    rm -rf "$tmp_dir"
    
    # Starte Services
    info "Starte SitRep..."
    systemctl start sitrep
    
    info "✓ Wiederherstellung abgeschlossen!"
}

list_backups() {
    info "Verfügbare Backups in $BACKUP_DIR:"
    echo ""
    
    if [ -d "$BACKUP_DIR" ]; then
        ls -lht "$BACKUP_DIR"/sitrep-backup-*.tar.gz 2>/dev/null | awk '{print "  " $9 "  (" $5 "  " $6 " " $7 " " $8 ")"}'
    else
        warn "Keine Backups gefunden"
    fi
}

setup_auto_backup() {
    info "Richte automatisches Backup ein..."
    
    # Erstelle Backup-Skript
    cat > /usr/local/bin/sitrep-auto-backup.sh <<'AUTOBACKUP'
#!/bin/bash
/opt/sitrep-image-builder/scripts/backup-restore.sh backup /var/backups/sitrep
AUTOBACKUP
    
    chmod +x /usr/local/bin/sitrep-auto-backup.sh
    
    # Erstelle Systemd Timer
    cat > /etc/systemd/system/sitrep-backup.service <<'SERVICE'
[Unit]
Description=SitRep Automatic Backup
After=sitrep.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sitrep-auto-backup.sh
SERVICE
    
    cat > /etc/systemd/system/sitrep-backup.timer <<'TIMER'
[Unit]
Description=SitRep Daily Backup Timer

[Timer]
OnCalendar=daily
OnCalendar=03:00
Persistent=true

[Install]
WantedBy=timers.target
TIMER
    
    # Aktiviere Timer
    systemctl daemon-reload
    systemctl enable sitrep-backup.timer
    systemctl start sitrep-backup.timer
    
    info "✓ Automatisches Backup eingerichtet (täglich 03:00 Uhr)"
    systemctl status sitrep-backup.timer --no-pager
}

# Main
case "${1:-}" in
    backup)
        create_backup "$2"
        ;;
    restore)
        if [ -z "$2" ]; then
            error "Bitte Backup-Datei angeben"
        fi
        restore_backup "$2"
        ;;
    list)
        list_backups
        ;;
    auto-backup)
        setup_auto_backup
        ;;
    *)
        usage
        ;;
esac
