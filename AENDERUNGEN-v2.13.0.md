# Version 2.13.0 – NVIDIA-Paketupdates

Die funktionierende Version 2.12.18 bleibt unverändert erhalten. Die neue
Updatefunktion ist bewusst von der vollständigen Neuinstallation getrennt.

## Bedienung

```bash
bash ./nvidia-driver-setup-v2.13.0.sh
```

Im Menü sind neu:

- **12:** NVIDIA-Pakete auf diesem System aktualisieren (Host oder LXC).
- **13:** NVIDIA-Pakete eines LXC vollständig vom Proxmox-Host aus aktualisieren.
- **14:** NVIDIA-Update nur simulieren, anhand des vorhandenen APT-Caches.

Menü 1/2/4 bleibt die saubere Neuinstallation. Beim Update gibt es keinen
pauschalen NVIDIA-Purge und kein `--reinstall` für bereits aktuelle Pakete.
Dienststopp, Abschluss-Autoremove, Laufzeittests und Sicherungsrichtlinien
bleiben im Menü auswählbar. Die vorhandene GPU-Zuweisung wird nicht neu eingerichtet.

## Was das Update macht

1. Den bisherigen Paket-/Konfigurationsstand mit der vorhandenen Rückkehrsicherung absichern.
2. Paketquellen prüfen und APT-Paketlisten neu abrufen; alte Holds oder APT-Kandidaten
   dürfen die Suche nach neueren offiziellen Versionen nicht verdecken.
3. Auf dem Host die neueste verfügbare moderne Treiberversion ermitteln. Im LXC
   bleibt die Treiberversion exakt an das geladene Host-Kernelmodul gebunden.
4. Alle vorhandenen, vom Skript verwalteten NVIDIA-Pakete berücksichtigen,
   einschließlich optionaler Treiberbibliotheken, CUDA- und Container-Komponenten.
   Letztere verwenden ihre eigenen Versionsnummern, nicht die Treiberversion.
5. Einen gemeinsamen APT-Plan simulieren, zusätzlich notwendige NVIDIA-Abhängigkeiten
   exakt aufnehmen und alle benötigten Pakete vorladen. Erst anschließend Holds lösen.
6. Den Plan unmittelbar vor der Paketänderung erneut prüfen. Unerwartete Entfernungen,
   Versionswechsel, nicht vertrauenswürdige NVIDIA-Kandidaten und LXC-Kernelpakete blockieren.
7. Nur notwendige Paketänderungen ausführen. Auf dem Host DKMS und die installierte
   Moduldatei prüfen; ein erforderlicher Host-Neustart bleibt eine offene Abschlussprüfung.
8. Vollständige Debian-Paketversionen einschließlich Epoch und Revision nachprüfen.
   Die exakten Versionen werden in
   `/etc/apt/preferences.d/00-nvidia-driver-setup-update-pin.pref` festgelegt und
   mit `apt-mark hold` gebunden. APT-Kandidaten und Holds werden anschließend kontrolliert.

Der Vergleich vollständiger DEB-Versionen erfolgt mit `dpkg --compare-versions`.
Eine neuere Paketrevision desselben Treibers wird deshalb ebenfalls berücksichtigt.
Unabhängig versionierte Pakete müssen nicht dieselbe DEB-Version wie der Treiber haben.

## Sicherheit und Grenzen

- Kein globales `apt upgrade` oder `dist-upgrade`. Nur ausgewählte NVIDIA-Komponenten
  und ihre erforderlichen Abhängigkeiten werden aktualisiert. Das separat auswählbare
  Abschluss-Autoremove kann zusätzlich geprüfte verwaiste Pakete entfernen.
- Ein aktueller NVIDIA-Stack wird nicht neu installiert. Prüfung und Versionsbindung
  finden trotzdem statt; gewählte Zusatzaktionen wie Autoremove sind davon unabhängig.
- Versionierte CUDA-Toolkits werden innerhalb ihrer vorhandenen Paketnamen aktualisiert.
  Ein neues Toolkit-Hauptrelease wird nur durch ein bereits installiertes, übergeordnetes
  Metapaket nachgezogen; das Skript erfindet keine CUDA-ABI-Migration.
- Ein Update setzt einen gesunden Paketstand und eine eindeutige Zuordnung zu verfügbaren
  Zielpaketen voraus. Nicht verfügbare Komponenten werden nicht stillschweigend entfernt;
  bei Layoutwechseln oder beschädigten Altbeständen bleibt die saubere Installation verfügbar.
