# SitRep Offline Image Builder

Vollständig offline-fähiges SitRep System für Krisensituationen auf Raspberry Pi 4 oder Odroid.

## Features

✅ **Komplett Offline** - Funktioniert ohne Internetverbindung  
✅ **WiFi Hotspot** - Raspberry Pi erstellt eigenes WiFi-Netzwerk  
✅ **Lokale Authentifizierung** - Keine Cloud-Abhängigkeiten  
✅ **Captive Portal** - Automatische Weiterleitung zu SitRep  
✅ **mDNS Support** - Zugriff über `sitrep.local`  
✅ **Vorkonfiguriert** - Alle Docker-Container vorinstalliert  

## Systemanforderungen

### Hardware
- Raspberry Pi 4 (empfohlen: 4GB+ RAM)
- Oder: Odroid N2+, Odroid HC4
- SD-Karte: mindestens 16GB (32GB empfohlen)
- WiFi-Modul (beim RPi4 integriert)

### Software
- Raspberry Pi OS Lite (64-bit) oder Ubuntu Server 22.04 ARM64
- Docker & Docker Compose werden automatisch installiert

## Vorbereitung (Online - Einmalig)

Diese Schritte führst du auf einem Computer mit Internet aus:

### 1. Repository klonen
```bash
git clone https://github.com/czarofak/sitrep-image-builder.git
cd sitrep-image-builder
```

### 2. Docker Images vorbereiten
```bash
chmod +x prepare-images.sh
./prepare-images.sh
```

Dies lädt alle benötigten Docker-Images (~3-5 GB) und speichert sie als komprimierte Archive.

**Dauer:** 20-60 Minuten je nach Internet-Geschwindigkeit

### 3. Image prüfen
```bash
ls -lh docker-images/
cat docker-images/image-list.txt
```

## Installation auf Raspberry Pi (Offline möglich)

### Option A: Frische Installation auf neuer SD-Karte

1. **Basis-OS installieren**
   - Flashe Raspberry Pi OS Lite (64-bit) auf SD-Karte
   - Tool: Raspberry Pi Imager oder Balena Etcher
   - Aktiviere SSH in der Boot-Partition: `touch /boot/ssh`
   
2. **Builder kopieren**
   ```bash
   # Mounte die SD-Karte auf deinem Computer
   # Kopiere das Verzeichnis
   sudo cp -r sitrep-image-builder /mnt/sdcard/home/pi/
   ```

3. **Raspberry Pi booten**
   - SD-Karte einlegen und starten
   - Via SSH verbinden: `ssh pi@raspberrypi.local`
   - Standard-Passwort: `raspberry`

4. **Installation starten**
   ```bash
   cd /home/pi/sitrep-image-builder
   chmod +x install.sh
   sudo ./install.sh
   ```

Das System installiert sich automatisch und startet neu.

### Option B: Auf bestehendem System

```bash
# Dateien übertragen (z.B. via USB-Stick)
sudo cp -r /media/usb/sitrep-image-builder /opt/

# Installation starten
cd /opt/sitrep-image-builder
sudo bash install.sh
```

## Nach der Installation

### Erste Verbindung

1. **WiFi Hotspot suchen**
   - SSID: `SitRep-Emergency`
   - Passwort: `emergency123`

2. **Browser öffnen**
   - URL: `http://192.168.50.1:3000`
   - Oder: `http://sitrep.local:3000`

3. **Anmelden**
   - Benutzer: `admin@sitrep.local`
   - Passwort: `admin`
   - **WICHTIG:** Passwort sofort ändern!

### Hotspot anpassen

```bash
sudo /opt/sitrep-image-builder/scripts/configure-hotspot.sh
```

Ändere:
- SSID Name
- WiFi Passwort
- IP-Adresse
- WiFi-Kanal

## Verwaltung

### Services starten/stoppen

```bash
# SitRep
sudo systemctl start sitrep
sudo systemctl stop sitrep
sudo systemctl status sitrep

# WiFi Hotspot
sudo systemctl start sitrep-hotspot
sudo systemctl stop sitrep-hotspot
```

### Logs anzeigen

```bash
# Service Logs
sudo journalctl -u sitrep -f

# Docker Logs
cd /opt/sitrep
sudo docker-compose logs -f
```

### Backup erstellen

```bash
# Datenbank-Backup
sudo docker exec sitrep_postgres_1 pg_dump -U sitrep sitrep > backup.sql

# Komplett-Backup
sudo tar czf sitrep-backup-$(date +%Y%m%d).tar.gz \
  /opt/sitrep \
  /etc/sitrep \
  /var/lib/sitrep
```

## Konfiguration

### Umgebungsvariablen
Datei: `/etc/sitrep/sitrep.env`

