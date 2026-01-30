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
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

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
    if docker pull $image; then
        # Save image
        docker save $image | gzip > "$IMAGES_DIR/${image_name}.tar.gz"
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
    docker-compose build
    
    # Exportiere selbst-gebaute Images
    LOCAL_IMAGES=$(docker-compose config | grep 'image:' | awk '{print $2}' | grep -v '^gcr.io\|^ghcr.io\|^quay.io' || true)
    
    for image in $LOCAL_IMAGES; do
        if [ ! -z "$image" ]; then
            image_name=$(echo $image | tr '/:' '_')
            info "Exportiere lokales Image: $image"
            docker save $image | gzip > "$IMAGES_DIR/${image_name}.tar.gz"
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
