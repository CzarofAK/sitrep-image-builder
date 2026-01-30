.PHONY: help prepare build clean test install

# SitRep Offline Image Builder
# Makefile für einfache Bedienung

# Variablen
IMAGE_VERSION ?= 1.0.0
IMAGE_NAME = sitrep-offline-$(IMAGE_VERSION)
BUILD_DIR = build
OUTPUT_DIR = output

# Farben für Terminal-Output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

help: ## Zeigt diese Hilfe
	@echo "$(GREEN)SitRep Offline Image Builder$(NC)"
	@echo ""
	@echo "Verfügbare Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "Beispiele:"
	@echo "  make prepare          # Lade SitRep und Docker Images"
	@echo "  make build            # Baue fertiges Image"
	@echo "  make test             # Teste das gebaute Image"
	@echo "  make all              # Führe alle Schritte aus"

prepare: ## Bereite SitRep und Docker Images vor (benötigt Internet)
	@echo "$(GREEN)[1/3] Bereite SitRep vor...$(NC)"
	@chmod +x prepare-images.sh
	@./prepare-images.sh
	@echo "$(GREEN)✓ Vorbereitung abgeschlossen$(NC)"
	@echo ""
	@echo "Geladene Images:"
	@cat docker-images/image-list.txt
	@echo ""

verify: ## Prüfe ob alle Dateien vorhanden sind
	@echo "$(GREEN)Prüfe Dateien...$(NC)"
	@test -d sitrep || (echo "$(RED)✗ SitRep Repository fehlt$(NC)" && exit 1)
	@test -d docker-images || (echo "$(RED)✗ Docker Images fehlen$(NC)" && exit 1)
	@test -f install.sh || (echo "$(RED)✗ install.sh fehlt$(NC)" && exit 1)
	@echo "$(GREEN)✓ Alle Dateien vorhanden$(NC)"

package: verify ## Erstelle Installations-Paket (ZIP)
	@echo "$(GREEN)Erstelle Installations-Paket...$(NC)"
	@mkdir -p $(OUTPUT_DIR)
	@rm -f $(OUTPUT_DIR)/$(IMAGE_NAME)-installer.zip
	@zip -r $(OUTPUT_DIR)/$(IMAGE_NAME)-installer.zip \
		install.sh \
		prepare-images.sh \
		README.md \
		QUICKSTART.md \
		scripts/ \
		config/ \
		sitrep/ \
		docker-images/*.tar.gz \
		docker-images/load-images.sh \
		docker-images/image-list.txt
	@echo "$(GREEN)✓ Paket erstellt: $(OUTPUT_DIR)/$(IMAGE_NAME)-installer.zip$(NC)"
	@ls -lh $(OUTPUT_DIR)/$(IMAGE_NAME)-installer.zip

build: verify ## Baue fertiges Image mit Packer (benötigt Packer)
	@echo "$(YELLOW)Image-Bau mit Packer wird noch nicht unterstützt$(NC)"
	@echo "Bitte verwende 'make package' für ein Installations-Paket"

test: ## Teste das Installationspaket in QEMU
	@echo "$(YELLOW)Test in QEMU noch nicht implementiert$(NC)"
	@echo "Manuelle Testschritte:"
	@echo "1. Flashe ein frisches Raspberry Pi OS"
	@echo "2. Kopiere das Paket auf den RPi"
	@echo "3. Führe install.sh aus"

clean: ## Lösche Build-Artefakte
	@echo "$(YELLOW)Lösche Build-Artefakte...$(NC)"
	@rm -rf $(BUILD_DIR)
	@rm -rf $(OUTPUT_DIR)
	@echo "$(GREEN)✓ Aufgeräumt$(NC)"

clean-all: clean ## Lösche alles inkl. Docker Images
	@echo "$(RED)Lösche alle Downloads inkl. Docker Images...$(NC)"
	@read -p "Bist du sicher? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		rm -rf docker-images/*.tar.gz; \
		rm -rf sitrep; \
		echo "$(GREEN)✓ Alles gelöscht$(NC)"; \
	else \
		echo "$(YELLOW)Abgebrochen$(NC)"; \
	fi

docs: ## Generiere Dokumentation
	@echo "$(GREEN)Generiere Dokumentation...$(NC)"
	@mkdir -p $(OUTPUT_DIR)/docs
	@cp README.md $(OUTPUT_DIR)/docs/
	@cp QUICKSTART.md $(OUTPUT_DIR)/docs/
	@echo "$(GREEN)✓ Dokumentation in $(OUTPUT_DIR)/docs/$(NC)"

all: prepare verify package docs ## Führe alle Schritte aus
	@echo ""
	@echo "$(GREEN)═══════════════════════════════════════$(NC)"
	@echo "$(GREEN)  ✓ Build abgeschlossen!$(NC)"
	@echo "$(GREEN)═══════════════════════════════════════$(NC)"
	@echo ""
	@echo "Nächste Schritte:"
	@echo "1. Entpacke: $(OUTPUT_DIR)/$(IMAGE_NAME)-installer.zip"
	@echo "2. Kopiere auf Raspberry Pi"
	@echo "3. Führe aus: sudo bash install.sh"
	@echo ""
	@echo "Oder:"
	@echo "- Flashe Raspberry Pi OS"
	@echo "- Kopiere Verzeichnis nach /home/pi/"
	@echo "- SSH: sudo bash /home/pi/sitrep-image-builder/install.sh"
	@echo ""

install-deps: ## Installiere benötigte Tools (Ubuntu/Debian)
	@echo "$(GREEN)Installiere Abhängigkeiten...$(NC)"
	@command -v docker >/dev/null 2>&1 || { \
		echo "Installiere Docker..."; \
		curl -fsSL https://get.docker.com | sudo sh; \
	}
	@command -v git >/dev/null 2>&1 || sudo apt-get install -y git
	@command -v zip >/dev/null 2>&1 || sudo apt-get install -y zip
	@command -v jq >/dev/null 2>&1 || sudo apt-get install -y jq
	@echo "$(GREEN)✓ Abhängigkeiten installiert$(NC)"

info: ## Zeige System-Informationen
	@echo "$(GREEN)System-Informationen:$(NC)"
	@echo "  Version:      $(IMAGE_VERSION)"
	@echo "  Image Name:   $(IMAGE_NAME)"
	@echo "  Build Dir:    $(BUILD_DIR)"
	@echo "  Output Dir:   $(OUTPUT_DIR)"
	@echo ""
	@echo "$(GREEN)Installierte Tools:$(NC)"
	@command -v docker >/dev/null 2>&1 && echo "  ✓ Docker" || echo "  ✗ Docker"
	@command -v git >/dev/null 2>&1 && echo "  ✓ Git" || echo "  ✗ Git"
	@command -v zip >/dev/null 2>&1 && echo "  ✓ Zip" || echo "  ✗ Zip"
	@echo ""
	@echo "$(GREEN)Verfügbarer Speicher:$(NC)"
	@df -h . | tail -1 | awk '{print "  Gesamt: " $$2 "  Frei: " $$4}'

.DEFAULT_GOAL := help