### Dex Authentifizierung
Datei: `/etc/sitrep/dex-config.yaml`

### Weitere Benutzer hinzufügen

```bash
# Passwort-Hash generieren
htpasswd -bnBC 10 "" deinpasswort | tr -d ':\n'

# In /etc/sitrep/dex-config.yaml eintragen unter staticPasswords:
# - email: "user@sitrep.local"
#   hash: "$2a$10$..."
#   username: "user"
#   userID: "unique-id"

# Dex neu starten
sudo docker-compose -f /opt/sitrep/docker-compose.yml restart dex
```

## Netzwerk-Modi

### Als Access Point (Standard)
- Raspberry Pi erstellt WiFi-Netzwerk
- Clients verbinden sich mit dem Hotspot
- Keine externe Netzwerk-Verbindung nötig

### Als Client in bestehendem Netzwerk
```bash
# WiFi-Hotspot deaktivieren
sudo systemctl disable sitrep-hotspot
sudo systemctl stop sitrep-hotspot

# Mit bestehendem WiFi verbinden
sudo nmcli device wifi connect "SSID" password "PASSWORD"

# SitRep ist dann über die zugewiesene IP erreichbar
ip addr show wlan0
```

## Troubleshooting

### WiFi Hotspot startet nicht
```bash
# Interface prüfen
ip link show wlan0

# Dienste manuell starten
sudo systemctl start hostapd
sudo systemctl start dnsmasq
sudo journalctl -u hostapd -f
```

### Docker Container starten nicht
```bash
cd /opt/sitrep
sudo docker-compose down
sudo docker-compose up -d
sudo docker-compose logs
```

### Keine Verbindung zu SitRep möglich
```bash
# Firewall prüfen (sollte keine sein)
sudo iptables -L

# Ports prüfen
sudo netstat -tulpn | grep -E ':(3000|8080|5556)'

# DNS prüfen
sudo systemctl status dnsmasq
```

### Passwort vergessen
```bash
# Admin-Passwort zurücksetzen auf "admin"
sudo nano /etc/sitrep/dex-config.yaml
# Hash ersetzen mit: $2a$10$2b2cU8CPhOTaGrs1HRQuAueS7JTT5ZHsHSzYiFPm1leZck7Mc8T4W
sudo docker-compose -f /opt/sitrep/docker-compose.yml restart dex
```

## Erweiterte Konfiguration

### Mehrere Raspberry Pis im Mesh-Netzwerk

Für größere Einsätze können mehrere RPis als Mesh-Netzwerk konfiguriert werden:

```bash
# Auf jedem RPi unterschiedliche SSID aber gleiches Netzwerk
# RPi 1: SitRep-East / 192.168.50.1
# RPi 2: SitRep-West / 192.168.50.2
# Routing zwischen den RPis einrichten
```

### Externe Datenbank (für Redundanz)

```bash
# PostgreSQL auf separatem Server
# In /etc/sitrep/sitrep.env anpassen:
HASURA_GRAPHQL_DATABASE_URL=postgres://user:pass@192.168.50.10:5432/sitrep
```

## Performance-Optimierung

### Für Raspberry Pi 4 mit 2GB RAM
```bash
# Docker Memory-Limits setzen
nano /opt/sitrep/docker-compose.override.yml
# Für jeden Service hinzufügen:
#   mem_limit: 256m
#   memswap_limit: 512m
```

### SD-Karte Lebensdauer verlängern
```bash
# Log2RAM installieren (schreibt Logs in RAM)
echo "deb http://packages.azlux.fr/debian/ bullseye main" | sudo tee /etc/apt/sources.list.d/azlux.list
wget -qO - https://azlux.fr/repo.gpg.key | sudo apt-key add -
sudo apt update
sudo apt install log2ram
```

## Sicherheitshinweise

⚠️ **Wichtig für den Produktiv-Einsatz:**

1. **Passwörter ändern** - Alle Standard-Passwörter anpassen
2. **HTTPS aktivieren** - Für den Einsatz im Internet
3. **Firewall konfigurieren** - Nur benötigte Ports öffnen
4. **Regelmäßige Backups** - Automatisierte Datensicherung einrichten
5. **Updates** - System regelmäßig aktualisieren (im Wartungsfenster)

## Lizenz

Basierend auf [SitRep](https://github.com/f-eld-ch/sitrep) - AGPL-3.0 License

## Support

- GitHub Issues: https://github.com/f-eld-ch/sitrep/issues
- Email: info@f-eld.ch
- Demo: https://demo.sitrep.ch

## Credits

Entwickelt für Krisenstäbe und Katastrophenschutz-Organisationen.
Unterstützt von F-ELD, SZSV/FSPC und VSHN.
