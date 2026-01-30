#!/bin/bash
set -e

# SitRep Image Preparation Script
# Optimiert für Ubuntu 24.04 LTS
# Dieses Skript lädt alle benötigten Docker Images und speichert sie für Offline-Installation

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
IMAGES_DIR="$SCRIPT_DIR/docker-images"
SITREP_REPO="https://github.com/f-eld-ch/sitrep.git"
SITREP_BRANCH="develop"
SITREP_IMAGE="ghcr.io/f-eld-ch/sitrep:latest"

echo "=================================="
echo "SitRep Image Preparation"
echo "=================================="
echo ""

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Funktion: Bytes in lesbare Größe umwandeln (Fallback für numfmt)
human_readable_size() {
    local bytes=$1
    if command -v numfmt &> /dev/null; then
        numfmt --to=iec "$bytes"
    else
        # Fallback ohne numfmt
        if [ "$bytes" -ge 1073741824 ]; then
            echo "$(( bytes / 1073741824 ))G"
        elif [ "$bytes" -ge 1048576 ]; then
            echo "$(( bytes / 1048576 ))M"
        elif [ "$bytes" -ge 1024 ]; then
            echo "$(( bytes / 1024 ))K"
        else
            echo "${bytes}B"
        fi
    fi
}

# Prüfe Ubuntu Version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    info "Erkanntes System: $PRETTY_NAME"
else
    info "System: $(uname -s) $(uname -r)"
fi
echo ""

# Funktion: Systemabhängigkeiten installieren
install_dependencies() {
    info "Prüfe Systemabhängigkeiten..."

    local MISSING_DEPS=""

    # Prüfe benötigte Pakete
    command -v git &> /dev/null || MISSING_DEPS="$MISSING_DEPS git"
    command -v curl &> /dev/null || MISSING_DEPS="$MISSING_DEPS curl"

    if [ -n "$MISSING_DEPS" ]; then
        info "Installiere fehlende Pakete:$MISSING_DEPS"
        sudo apt-get update
        sudo apt-get install -y $MISSING_DEPS
    fi

    info "✓ Alle Abhängigkeiten verfügbar"
    echo ""
}

# Installiere Abhängigkeiten
install_dependencies

# Funktion: Docker installieren
install_docker() {
    echo ""
    info "Installiere Docker für Ubuntu..."
    echo ""

    # Entferne alte Docker-Versionen falls vorhanden
    sudo apt-get remove -y docker.io docker-doc docker-compose podman-docker containerd runc 2>/dev/null || true

    # Installiere Voraussetzungen
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg

    # Docker GPG Key hinzufügen
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Docker Repository hinzufügen
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Docker installieren (inkl. Compose Plugin)
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Benutzer zur Docker-Gruppe hinzufügen
    sudo usermod -aG docker $USER

    # Docker starten
    sudo systemctl enable docker
    sudo systemctl start docker

    echo ""
    info "Docker wurde installiert!"
}

# Funktion: Docker-Compose installieren (als Plugin)
install_docker_compose() {
    echo ""
    info "Installiere Docker Compose Plugin..."
    echo ""

    sudo apt-get update
    sudo apt-get install -y docker-compose-plugin

    echo ""
    info "Docker Compose wurde installiert!"
}

# Prüfe ob Docker installiert ist
if ! command -v docker &> /dev/null; then
    warn "Docker ist nicht installiert!"
    echo ""
    read -p "Soll Docker jetzt installiert werden? (j/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Jj]$ ]]; then
        install_docker
        # Hinweis für Gruppenänderung
        echo ""
        warn "WICHTIG: Du musst dich neu einloggen, damit die Docker-Gruppe aktiv wird!"
        echo "Alternativ kannst du jetzt 'newgrp docker' ausführen."
        echo ""
        read -p "Drücke Enter um fortzufahren (mit sudo) oder Ctrl+C zum Abbrechen..."
        # Führe Docker-Befehle mit sudo aus falls nötig
        DOCKER_CMD="sudo docker"
        DOCKER_COMPOSE_CMD="sudo docker-compose"
    else
        error "Docker wird benötigt. Abbruch."
        exit 1
    fi
else
    DOCKER_CMD="docker"
    DOCKER_COMPOSE_CMD="docker-compose"
fi

# Prüfe ob Docker-Compose installiert ist
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null 2>&1; then
    warn "Docker Compose ist nicht installiert!"
    echo ""
    read -p "Soll Docker Compose jetzt installiert werden? (j/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Jj]$ ]]; then
        install_docker_compose
    else
        error "Docker Compose wird benötigt. Abbruch."
        exit 1
    fi
fi

# Bestimme Docker-Compose Befehl (standalone oder plugin)
if command -v docker-compose &> /dev/null; then
    # Standalone docker-compose
    if [ "$DOCKER_CMD" = "sudo docker" ]; then
        DOCKER_COMPOSE_CMD="sudo docker-compose"
    else
        DOCKER_COMPOSE_CMD="docker-compose"
    fi
