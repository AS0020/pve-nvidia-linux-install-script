# NVIDIA-Treiber-Setup für Proxmox, Debian, Ubuntu und LXC

Interaktives Bash-Skript zur Installation, Aktualisierung, Diagnose und Entfernung
von NVIDIA-Treibern auf Proxmox-/Ubuntu-Hosts sowie von passenden NVIDIA-
Userspace-Bibliotheken in Debian- und Ubuntu-LXC.

Die aktuelle Version ist **2.13.0**. Das Skript trennt Host und Container strikt:
Kernelmodule, Kernel-Header und DKMS gehören ausschließlich auf den Host; im LXC
werden nur die zur geladenen Host-Treiberversion passenden Bibliotheken und
Werkzeuge installiert.

> [!WARNING]
> Das Skript verändert APT-Paketquellen, installierte Pakete und – je nach
> Auswahl – Proxmox-LXC-Konfigurationen. Vor jeder Paketänderung wird eine
> Rückkehrbasis angelegt. Trotzdem sollte es zuerst über den Dry-Run geprüft und
> nicht ohne eigene System-Backups auf einem produktiven Host eingesetzt werden.

## Inhalt

- [Hauptfunktionen](#hauptfunktionen)
- [Unterstützte Systeme](#unterstützte-systeme)
- [Schnellstart](#schnellstart)
- [Interaktives Menü](#interaktives-menü)
- [Empfohlene Abläufe](#empfohlene-abläufe)
- [GPU-Zuweisung an LXC](#gpu-zuweisung-an-lxc)
- [Updates und Versionsbindung](#updates-und-versionsbindung)
- [Sicherungen, Rollback und Protokolle](#sicherungen-rollback-und-protokolle)
- [Abschlussprüfungen](#abschlussprüfungen)
- [Automatisierung über Optionen](#automatisierung-über-optionen)
- [Fehlerbehebung](#fehlerbehebung)
- [Tests](#tests)
- [Sicherheitsgrenzen](#sicherheitsgrenzen)

## Hauptfunktionen

- Saubere NVIDIA-Neuinstallation mit vorheriger Inventarisierung und Entfernung
  alter paketverwalteter NVIDIA-, CUDA- und Container-Komponenten.
- Separater Update-Modus ohne pauschalen Purge oder erzwungene Neuinstallation
  bereits aktueller Pakete.
- Exakter Abgleich zwischen installierten DEB-Paketen, geladenem Kernelmodul und
  NVIDIA-Userspace im LXC.
- Dynamische Ermittlung geeigneter Versionen aus geprüften offiziellen
  NVIDIA-Paketquellen.
- Korrekte Debian-Versionsvergleiche einschließlich Epoch und Revision.
- Wahl zwischen offenem und proprietärem Kernelmodul auf dem Host.
- Native Proxmox-Gerätezuweisung, mit manuellen LXC-Einträgen als Fallback.
- Auswahl mehrerer GPUs per Gerätedatei, GPU-UUID oder PCI-Adresse.
- Konfigurierbare Geräteberechtigungen statt festem `0666`.
- Automatische Diagnose für APT, dpkg, DKMS, Nouveau, Secure Boot, Kernelmodule,
  NVML, `nvidia-smi`, `nvtop`, NVENC und NVDEC.
- Transaktionale Sicherungen mit Manifesten und Prüfsummen.
- Automatischer Rollback bei Fehlern oder Abbruch mit `Ctrl+C`, sofern bereits
  eine vollständige Rückkehrbasis vorbereitet wurde.
- Schutz gegen gleichzeitige Skriptausführungen.
- Wiederaufnahme oder Rollback einer erkannten unterbrochenen Transaktion.
- Abschlussbericht sowie einstellbare Aufbewahrung erfolgreicher und
  fehlgeschlagener Sicherungen und Logs.

## Unterstützte Systeme

Das Skript unterstützt ausschließlich **amd64**:

| Rolle | Unterstützte Systeme |
|---|---|
| Proxmox-Host | Proxmox VE auf Debian 12 oder Debian 13 |
| LXC | Debian 12/13 oder Ubuntu 22.04/24.04/26.04 |

Für die LXC-Verwaltung vom Host werden Proxmox und `pct` benötigt. Auf einem
gewöhnlichen Ubuntu- oder Debian-System ist keine Proxmox-Gerätezuweisung möglich.

### Voraussetzungen

- Ausführung als `root` für alle verändernden Aktionen.
- Bash und ein APT-/dpkg-basiertes amd64-System.
- Internetzugriff auf die benötigten offiziellen Paketquellen.
- Passende Kernel-Header auf dem Host; das Skript prüft beziehungsweise
  installiert sie im Installationsablauf.
- Bei Secure Boot müssen NVIDIA-Module vom System akzeptiert werden. Das Skript
  diagnostiziert Probleme, kann aber keine Firmware-Schlüsselentscheidung ohne
  Benutzerinteraktion ersetzen.
- Der Proxmox-Host benötigt einen funktionsfähigen NVIDIA-Treiber, bevor ein LXC
  dieselbe Treiberversion verwenden kann.

## Schnellstart

Die Dateien auf den Zielhost kopieren und das aktuelle Skript starten:

```bash
chmod +x nvidia-driver-setup-v2.13.0.sh
sudo ./nvidia-driver-setup-v2.13.0.sh
```

Wenn bereits als `root` gearbeitet wird:

```bash
./nvidia-driver-setup-v2.13.0.sh
```

Ohne Parameter öffnet sich das vollständige interaktive Menü. Zusätzliche
Kommandozeilenparameter sind im normalen Betrieb nicht erforderlich.

Vor einer ersten produktiven Installation empfiehlt sich:

1. Menüpunkt **7** für die vollständige Installationssimulation.
2. Menüpunkt **5** für Diagnose und Versionsabgleich.
3. Erst danach Menüpunkt **1** für die saubere Installation.

## Interaktives Menü

| Nr. | Funktion | Paketänderungen |
|---:|---|---|
| 1 | NVIDIA auf diesem System sauber installieren | Ja |
| 2 | LXC vollständig vom Proxmox-Host einrichten | Ja, im LXC; zusätzlich Gerätezuweisung |
| 3 | Nur GPU-Geräte an einen LXC durchreichen | Nein |
| 4 | Nur NVIDIA-Bibliotheken im LXC vom Host installieren | Ja, nur im LXC |
| 5 | GPU, Versionen, Host und NVIDIA-LXC diagnostizieren | Nein |
| 6 | Automatische Fehleranalyse und sichere Reparatur | Abhängig vom Befund |
| 7 | Installation und LXC-Änderungen simulieren | Nein |
| 8 | Ausstehende Abschlussprüfung oder Transaktion fortsetzen | Abhängig vom gespeicherten Zustand |
| 9 | Eine Sicherung prüfen und zurückrollen | Ja, stellt gesicherten Zustand wieder her |
| 10 | Alte Sicherungen nach Aufbewahrungszeit bereinigen | Löscht ausgewählte abgelaufene Sicherungen |
| 11 | NVIDIA vollständig entfernen | Ja |
| 12 | Vorhandene NVIDIA-Pakete aktualisieren und exakt pinnen | Ja |
| 13 | NVIDIA-Pakete eines LXC vom Host aktualisieren | Ja, nur im LXC |
| 14 | NVIDIA-Update anhand des vorhandenen APT-Caches simulieren | Nein |

## Empfohlene Abläufe

### Host neu installieren

1. Menüpunkt **1** auf dem Proxmox- oder Ubuntu-Host wählen.
2. Die gewünschte Kernelmodulvariante, Versionsbindung, Dienstbehandlung und
   Bereinigung festlegen.
3. Bei erkanntem Neustartbedarf zuerst den Host neu starten.
4. Danach Menüpunkt **8** ausführen, damit die ausstehende Laufzeitprüfung
   abgeschlossen und die gespeicherte Sicherungsrichtlinie angewendet wird.

### Neuen LXC vollständig einrichten

1. Den NVIDIA-Treiber auf dem Proxmox-Host installieren und gegebenenfalls neu starten.
2. Auf dem Host Menüpunkt **2** wählen.
3. LXC und GPU-Auswahl festlegen.
4. Falls der Container gestoppt ist, den temporären Start ausdrücklich erlauben.
5. Das Skript überträgt sich kontrolliert in den LXC, installiert dort nur den
   Userspace und führt die Prüfungen vom Host aus durch.

Ein zuvor gestoppter Container wird nach dem Ablauf wieder gestoppt. Ein zuvor
laufender Container wird nur nach ausdrücklicher Auswahl kontrolliert neu gestartet.

### Vorhandenen Host und seine LXC aktualisieren

1. Auf dem Host Menüpunkt **12** ausführen.
2. Falls verlangt, den Host neu starten und die Prüfung über Menüpunkt **8** abschließen.
3. Danach jeden NVIDIA-LXC einzeln über Menüpunkt **13** aktualisieren.

Ein LXC wird nicht vorsorglich auf eine noch nicht geladene neue Host-Version
gebracht. Seine Bibliotheken müssen exakt zum tatsächlich geladenen Host-Modul passen.

## GPU-Zuweisung an LXC

Mehrere GPUs können stabil ausgewählt werden:

```bash
./nvidia-driver-setup-v2.13.0.sh \
  --attach-only 111 \
  --gpu-uuid GPU-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  --gpu-pci 0000:65:00.0 \
  --device-mode 0660 \
  --device-gid 44
```

Unterstützte Auswahlarten:

- `--gpu-device /dev/nvidiaN`
- `--gpu-uuid <GPU-UUID>`
- `--gpu-pci <PCI-Adresse>`
- `--all-gpus`

Das Skript bevorzugt native Proxmox-`devN`-Einträge. Bestehende verwaltete
NVIDIA-Einträge werden gesichert, dedupliziert und aktualisiert. Wenn die native
Zuweisung nicht verfügbar ist, kann ein klar markierter manueller Block mit
`lxc.cgroup2.devices.allow` und Bind-Mounts verwendet werden.

Gemeinsame Kontrollgeräte wie `/dev/nvidiactl`, `/dev/nvidia-uvm`,
`/dev/nvidia-uvm-tools` und vorhandene `/dev/nvidia-caps/*` werden berücksichtigt.
Die dynamischen Gerätenummern werden nach Kernel- oder Treiberänderungen erneut erkannt.

### Geräteberechtigungen

Im Menü können Modus, UID und GID gewählt werden. Empfohlen ist `inherit`, damit
der LXC die Berechtigungen der Host-Gerätedateien übernimmt. Alternativ ist zum
Beispiel `0660` mit der im Container verwendeten `video`-GID möglich.

`0666` erlaubt jedem Prozess im Container den Zugriff auf die durchgereichten
Geräte. Das kann für einen vollständig vertrauenswürdigen Container bequem sein,
ist aber nicht die restriktivste Einstellung.

## Updates und Versionsbindung

Menüpunkt **12** aktualisiert einen vorhandenen Stack ohne vollständige
Neuinstallation:

1. Paketquellen und Paketstatus prüfen.
2. Paketlisten aktualisieren.
3. Neueste geeignete offizielle Treiberversion bestimmen.
4. Alle vorhandenen verwalteten NVIDIA-, CUDA- und Container-Pakete einem
   verfügbaren Ziel zuordnen.
5. Den gemeinsamen APT-Plan simulieren und alle Pakete vorab herunterladen.
6. Alte NVIDIA-Holds lösen und nur die geplanten Änderungen ausführen.
7. Paketversionen, DKMS beziehungsweise LXC-Grenzen überprüfen.
8. Exakte DEB-Versionen pinnen und mit `apt-mark hold` binden.

Der Update-Modus führt kein globales `apt upgrade`, `dist-upgrade` oder
`full-upgrade` aus. Unabhängig versionierte CUDA- und Container-Pakete werden
nicht künstlich auf die Nummer des NVIDIA-Treibers gesetzt.

Wenn ein Paket nicht eindeutig auf eine verfügbare Version abgebildet werden
kann, bricht das Update vor der Paketentfernung ab. Für beschädigte Altbestände
oder Paketlayoutwechsel stehen Reparatur und saubere Neuinstallation getrennt bereit.

Die ausführlichen Änderungen stehen in
[AENDERUNGEN-v2.13.0.md](AENDERUNGEN-v2.13.0.md).

## Sicherungen, Rollback und Protokolle

### Sicherungen

Transaktionssicherungen werden standardmäßig unter folgendem Pfad angelegt:

```text
/opt/nvidia-backup/
```

Eine Sicherung enthält – abhängig vom Vorgang – unter anderem:

- Manifest mit Zeit, Rolle, Versionen und betroffenen Dateien.
- Prüfsummenmanifest.
- Paketlisten und gesicherte DEB-Dateien für den Rollback.
- Sicherungen geänderter APT-, Modprobe- und LXC-Konfigurationen.
- `resume.env`, Transaktionsstatus und ein geprüftes `rollback.sh`.
- Diagnose- und Simulationsausgaben.

Vor einem Rollback werden Pfad, Manifest und Prüfsummen geprüft. Ein manueller
Rollback kann über Menüpunkt **9** oder für Experten über `--rollback` gestartet werden.

### Installationslogs

Verändernde Läufe speichern ein farbfreies Gesamtprotokoll unter:

```text
/var/log/nvidia-driver-setup/
```

Standardmäßig werden erfolgreiche Detailprotokolle nach einem gespeicherten
Abschlussbericht entfernt. Fehler- und Pending-Logs bleiben erhalten. Dieses
Verhalten ist im Menü konfigurierbar.

`--check-only`, `--diagnose-all` und `--dry-run` erzeugen bewusst kein dauerhaftes
Installationslog.

### Abgebrochene Transaktionen

Beim nächsten Start erkennt das Skript eine aktive, nicht abgeschlossene
Transaktion. Sie kann über das Menü fortgesetzt oder anhand der geprüften
Sicherung zurückgerollt werden. Ein neuer verändernder Vorgang wird nicht einfach
über eine ungeklärte Transaktion gelegt.

## Abschlussprüfungen

Nach einer Installation oder Aktualisierung kontrolliert das Skript – soweit für
die gewählte Rolle anwendbar – unter anderem:

- APT-Konsistenz und `dpkg --audit`.
- Installierte vollständige DEB-Versionen.
- DKMS-Status für den laufenden Host-Kernel.
- Installierte Moduldatei und tatsächlich geladenes NVIDIA-Kernelmodul.
- Erforderlichen Host-Neustart.
- Konflikte mit Nouveau oder Secure Boot.
- Vorhandensein und Berechtigungen der NVIDIA-Gerätedateien.
- Exakten Host-/LXC-Versionsabgleich.
- `nvidia-smi` und NVML.
- `nvtop`, sofern aktiviert oder vorhanden.
- NVENC-/NVDEC-Bibliotheken und optional einen echten FFmpeg-Smoke-Test.
- Wiederherstellung zuvor gestoppter GPU-Dienste und des ursprünglichen LXC-Zustands.

Ist eine notwendige Laufzeitprüfung – etwa vor einem Host-Neustart – noch nicht
möglich, gilt der Ablauf als **ausstehend**. Die Sicherung bleibt erhalten und
kann später über Menüpunkt **8** abgeschlossen werden.

## Automatisierung über Optionen

Das Menü ist der empfohlene Normalbetrieb. Die wichtigsten optionalen Parameter:

| Option | Bedeutung |
|---|---|
| `--update` | Vorhandene NVIDIA-Pakete aktualisieren und pinnen |
| `--update-lxc <CTID>` | NVIDIA-Userspace eines LXC vom Host aktualisieren |
| `--mode auto\|host\|lxc` | Rolle erkennen oder festlegen |
| `--version auto\|<Version>` | Automatische oder explizite Zielversion für Installationen |
| `--kernel auto\|open\|proprietary` | Host-Kernelmodul wählen |
| `--check-only` | Nur lokale Prüfung |
| `--diagnose-all` | Host und NVIDIA-LXC diagnostizieren |
| `--dry-run` | Ablauf schreibgeschützt simulieren |
| `--repair-only` | Sichere Reparatur ohne vollständige Neuinstallation |
| `--rollback <Pfad>` | Geprüfte Sicherung zurückrollen |
| `--resume` | Unterbrochene Transaktion fortsetzen |
| `--uninstall` | NVIDIA vollständig entfernen |
| `--cleanup-backups` | Abgelaufene Sicherungen bereinigen |
| `--retention-days <Tage>` | Aufbewahrungszeit setzen |
| `--pin-packages` | NVIDIA-Pakete nach Installation halten |
| `--stop-gpu-services` | Eindeutig erkannte, freigegebene GPU-Dienste kontrolliert stoppen |
| `--initial-autoremove` | Geprüftes Anfangs-`autoremove --purge` aktivieren |
| `--final-autoremove` | Geprüftes Abschluss-`autoremove --purge` aktivieren |
| `--nvtop auto\|install\|skip` | Verwaltung von `nvtop` steuern |

Die vollständige aktuelle Liste zeigt:

```bash
./nvidia-driver-setup-v2.13.0.sh --help
```

Beispiele:

```bash
# Host-Update auf die neueste geeignete Version
./nvidia-driver-setup-v2.13.0.sh --update --mode host

# Schreibgeschützte Update-Vorschau mit vorhandenem APT-Cache
./nvidia-driver-setup-v2.13.0.sh --update --mode host --dry-run

# LXC 111 vom Proxmox-Host aktualisieren
./nvidia-driver-setup-v2.13.0.sh --update-lxc 111

# Diagnose ohne Paketänderungen
./nvidia-driver-setup-v2.13.0.sh --diagnose-all
```

## Fehlerbehebung

### `nvidia-smi` funktioniert im LXC nicht

Prüfen:

```bash
nvidia-smi
ls -la /dev/nvidia* /dev/nvidia-caps/* 2>/dev/null
dpkg-query -W 'libnvidia*' 'nvidia-smi' 2>/dev/null
```

Häufige Ursachen sind eine abweichende Host-/LXC-Version, fehlende Kontrollgeräte,
noch nicht wirksame LXC-Konfiguration oder ein notwendiger Host-/LXC-Neustart.
Menüpunkt **5** fasst Host und NVIDIA-LXC zusammen; Menüpunkt **6** versucht nur
die dafür vorgesehenen sicheren Reparaturen.

### `nvidia-smi` funktioniert, aber `nvtop` nicht

Menüpunkt **6** oder die Auswahl `nvtop: auto/install` prüft Paket, Bibliotheken
und einen echten NVML-Start. Zusätzlich helfen:

```bash
nvtop --version
ldd "$(command -v nvtop)" | grep -E 'not found|nvidia|cuda'
ldconfig -p | grep -E 'libnvidia-ml|libcuda'
```

### GPU wird noch von einem Dienst verwendet

Im Menü kann gewählt werden, ob das Skript nur melden und abbrechen oder eindeutig
erkannte, freigegebene Dienste kontrolliert stoppen und anschließend wieder starten
soll. Unbekannte oder kritische Prozesse werden nicht blind beendet.

### Alte oder widersprüchliche NVIDIA-Pakete

- Menüpunkt **6** für einen noch grundsätzlich konsistenten Paketstand.
- Menüpunkt **1** für eine vollständige saubere Neuinstallation.
- Menüpunkt **12** nur für einen gesunden, eindeutig aktualisierbaren Bestand.

Bei einem Fehler bleiben die Sicherung und das vollständige Installationslog
erhalten. Diese beiden Pfade sind für eine weitere Analyse am wichtigsten.

## Tests

Die vollständige lokale Test-Suite:

```bash
bash ./test-nvidia-driver-setup-v2.13.0.sh
```

Gezielte Update-Tests:

```bash
bash ./tests/test-nvidia-update.sh ./nvidia-driver-setup-v2.13.0.sh
bash ./tests/test-nvidia-update-transaction.sh ./nvidia-driver-setup-v2.13.0.sh
bash ./tests/test-nvidia-update-lxc.sh ./nvidia-driver-setup-v2.13.0.sh
```

Das mitgelieferte Prüfprotokoll [.test-run-v2.13.0.log](.test-run-v2.13.0.log)
enthält 568 erfolgreiche Syntax-, Funktions- und Simulationstests ohne gemeldeten
Fehler. Die Tests simulieren Linux-Systemgrenzen; sie ersetzen keinen echten Lauf
auf Proxmox, Debian oder Ubuntu mit NVIDIA-GPU.

Die Prüfsumme der lokal verwendeten Skriptdatei kann jederzeit neu berechnet werden:

```bash
sha256sum nvidia-driver-setup-v2.13.0.sh
```

## Sicherheitsgrenzen

- Das Skript verspricht keine fehlerfreie Installation auf beliebigen Systemen.
  Fremde Paketquellen, lokale Runfile-Installationen, Secure Boot, defekte Paketstände
  oder nicht unterstützte Hardware können einen sicheren Abbruch erforderlich machen.
- Fremde beziehungsweise nicht eindeutig zuordenbare NVIDIA-Komponenten werden im
  Update-Modus nicht stillschweigend entfernt.
- `--check-only`, `--attach-only` und `--dry-run` dürfen keine Treiber- oder
  Paketänderungen ausführen und werden zusätzlich durch interne Mutationssperren geschützt.
- Persönliche Medien, Projekte, Docker-Volumes und Anwendungsdaten gehören nicht
  zum NVIDIA-Bereinigungsumfang.
- Ein Rollback stellt den vom Manifest erfassten Systemzustand wieder her; er ist
  kein Ersatz für ein vollständiges externes System- oder VM-Backup.
- Zuvor gestoppte Container werden nicht ohne ausdrückliche Erlaubnis gestartet.
- Alte Sicherungen werden nur nach der konfigurierten Richtlinie bereinigt; aktive
  und noch ausstehende Transaktionen bleiben geschützt.

## Dateien im Projekt

- [nvidia-driver-setup-v2.13.0.sh](nvidia-driver-setup-v2.13.0.sh) – aktuelles Installationsskript
- [AENDERUNGEN-v2.13.0.md](AENDERUNGEN-v2.13.0.md) – technische Änderungen der Version 2.13.0
- [test-nvidia-driver-setup-v2.13.0.sh](test-nvidia-driver-setup-v2.13.0.sh) – vollständige lokale Testsuite
- [`tests/`](tests/) – zusätzliche Verhaltens- und Regressionstests

## Lizenz

Für dieses Projekt liegt im aktuellen Verzeichnis keine Lizenzdatei vor. Vor einer
öffentlichen Veröffentlichung sollte eine passende `LICENSE` ergänzt werden, damit
Nutzungs-, Änderungs- und Weitergaberechte eindeutig geregelt sind.
