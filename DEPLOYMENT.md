# SitRep Offline Image Builder - Deployment Guide

## Überblick

Dieses Paket erstellt ein vollständig offline-fähiges SitRep-System auf Raspberry Pi 4 oder Odroid mit folgenden Features:

✅ **Komplett offline** - Keine Internet-Verbindung erforderlich  
✅ **WiFi Hotspot** - Raspberry Pi wird zum Access Point  
✅ **Lokale Authentifizierung** - Dex statt Auth0  
✅ **Vorkonfiguriert** - Alle Docker-Container enthalten  
✅ **Einfache Verwaltung** - Management-Skripte inklusive  

## Schnellstart

### Variante 1: Auf vorhandenem Raspberry Pi OS

```bash
# 1. Pakete vorbereiten (auf einem Computer mit Internet)
git clone <dein-repo>
cd sitrep-image-builder
make prepare      # Lädt SitRep und Docker Images (~3-5 GB)

# 2. Paket erstellen
make package      # Erstellt ZIP-Datei

# 3. Auf Raspberry Pi kopieren und installieren
# Via USB-Stick oder SD-Karte
sudo bash install.sh
```

### Variante 2: Komplett-Image flashen (empfohlen)

```bash
# 1. Vorbereitung (einmalig, mit Internet)
make prepare

# 2. Image bauen
# TODO: Packer-Build implementieren
# Alternativ: Manuelle Installation dokumentiert

# 3. Image flashen
sudo dd if=sitrep-offline.img of=/dev/sdX bs=4M status=progress
```

## Verzeichnisstruktur

```
sitrep-image-builder/
├── install.sh                 # Haupt-Installationsskript
├── prepare-images.sh          # Docker-Images vorbereiten
├── Makefile                   # Build-Automation
├── README.md                  # Vollständige Dokumentation
├── QUICKSTART.md              # Endbenutzer-Anleitung
├── packer-template.json       # Packer-Config (WIP)
├── scripts/
│   ├── configure-hotspot.sh   # WiFi-Hotspot konfigurieren
│   ├── backup-restore.sh      # Backup/Restore System
│   └── ssh-config.sh          # SSH Management
├── config/                    # Vorbereitete Configs
├── docker-images/             # Gespeicherte Docker-Images
└── sitrep/                    # SitRep Repository (nach prepare)
```

## Installation - Schritt für Schritt

### Phase 1: Vorbereitung (Online, einmalig)

**Systemanforderungen:**
- Linux/Mac/WSL2
- Docker installiert
- Git installiert
- ~10 GB freier Speicher

```bash
# Dependencies installieren
make install-deps

# Repository klonen
git clone https://github.com/f-eld-ch/sitrep-image-builder.git
cd sitrep-image-builder

# Alle Docker-Images herunterladen und vorbereiten
make prepare

# Dies dauert 20-60 Minuten je nach Internet-Geschwindigkeit
# und lädt folgende Images:
# - SitRep UI & Server
# - Hasura GraphQL Engine
# - PostgreSQL 15
# - Redis 7
# - Dex (Authentifizierung)
# - OAuth2-Proxy
# - Flipt (Feature Flags)

# Paket erstellen
make package

# Ergebnis: output/sitrep-offline-1.0.0-installer.zip
```

### Phase 2: Installation (Offline möglich)

**Hardware vorbereiten:**
1. Raspberry Pi 4 (4GB+ RAM)
2. SD-Karte (32GB empfohlen)
3. Raspberry Pi OS Lite 64-bit flashen
4. Boot-Partition: Datei `ssh` anlegen für SSH-Zugriff

**Installation durchführen:**