- Die vorhandene Host-Kernelmodulvariante bleibt erhalten. Kernel/DKMS wird im LXC nicht installiert.
- Ein LXC erhält niemals vorab Bibliotheken für ein noch nicht geladenes neues Host-Modul.
  Vorgehen: Host über Punkt 12 aktualisieren, falls erforderlich neu starten und Punkt 8
  abschließen; anschließend die betroffenen LXC einzeln über Punkt 13 aktualisieren.
- Fortsetzen verwendet die gespeicherten Zielpaketversionen. Ein geänderter LXC-Hoststand
  oder ein fehlender Updateplan führt zum Abbruch. Eine fremde, unterbrochene LXC-Installation
  wird nicht versehentlich als neues Update ausgeführt.
- Der Debian-13-`nvidia-smi`-Zusatzpayload wird bei Paketupdates mitgeführt. Paketverwaltete
  Binärdateien und nachträglich veränderte/unbekannte Dateien werden nicht blind überschrieben.
- Erfolgssicherungen/Logs werden nur nach vollständiger Abschlussprüfung gemäß gewählter
  Richtlinie entfernt. Bei Neustartbedarf oder fehlgeschlagener Laufzeitprüfung bleiben sie bestehen.
- Die Update-Vorschau erzeugt nur kurzlebige Planungsdateien, keine Systemlogs, Paketlisten-
  Downloads, Holds oder dauerhaften Änderungen. Der echte Lauf fragt die Quellen erneut ab.

Optional für Automatisierung:

```bash
bash ./nvidia-driver-setup-v2.13.0.sh --update --mode host
bash ./nvidia-driver-setup-v2.13.0.sh --update-lxc 101
bash ./nvidia-driver-setup-v2.13.0.sh --update --mode lxc --host-version 610.57.04
bash ./nvidia-driver-setup-v2.13.0.sh --update --mode host --dry-run
```

Die Beispielversion ist kein fest eingebautes Updateziel. Im normalen Betrieb sind
keine zusätzlichen Parameter nötig.

## Prüfung

```bash
bash ./test-nvidia-driver-setup-v2.13.0.sh
bash ./tests/test-nvidia-update.sh ./nvidia-driver-setup-v2.13.0.sh
bash ./tests/test-nvidia-update-transaction.sh ./nvidia-driver-setup-v2.13.0.sh
bash ./tests/test-nvidia-update-lxc.sh ./nvidia-driver-setup-v2.13.0.sh
```

Die zusätzlichen Tests führen echte Planungs-, Menü-, Mutationsschutz-, Update- und
Versionsbindungsfunktionen aus. Linux-Systemgrenzen wie APT/dpkg, DKMS, Proxmox und
DEB-Archivierung werden durch kontrollierte Antworten ersetzt. Abgedeckt sind unter
anderem alte Holds, Epoch/Revision, mehrere Architekturen, neue Abhängigkeiten,
unveränderter Stand, Abbruch vor Installation, veränderte Pläne, Paket-/Pinningfehler,
LXC-Weitergabe und Fortsetzung. Die bestehenden Installationstests laufen weiterhin.

In dieser Windows-Umgebung ist kein echter Proxmox-/Ubuntu-/Debian-APT-Lauf mit GPU
möglich. Simulationen ersetzen den abschließenden Praxistest nicht und garantieren
keine fehlerfreie Installation bei beliebigen Paketquellen oder Hardwareproblemen.
Eine zusätzliche unabhängige Review-Instanz war wegen ihres Nutzungslimits nicht verfügbar.

Abschlussergebnis: **568 erfolgreiche Prüfungen, 0 fehlgeschlagene Prüfungen**;
die vollständige Testsuite endete mit Exit-Code 0. Bash-Syntaxprüfung und CLI-Hilfe
waren ebenfalls erfolgreich. Protokoll: `.test-run-v2.13.0.log`.
Die Tests wurden mit einer temporären Git-for-Windows-Bash-Laufzeit ausgeführt;
Laufzeit und Downloadarchiv wurden anschließend wieder entfernt.

SHA-256 des geprüften Installationsskripts:
`327A6CFBBB6129B873F3E11B4A1819F69A21197F4593BC83386B0EE25311EED3`.

Referenzen: [APT-Paketselektion und Simulation](https://manpages.debian.org/trixie/apt/apt-get.8.en.html),
[APT-Versionspräferenzen](https://manpages.debian.org/trixie/apt/apt_preferences.5.en.html),
[NVIDIA Version Locking](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/version-locking.html).