elif $DOCKER_CMD compose version &> /dev/null 2>&1; then
    # Docker Compose Plugin
    DOCKER_COMPOSE_CMD="$DOCKER_CMD compose"
fi

# Prüfe ob Docker läuft
if ! $DOCKER_CMD info &> /dev/null; then
    warn "Docker läuft nicht!"
    echo ""
    read -p "Soll Docker jetzt gestartet werden? (j/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Jj]$ ]]; then
        sudo systemctl start docker
        sleep 2
        if ! $DOCKER_CMD info &> /dev/null; then
            error "Docker konnte nicht gestartet werden."
            exit 1
        fi
    else
        error "Docker muss laufen. Abbruch."
        exit 1
    fi
fi

echo -e "${GREEN}[OK]${NC} Docker ist verfügbar"
echo ""

# Erstelle Verzeichnisse
mkdir -p "$IMAGES_DIR"
mkdir -p "$SCRIPT_DIR/sitrep"

# Clone oder Update SitRep Repository
if [ -d "$SCRIPT_DIR/sitrep/.git" ]; then
    info "Aktualisiere SitRep Repository..."
    cd "$SCRIPT_DIR/sitrep"
    git pull origin $SITREP_BRANCH
else
    info "Clone SitRep Repository..."
    git clone --branch $SITREP_BRANCH $SITREP_REPO "$SCRIPT_DIR/sitrep"
fi

cd "$SCRIPT_DIR/sitrep"

# Funktion: Image sicher exportieren (nur wenn es existiert)
export_image() {
    local image="$1"
    local image_name=$(echo "$image" | tr '/:' '_')

    # Prüfe ob Image existiert
    if $DOCKER_CMD image inspect "$image" &> /dev/null; then
        info "Exportiere: $image"
        $DOCKER_CMD save "$image" | gzip > "$IMAGES_DIR/${image_name}.tar.gz"

        # Prüfe ob Export erfolgreich war (Datei > 1KB)
        local filesize=$(stat -c%s "$IMAGES_DIR/${image_name}.tar.gz" 2>/dev/null || echo "0")
        if [ "$filesize" -gt 1000 ]; then
            info "✓ Gespeichert: ${image_name}.tar.gz ($(human_readable_size $filesize))"
            return 0
        else
            warn "⚠ Export fehlgeschlagen für $image (Datei zu klein)"
            rm -f "$IMAGES_DIR/${image_name}.tar.gz"
            return 1
        fi
    else
        warn "⚠ Image nicht gefunden: $image"
        return 1
    fi
}

# Extrahiere alle Images aus docker-compose.yml
info "Analysiere docker-compose.yml..."
if [ -f "$SCRIPT_DIR/sitrep/docker-compose.yml" ]; then
    cd "$SCRIPT_DIR/sitrep"

    # Hole alle Images aus docker-compose config
    ALL_IMAGES=$($DOCKER_COMPOSE_CMD config 2>/dev/null | grep -E '^\s+image:' | awk '{print $2}' | sort -u || true)

    # Trenne in externe und lokale Images
    EXTERNAL_IMAGES=""
    LOCAL_BUILD_SERVICES=""

    for image in $ALL_IMAGES; do
        # Externe Images enthalten meist einen Registry-Pfad oder bekannte Prefixe
        if [[ "$image" == *"ghcr.io/f-eld-ch"* ]]; then
            # SitRep eigene Images - müssen gebaut werden
            LOCAL_BUILD_SERVICES="$LOCAL_BUILD_SERVICES $image"
        elif [[ "$image" == *"/"* ]] || [[ "$image" == *":"* ]]; then
            # Externe Images (haben / oder : im Namen)
            EXTERNAL_IMAGES="$EXTERNAL_IMAGES $image"
        fi
    done

    echo ""
    info "Gefundene externe Images:"
    for img in $EXTERNAL_IMAGES; do
        echo "  - $img"
    done
    echo ""
else
    error "docker-compose.yml nicht gefunden!"
    exit 1
fi

# Schritt 1: Baue alle lokalen Images
info "Baue SitRep Images aus Source Code..."
echo ""

cd "$SCRIPT_DIR/sitrep"

# Baue alle Services die ein build: haben
if $DOCKER_COMPOSE_CMD build; then
    info "✓ Lokale Images erfolgreich gebaut"
else
    warn "⚠ Einige Images konnten nicht gebaut werden"
fi
echo ""

# Schritt 2: Pulle alle externen Images
info "Lade externe Docker Images..."
echo ""

for image in $EXTERNAL_IMAGES; do
    info "Verarbeite: $image"

    if $DOCKER_CMD pull "$image"; then
        info "✓ Geladen: $image"
    else
        warn "⚠ Konnte $image nicht laden"
    fi
    echo ""
done

