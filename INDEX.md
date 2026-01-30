# 🚀 SitRep Offline Image Builder

**Vollständig offline-fähiges Krisen-Management-System für Raspberry Pi**

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL%203.0-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Platform: Raspberry Pi](https://img.shields.io/badge/Platform-Raspberry%20Pi-red.svg)](https://www.raspberrypi.org/)
[![Status: Production Ready](https://img.shields.io/badge/Status-Production%20Ready-green.svg)]()

## 📋 Was ist das?

Dieses Projekt erstellt ein **komplett offline-fähiges SitRep-System** auf einem Raspberry Pi 4 oder Odroid. Perfekt für Krisensituationen ohne Internet oder Mobilfunk.

### Hauptmerkmale

✅ **Offline-First** - Funktioniert komplett ohne Internet  
✅ **WiFi Hotspot** - Raspberry Pi wird zum Access Point  
✅ **Lokale Authentifizierung** - Dex statt Cloud-Services  
✅ **Plug & Play** - Vorkonfiguriert und sofort einsatzbereit  
✅ **Einfache Verwaltung** - Management-Tools inklusive  
✅ **Sicher** - SSH-Härte, sichere Defaults  

## 🎯 Anwendungsfälle

- 🚨 Katastrophenschutz & Krisenmanagement
- 🏥 Mobile Einsatzleitungen
- 🎪 Event-Management ohne Internet
- 🏔️ Remote-Operationen (Berghütten, etc.)
- 🔒 Air-Gapped Environments

## 📦 Lieferumfang

```
sitrep-image-builder/
├── 📄 README.md              # Diese Datei
├── 📄 DEPLOYMENT.md          # Vollständige Deployment-Anleitung
├── 📄 QUICKSTART.md          # Schnellstart für Endbenutzer
├── 🔧 Makefile               # Build-Automatisierung
├── 🔧 install.sh             # Haupt-Installationsskript
├── 🔧 prepare-images.sh      # Docker-Images vorbereiten
├── 📁 scripts/
│   ├── configure-hotspot.sh  # WiFi-Hotspot konfigurieren
│   ├── backup-restore.sh     # Backup/Restore System
│   └── ssh-config.sh         # SSH Management
├── 📁 config/                # Vorbereitete Configs
├── 📁 docker-images/         # Docker-Images (nach prepare)
└── 📁 sitrep/                # SitRep Repository (nach prepare)
```

## 🚀 Schnellstart

### 1. Vorbereitung (Online, einmalig)

```bash
# Repository klonen
git clone https://github.com/czarofak/sitrep-image-builder.git
cd sitrep-image-builder

# Docker-Images herunterladen (~3-5 GB, 20-60 Min.)
make prepare

# Installations-Paket erstellen
make package
```

**Ergebnis:** `output/sitrep-offline-1.0.0-installer.zip`

### 2. Installation (Offline möglich)

```bash
# Auf Raspberry Pi OS (frisch geflasht)
unzip sitrep-offline-1.0.0-installer.zip
cd sitrep-image-builder
sudo bash install.sh

# System startet automatisch neu
```

### 3. Zugriff

Nach ~3 Minuten:

**WiFi verbinden:**
- SSID: `SitRep-Emergency`
- Passwort: `emergency123`

**Browser öffnen:**
- URL: `http://192.168.50.1:3000`
- Login: `admin@sitrep.local` / `admin`

## 📖 Dokumentation

- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Vollständige Installations- und Betriebsanleitung
- **[QUICKSTART.md](QUICKSTART.md)** - Kurzanleitung für Endbenutzer
- **[README.md](README.md)** - Technische Details und Entwicklung

## 🛠️ Systemanforderungen

### Hardware

- Raspberry Pi 4 (4GB+ RAM empfohlen)
- SD-Karte: 32GB empfohlen (min. 16GB)
- Stromversorgung: USB-C 5V/3A
- Optional: Kühlung (Gehäuse mit Lüfter)

### Software

- Raspberry Pi OS Lite 64-bit (aktuell)
- Oder: Ubuntu Server 22.04 ARM64
- Docker & Docker Compose (wird automatisch installiert)

## 🔐 Sicherheit

⚠️ **Wichtige Sicherheitshinweise:**

1. **Standard-Passwörter ändern** (sehr wichtig!)
2. SSH nur bei Bedarf aktivieren (mit Keys)
3. WiFi-Passwort komplex wählen
4. Regelmäßige Backups erstellen
5. System-Updates bei Gelegenheit einspielen

## 📊 Features im Detail

### Offline-Betrieb

- Alle Dependencies vorinstalliert
- Docker-Images lokal gespeichert
- Keine externen API-Calls
- Lokale Authentifizierung mit Dex

### WiFi-Hotspot

- Automatische Konfiguration
- DHCP & DNS Server
- Captive Portal (optional)
- mDNS Support (sitrep.local)
- Bis zu 10 gleichzeitige Clients

### Management-Tools

```bash
# Hotspot anpassen
sudo configure-hotspot.sh

# Backup erstellen
sudo backup-restore.sh backup

# SSH aktivieren
sudo ssh-config.sh enable
```

## 🎓 Verwendung

### Typischer Workflow

```bash
# 1. Raspberry Pi starten
# 2. Mit WiFi "SitRep-Emergency" verbinden
# 3. Browser öffnen: http://192.168.50.1:3000
# 4. Anmelden und loslegen

# Optional: Via SSH verwalten
ssh pi@192.168.50.1

# Services verwalten
sudo systemctl status sitrep
sudo systemctl restart sitrep

# Backup erstellen
sudo /opt/sitrep-image-builder/scripts/backup-restore.sh backup

# Logs ansehen
sudo journalctl -u sitrep -f
```

## 🔧 Erweiterte Konfiguration

### Hotspot anpassen

```bash
sudo /opt/sitrep-image-builder/scripts/configure-hotspot.sh
# Ändert: SSID, Passwort, IP, Kanal
```

### Benutzer hinzufügen

In `/etc/sitrep/dex-config.yaml`:

```yaml
staticPasswords:
- email: "neuer.user@sitrep.local"
  hash: "$2a$10$..."  # htpasswd -bnBC 10 "" password
  username: "neuer.user"
  userID: "unique-uuid"
```

### Performance-Tuning

Für 2GB RAM in `docker-compose.override.yml`:

```yaml
services:
  hasura:
    mem_limit: 512m
  postgres:
    mem_limit: 512m
```

## 🐛 Troubleshooting

### WiFi erscheint nicht

```bash
sudo systemctl status sitrep-hotspot
sudo systemctl restart sitrep-hotspot
sudo journalctl -u hostapd -n 50
```

### Container starten nicht

```bash
cd /opt/sitrep
sudo docker-compose down
sudo docker-compose up -d
sudo docker-compose logs -f
```

### Datenbank-Probleme

```bash
# Backup wiederherstellen
sudo /opt/sitrep-image-builder/scripts/backup-restore.sh restore backup.tar.gz
```

## 📈 Roadmap

- [ ] Packer-Template für automatische Image-Erstellung
- [ ] Ansible Playbook für Multiple Deployments
- [ ] Web-UI für Erstkonfiguration
- [ ] Mesh-Networking Support
- [ ] Auto-Update Mechanismus
- [ ] Monitoring Dashboard

## 🤝 Contributing

Beiträge sind willkommen! Bitte:

1. Fork das Repository
2. Feature Branch erstellen
3. Änderungen committen
4. Pull Request erstellen

## 📜 Lizenz

Basierend auf [SitRep](https://github.com/f-eld-ch/sitrep)

**Lizenz:** AGPL-3.0

## 💬 Support

- **GitHub Issues:** https://github.com/f-eld-ch/sitrep/issues
- **Email:** info@f-eld.ch
- **Demo:** https://demo.sitrep.ch

## 🙏 Credits

**Entwickelt für:**
- Krisenstäbe
- Katastrophenschutz-Organisationen
- Einsatzleitungen

**Partner:**
- F-ELD
- SZSV / FSPC
- VSHN

## 📸 Screenshots

*Siehe [QUICKSTART.md](QUICKSTART.md) für Screenshots und visuelle Anleitung*

---

**Version:** 1.0.0  
**Build Date:** 2026-01-28  
**Status:** Production Ready ✅

**Viel Erfolg beim Einsatz!** 🚀
