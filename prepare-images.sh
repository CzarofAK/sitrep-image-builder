#!/bin/bash
set -e

# SitRep Image Preparation Script
# Dieses Skript lädt alle benötigten Docker Images und speichert sie für Offline-Installation

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
IMAGES_DIR="$SCRIPT_DIR/docker-images"
SITREP_REPO="https://github.com/f-eld-ch/sitrep.git"
SITREP_BRANCH="develop"

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

# Funktion: Docker installieren
install_docker() {
    echo ""
    info "Installiere Docker..."
    echo ""

    # Docker Installation via offizielles Script
    curl -fsSL https://get.docker.com | sh

    # Benutzer zur Docker-Gruppe hinzufügen
    sudo usermod -aG docker $USER

    # Docker starten
    sudo systemctl enable docker
    sudo systemctl start docker

    echo ""
    info "Docker wurde installiert!"
}

# Funktion: Docker-Compose installieren
install_docker_compose() {
    echo ""
    info "Installiere Docker Compose..."
    echo ""

    # Versuche docker-compose-plugin zu installieren
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y docker-compose-plugin
    else
        # Fallback: Standalone docker-compose
        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
        sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi

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

# Liste der benötigten Images
DOCKER_IMAGES=(
    # SitRep spezifische Images
    "ghcr.io/f-eld-ch/sitrep/ui:latest"
    "ghcr.io/f-eld-ch/sitrep/server:latest"
    
    # Hasura
    "hasura/graphql-engine:v2.38.0"
    
    # PostgreSQL
    "postgres:15-alpine"
    
    # Redis
    "redis:7-alpine"
    
    # Dex für lokale Authentifizierung
    "ghcr.io/dexidp/dex:v2.37.0"
    
    # OAuth2 Proxy
    "quay.io/oauth2-proxy/oauth2-proxy:v7.5.1"
    
    # Flipt (Feature Flags)
    "flipt/flipt:latest"
)

info "Lade und exportiere Docker Images..."
echo ""

# Pull und Save Images
for image in "${DOCKER_IMAGES[@]}"; do
    image_name=$(echo $image | tr '/:' '_')
    info "Verarbeite: $image"
    
    # Pull image
    if $DOCKER_CMD pull $image; then
        # Save image
        $DOCKER_CMD save $image | gzip > "$IMAGES_DIR/${image_name}.tar.gz"
        info "✓ Gespeichert: ${image_name}.tar.gz"
    else
        warn "⚠ Konnte $image nicht laden"
    fi
    echo ""
done

# Build lokale Images falls nötig
info "Baue lokale Images..."
if [ -f "$SCRIPT_DIR/sitrep/docker-compose.yml" ]; then
    cd "$SCRIPT_DIR/sitrep"
    $DOCKER_COMPOSE_CMD build

    # Exportiere selbst-gebaute Images
    LOCAL_IMAGES=$($DOCKER_COMPOSE_CMD config | grep 'image:' | awk '{print $2}' | grep -v '^gcr.io\|^ghcr.io\|^quay.io' || true)

    for image in $LOCAL_IMAGES; do
        if [ ! -z "$image" ]; then
            image_name=$(echo $image | tr '/:' '_')
            info "Exportiere lokales Image: $image"
            $DOCKER_CMD save $image | gzip > "$IMAGES_DIR/${image_name}.tar.gz"
        fi
    done
fi

# Erstelle Liste der gespeicherten Images
info "Erstelle Image-Liste..."
cat > "$IMAGES_DIR/image-list.txt" <<EOF
# SitRep Docker Images
# Generiert: $(date)
# Für Offline-Installation

$(ls -lh "$IMAGES_DIR"/*.tar.gz | awk '{print $9, $5}')

Gesamt: $(du -sh "$IMAGES_DIR" | awk '{print $1}')
EOF

# Erstelle Load-Skript
cat > "$IMAGES_DIR/load-images.sh" <<'LOADSCRIPT'
#!/bin/bash
# Lade alle Docker Images aus diesem Verzeichnis

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Lade Docker Images..."
for image_file in "$SCRIPT_DIR"/*.tar.gz; do
    if [ -f "$image_file" ]; then
        echo "Lade: $(basename $image_file)"
        gunzip -c "$image_file" | docker load
    fi
done
echo "Fertig!"
LOADSCRIPT

chmod +x "$IMAGES_DIR/load-images.sh"

info "Image-Vorbereitung abgeschlossen!"
echo ""
cat "$IMAGES_DIR/image-list.txt"
echo ""
info "Nächste Schritte:"
echo "1. Kopiere das gesamte Verzeichnis 'sitrep-image-builder' auf die Ziel-SD-Karte"
echo "2. Führe auf dem Raspberry Pi aus: sudo bash install.sh"
echo ""