# Zusätzlich: Lade das vollständige SitRep Image (enthält UI + Server)
SITREP_IMAGE="ghcr.io/f-eld-ch/sitrep:latest"
info "Lade vollständiges SitRep Image (mit UI)..."
if $DOCKER_CMD pull "$SITREP_IMAGE"; then
    info "✓ SitRep Image geladen: $SITREP_IMAGE"
else
    warn "⚠ Konnte SitRep Image nicht laden: $SITREP_IMAGE"
    warn "  Versuche alternative Version..."
    # Fallback auf latest
    if $DOCKER_CMD pull "ghcr.io/f-eld-ch/sitrep:latest"; then
        SITREP_IMAGE="ghcr.io/f-eld-ch/sitrep:latest"
        info "✓ SitRep Image geladen: $SITREP_IMAGE"
    fi
fi
echo ""

# Schritt 3: Exportiere alle Images
info "Exportiere alle Docker Images..."
echo ""

# Hole alle geladenen/gebauten Images nochmal frisch
cd "$SCRIPT_DIR/sitrep"
FINAL_IMAGES=$($DOCKER_COMPOSE_CMD config 2>/dev/null | grep -E '^\s+image:' | awk '{print $2}' | sort -u || true)

EXPORT_COUNT=0
EXPORT_FAILED=0

for image in $FINAL_IMAGES; do
    if export_image "$image"; then
        ((EXPORT_COUNT++))
    else
        ((EXPORT_FAILED++))
    fi
    echo ""
done

# Zusätzlich: Exportiere das lokal gebaute sitrep-graphql-engine falls vorhanden
if $DOCKER_CMD image inspect "sitrep-graphql-engine:latest" &> /dev/null; then
    export_image "sitrep-graphql-engine:latest"
    ((EXPORT_COUNT++))
fi

# Exportiere das vollständige SitRep Image
if $DOCKER_CMD image inspect "$SITREP_IMAGE" &> /dev/null; then
    export_image "$SITREP_IMAGE"
    ((EXPORT_COUNT++))
elif $DOCKER_CMD image inspect "ghcr.io/f-eld-ch/sitrep:latest" &> /dev/null; then
    export_image "ghcr.io/f-eld-ch/sitrep:latest"
    ((EXPORT_COUNT++))
fi

# Erstelle Liste der gespeicherten Images
info "Erstelle Image-Liste..."

# Zähle nur gültige tar.gz Dateien (> 1KB)
VALID_FILES=$(find "$IMAGES_DIR" -name "*.tar.gz" -size +1k 2>/dev/null | wc -l)

cat > "$IMAGES_DIR/image-list.txt" <<EOF
# SitRep Docker Images
# Generiert: $(date)
# Für Offline-Installation

EOF

# Liste nur Dateien > 1KB auf
for f in "$IMAGES_DIR"/*.tar.gz; do
    if [ -f "$f" ]; then
        filesize=$(stat -c%s "$f" 2>/dev/null || echo "0")
        if [ "$filesize" -gt 1000 ]; then
            echo "$(basename "$f") $(human_readable_size $filesize)" >> "$IMAGES_DIR/image-list.txt"
        fi
    fi
done

echo "" >> "$IMAGES_DIR/image-list.txt"
echo "Gesamt: $(du -sh "$IMAGES_DIR" | awk '{print $1}')" >> "$IMAGES_DIR/image-list.txt"
echo "Anzahl Images: $VALID_FILES" >> "$IMAGES_DIR/image-list.txt"

# Erstelle Load-Skript
cat > "$IMAGES_DIR/load-images.sh" <<'LOADSCRIPT'
#!/bin/bash
# Lade alle Docker Images aus diesem Verzeichnis

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Lade Docker Images..."
for image_file in "$SCRIPT_DIR"/*.tar.gz; do
    if [ -f "$image_file" ]; then
        # Überspringe leere/defekte Dateien
        filesize=$(stat -c%s "$image_file" 2>/dev/null || echo "0")
        if [ "$filesize" -gt 1000 ]; then
            echo "Lade: $(basename $image_file)"
            gunzip -c "$image_file" | docker load
        else
            echo "Überspringe (ungültig): $(basename $image_file)"
        fi
    fi
done
echo "Fertig!"
LOADSCRIPT

chmod +x "$IMAGES_DIR/load-images.sh"

echo ""
echo "=================================="
info "Image-Vorbereitung abgeschlossen!"
echo "=================================="
echo ""
echo -e "${GREEN}Erfolgreich exportiert:${NC} $EXPORT_COUNT Images"
if [ "$EXPORT_FAILED" -gt 0 ]; then
    echo -e "${YELLOW}Fehlgeschlagen:${NC} $EXPORT_FAILED Images"
fi
echo ""
cat "$IMAGES_DIR/image-list.txt"
echo ""
info "Nächste Schritte:"
echo "1. Kopiere das gesamte Verzeichnis 'sitrep-image-builder' auf die Ziel-SD-Karte"
echo "2. Führe auf dem Raspberry Pi aus: sudo bash install.sh"
echo ""