```bash
# Option A: Via SSH
scp sitrep-offline-1.0.0-installer.zip pi@raspberrypi.local:/home/pi/
ssh pi@raspberrypi.local
unzip sitrep-offline-1.0.0-installer.zip
cd sitrep-image-builder
sudo bash install.sh

# Option B: SD-Karte direkt beschreiben
# SD-Karte mounten
sudo mount /dev/sdX2 /mnt
sudo cp -r sitrep-image-builder /mnt/home/pi/
sudo umount /mnt
# SD-Karte in RPi, booten, dann via SSH verbinden und installieren

# Installation läuft automatisch durch:
# - Docker & Dependencies installieren
# - Docker-Images laden
# - WiFi-Hotspot konfigurieren
# - Systemd-Services einrichten
# - System neu starten
```

**Nach der Installation:**
- System startet neu (~2 Minuten)
- WiFi-Hotspot "SitRep-Emergency" erscheint
- Verbinden mit Passwort: "emergency123"
- Browser öffnen: http://192.168.50.1:3000

### Phase 3: Erste Konfiguration

```bash
# Via SSH verbinden (falls aktiviert)
ssh pi@192.168.50.1
# Passwort: raspberry (Standard)

# 1. Hotspot anpassen
sudo /opt/sitrep-image-builder/scripts/configure-hotspot.sh

# 2. SSH sicher konfigurieren (optional)
sudo /opt/sitrep-image-builder/scripts/ssh-config.sh enable
sudo /opt/sitrep-image-builder/scripts/ssh-config.sh add-key

# 3. Automatisches Backup einrichten
sudo /opt/sitrep-image-builder/scripts/backup-restore.sh auto-backup

# 4. Standard-Passwörter ändern
# - pi User: passwd
# - SitRep Admin: Über Web-Interface
```

## Verwaltung im Betrieb

### Services

```bash
# SitRep Service
sudo systemctl status sitrep
sudo systemctl restart sitrep
sudo journalctl -u sitrep -f

# WiFi Hotspot
sudo systemctl status sitrep-hotspot
sudo systemctl restart sitrep-hotspot

# Einzelne Container
cd /opt/sitrep
sudo docker-compose ps
sudo docker-compose logs -f
sudo docker-compose restart hasura
```

### Backup & Restore

```bash
# Backup erstellen
sudo /opt/sitrep-image-builder/scripts/backup-restore.sh backup

# Backup auf USB-Stick
sudo /opt/sitrep-image-builder/scripts/backup-restore.sh backup /mnt/usb

# Liste der Backups
sudo /opt/sitrep-image-builder/scripts/backup-restore.sh list

# Restore
sudo /opt/sitrep-image-builder/scripts/backup-restore.sh restore backup.tar.gz
```

### Hotspot-Konfiguration

```bash
sudo /opt/sitrep-image-builder/scripts/configure-hotspot.sh
# Ändert: SSID, Passwort, IP, Kanal
```

### SSH-Verwaltung

```bash
# SSH aktivieren
sudo /opt/sitrep-image-builder/scripts/ssh-config.sh enable

# SSH-Key hinzufügen
sudo /opt/sitrep-image-builder/scripts/ssh-config.sh add-key

# Status prüfen
sudo /opt/sitrep-image-builder/scripts/ssh-config.sh status
```

## Konfigurationsdateien

```
/etc/sitrep/
├── sitrep.env              # Umgebungsvariablen (Secrets!)
└── dex-config.yaml         # Dex Authentifizierung

/opt/sitrep/
├── docker-compose.yml      # Docker Services
└── docker-compose.override.yml  # Lokale Anpassungen

/etc/hostapd/hostapd.conf   # WiFi-Hotspot
/etc/dnsmasq.conf           # DHCP & DNS
```

## Standard-Zugangsdaten

**WiFi Hotspot:**
- SSID: `SitRep-Emergency`
- Passwort: `emergency123`

**SitRep Login:**
- Admin: `admin@sitrep.local` / `admin`
- User: `user@sitrep.local` / `admin`

**Raspberry Pi:**
- User: `pi` / `raspberry`

⚠️ **WICHTIG:** Alle Passwörter nach erster Anmeldung ändern!

## Netzwerk-Topologie

```
[Internet] (optional)
    |
[Raspberry Pi] 192.168.50.1
    |
    +-- wlan0 (AP Mode)
         |
         +-- [Tablet] 192.168.50.10
         +-- [Laptop] 192.168.50.11
         +-- [Phone]  192.168.50.12
         ...
```

