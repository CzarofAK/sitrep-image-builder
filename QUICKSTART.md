# SitRep Offline - Quick Start Guide

## Was ist das?

SitRep Offline ist ein komplett offline-fähiges Krisen-Management-System auf einem Raspberry Pi. Perfekt für Einsätze ohne Internet oder Mobilfunk.

## Schnellstart (5 Minuten)

### 1. Hardware vorbereiten
- Raspberry Pi 4 (4GB+ RAM empfohlen)
- SD-Karte (min. 16GB)
- Stromversorgung (USB-C, 5V/3A)
- Optional: Gehäuse mit Kühlung

### 2. Image flashen
```bash
# Download: sitrep-offline-v1.0.0.img.zip
# Entpacken und flashen mit:

# Windows: Balena Etcher oder Raspberry Pi Imager
# Linux/Mac:
unzip sitrep-offline-v1.0.0.img.zip
sudo dd if=sitrep-offline-v1.0.0.img of=/dev/sdX bs=4M status=progress
sync
```

### 3. Raspberry Pi starten
- SD-Karte einlegen
- Stromkabel anschließen
- **Warten:** Erste Boot dauert 2-3 Minuten

### 4. Mit WiFi verbinden
**WiFi Suchen:**
- SSID: `SitRep-Emergency`
- Passwort: `emergency123`

**Browser öffnen:**
- URL: `http://192.168.50.1:3000`
- Oder: `http://sitrep.local:3000`

### 5. Anmelden
- Benutzer: `admin@sitrep.local`
- Passwort: `admin`

⚠️ **WICHTIG:** Passwort sofort ändern!

## Grundfunktionen

### Lage erfassen
1. Neuer Eintrag → Typ auswählen
2. Informationen eingeben
3. Speichern

### Nachrichten senden
1. Nachrichten-Editor öffnen
2. Empfänger wählen
3. Nachricht verfassen

### Journal führen
- Automatische Zeitstempel
- Filtern nach Typ/Priorität
- Export als PDF

### Karte verwenden
- Ereignisse platzieren
- Ressourcen markieren
- Übersicht behalten

## Konfiguration

### WiFi-Hotspot ändern
```bash
# Via SSH (wenn aktiviert):
ssh pi@192.168.50.1
# Passwort: raspberry (Standard)

sudo /opt/sitrep-image-builder/scripts/configure-hotspot.sh
```

### Weitere Benutzer anlegen
1. Admin-Login
2. Einstellungen → Benutzerverwaltung
3. Neuen Benutzer hinzufügen

### Backup erstellen
```bash
# Via SSH:
sudo docker exec sitrep_postgres_1 pg_dump -U sitrep sitrep > backup-$(date +%Y%m%d).sql
```

## Fehlerbehebung

### WiFi erscheint nicht
- Warte 3-5 Minuten nach erstem Boot
- RPi neu starten (Strom aus/ein)
- LED-Status prüfen (sollte blinken)

### Kann mich nicht verbinden
- Passwort korrekt? `emergency123`
- Mehrere Geräte? Nur 10 gleichzeitig möglich
- Zu weit weg? Max. 30m Reichweite

### Website lädt nicht
- Warte noch 1 Minute (Services starten)
- Versuche: `http://192.168.50.1:3000`
- Neustart: Strom aus, 10 Sek warten, Strom an

### Login funktioniert nicht
- Browser-Cache leeren (Strg+Shift+Entf)
- Anderer Browser versuchen
- Falls alle Stricke reißen: Passwort zurücksetzen (siehe README)

## Tipps für den Einsatz

### Reichweite erhöhen
- Raspberry Pi erhöht platzieren
- Externe WiFi-Antenne verwenden
- Metallische Umgebung meiden

### Stromversorgung sichern
- Powerbank (min. 10.000 mAh)
- Solar-Panel mit USB
- Auto-Adapter (12V → 5V USB)

### Mehrere Geräte gleichzeitig
- Max. 10 Clients optimal
- Bei mehr: zweiten RPi als Repeater

### Daten sichern
- Täglich Backup
- Auf USB-Stick exportieren
- Wichtige Einträge ausdrucken

## Checkliste Einsatzvorbereitung

**Vor jedem Einsatz:**
- [ ] SD-Karte geprüft (keine Fehler)
- [ ] Stromversorgung getestet
- [ ] WiFi-Verbindung funktioniert
- [ ] Login möglich
- [ ] Aktuelles Backup vorhanden
- [ ] Benutzer angelegt und geschult
- [ ] Ersatz-SD-Karte dabei
- [ ] Dokumentation ausgedruckt

**Nach jedem Einsatz:**
- [ ] Finale Daten gesichert
- [ ] Backup auf Server/USB
- [ ] System heruntergefahren
- [ ] Equipment gereinigt
- [ ] Lessons Learned dokumentiert

## Technische Daten

- **System:** Raspberry Pi OS Lite (64-bit)
- **RAM-Bedarf:** Min. 2GB, empf. 4GB
- **Speicher:** Min. 16GB, empf. 32GB
- **Netzwerk:** WiFi 802.11ac (2.4/5 GHz)
- **Reichweite:** ~30m (je nach Umgebung)
- **Max. Clients:** 10 gleichzeitig
- **Betriebsdauer:** ~4h mit 10.000mAh Powerbank

## Wichtige Hinweise

⚠️ **Sicherheit:**
- Standard-Passwörter ändern!
- SSH nur bei Bedarf aktivieren
- Nicht unbeaufsichtigt lassen

⚠️ **Datenschutz:**
- Keine sensiblen Daten unverschlüsselt
- Nach Einsatz Daten archivieren
- Regelungen für Datenaufbewahrung beachten

⚠️ **Betrieb:**
- Nicht überhitzen lassen (Kühlung!)
- Vor Nässe schützen
- Nicht während Betrieb abstecken

## Support & Hilfe

**Dokumentation:**
- Vollständige Doku: `/opt/sitrep-installer/README.md`
- Logs: `sudo journalctl -u sitrep -f`

**Community:**
- GitHub: https://github.com/f-eld-ch/sitrep
- Demo: https://demo.sitrep.ch
- Email: info@f-eld.ch

**Training:**
- Online-Schulungen verfügbar
- Demo-Umgebung zum Üben
- Video-Tutorials

## Version

- Version: 1.0.0
- Build-Datum: 2026-01-28
- Basis: SitRep develop branch

---

**Viel Erfolg beim Einsatz!** 🚀

Bei Fragen oder Problemen: Dokumentation lesen oder Support kontaktieren.