**DNS-Namen:**
- `sitrep.local` → 192.168.50.1
- Captive Portal leitet alle Anfragen zu SitRep

## Performance-Tuning

### Für Raspberry Pi 4 mit 2GB RAM

```yaml
# In docker-compose.override.yml
services:
  hasura:
    mem_limit: 512m
  postgres:
    mem_limit: 512m
    command: postgres -c shared_buffers=128MB -c max_connections=50
```

### Für maximale Akkulaufzeit

```bash
# CPU-Frequenz begrenzen
echo "arm_freq=1000" >> /boot/config.txt

# Onboard-LEDs deaktivieren
echo "dtparam=act_led_trigger=none" >> /boot/config.txt
echo "dtparam=pwr_led_trigger=none" >> /boot/config.txt
```

## Troubleshooting

### Problem: WiFi-Hotspot startet nicht

```bash
# Interface prüfen
ip link show wlan0
sudo rfkill unblock wifi

# Dienste neu starten
sudo systemctl restart sitrep-hotspot
sudo systemctl status hostapd
sudo journalctl -u hostapd -n 50
```

### Problem: Docker-Container starten nicht

```bash
# Memory-Verwendung prüfen
free -h
docker stats

# Container-Logs
cd /opt/sitrep
sudo docker-compose logs --tail=100

# Neustart
sudo docker-compose down
sudo docker-compose up -d
```

### Problem: Datenbank-Fehler

```bash
# Postgres-Logs
sudo docker logs sitrep_postgres_1

# Neustart mit Wiederherstellung
cd /opt/sitrep
sudo docker-compose stop postgres
sudo docker-compose start postgres
```

## Best Practices

### Vor dem Einsatz

- [ ] Vollständiges Backup erstellen
- [ ] Alle Passwörter geändert
- [ ] System-Update durchgeführt
- [ ] Funktionstests absolviert
- [ ] Ersatz-SD-Karte vorbereitet
- [ ] Dokumentation ausgedruckt
- [ ] Team geschult

### Während des Einsatzes

- Regelmäßige Backups (alle 6h)
- System-Monitoring (Speicher, CPU)
- Batteriestatus überwachen
- Log-Größe im Auge behalten

### Nach dem Einsatz

- Finales Backup erstellen
- Daten archivieren
- System herunterfahren
- Lessons Learned dokumentieren

## Erweiterte Szenarien

### Mehrere Raspberry Pis im Mesh

```bash
# RPi 1 als Master
SITREP_HOST=192.168.50.1

# RPi 2 als Slave mit Replikation
# In /etc/sitrep/sitrep.env auf RPi 2:
HASURA_GRAPHQL_DATABASE_URL=postgres://user:pass@192.168.50.1:5432/sitrep
```

### Externe Peripherie

```bash
# USB-Drucker
sudo apt-get install cups
sudo systemctl enable cups

# GPS-Empfänger
sudo apt-get install gpsd
# Integration in SitRep über API
```

### HTTPS mit Self-Signed Cert

```bash
# Zertifikat erstellen
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/sitrep.key \
  -out /etc/ssl/certs/sitrep.crt

# Nginx als Reverse Proxy
# (Konfiguration separat)
```

## Lizenz & Credits

Basierend auf [SitRep](https://github.com/f-eld-ch/sitrep)  
Lizenz: AGPL-3.0

Entwickelt für:
- Krisenstäbe
- Katastrophenschutz
- Einsatzleitung
- Führungsstäbe

Partner:
- F-ELD
- SZSV / FSPC
- VSHN

## Support & Kontakt

- GitHub: https://github.com/f-eld-ch/sitrep
- Issues: https://github.com/f-eld-ch/sitrep/issues
- Email: info@f-eld.ch
- Demo: https://demo.sitrep.ch

---

**Version:** 1.0.0  
**Datum:** 2026-01-28  
**Status:** Production Ready
