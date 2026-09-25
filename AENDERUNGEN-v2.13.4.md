# Änderungen in Version 2.13.4

## Auswertung der Logs vom 25.09.2026

- **Host, 16:31:** 615.71.09-2 wurde installiert und DKMS für den laufenden
  Kernel gebaut. Geladen war noch 610.57.04; NVML-Mismatch und ausstehende
  Abschlussprüfung waren bis zum Neustart erwartbar. Exit-Code 2 ist kein
  erfolgreicher Laufzeitabschluss und wurde nicht in Erfolg umgedeutet.
- **LXC 201, Abschlussbericht 16:50:** erfolgreich; der Bericht bestätigt das
  geladene Host-Modul 615.71.09, den passenden Userspace, NVML und nvtop.
- **LXC 102, Update 16:51:** Abbruch am alten Host-Helfer `nvidia-modprobe`.
- **LXC 102, Neuinstallation 16:54:** Abbruch bei der Versionsauswahl für den
  echten `nvidia-smi`-Payload. Beide fehlgeschlagenen LXC-102-Läufe melden
  einen abgeschlossenen Rollback.
- **LXC 124, 16:55:** die bereitgestellte Datei endet beim Sichern von
  `libxnvctrl0`, ohne Fehler, Abschluss oder Exit-Code. Ob dieser Lauf beendet
  wurde, ist damit nicht feststellbar.

## Korrekturen

### Mehrere offizielle Debian-Paketrevisionen

Die saubere Neuinstallation verwendet jetzt dieselbe Versionsauswahl wie das
Update: die höchste vollständige DEB-Version innerhalb der gewählten
NVIDIA-Treiberversion. Epoch und Revision werden mit `dpkg --compare-versions`
verglichen. Die bisherigen Prüfungen auf gemeinsame exakte Paketversionen und
lösbare Abhängigkeiten bleiben aktiv.

Auch nach der Pinning-Einrichtung bleibt die vorab ausgewählte Revision
verbindlich. Ein alter APT-Kandidat kann sie nicht still auf eine ältere
Revision zurücksetzen. Ändert sich die offizielle Zielrevision während der
Vorbereitung, wird vor der Treiberinstallation abgebrochen.

Der [offizielle NVIDIA-Index](https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/)
enthält `nvidia-driver-cuda` für 615.71.09 sowohl als `-1` als auch als `-2`.
Das war bislang beim Neuinstallationspfad fälschlich mehrdeutig und blockierte
bereits das Vorladen von `nvidia-smi`. Nun wird `615.71.09-2` gewählt.

Nur passende, freigegebene Quellen werden berücksichtigt. Eine gleichlautende
gewählte Paketversion aus einer fremden Quelle bleibt ein Abbruchgrund;
falsche Distributionspfade und ähnlich benannte Fremddomains gelten nicht als
offizielles NVIDIA-Repository. Es wird kein Kernelpaket für den Payload im
LXC installiert: das geprüfte Original-DEB dient nur zum Entnehmen der Binärdatei.

### Altes nvidia-modprobe beim LXC-Update

Mit aktivierter automatischer Fehlerbehebung nimmt der Updateplan ein gesund
installiertes altes `nvidia-modprobe` zur Entfernung auf, statt pauschal eine
Neuinstallation zu verlangen. Es bleibt ein gemeinsamer, simulierter und
gesicherter Updatevorgang. Fremdpakete dürfen dabei nicht entfernt und
Host-Helfer nicht erneut installiert werden. Auf dem Host wird `nvidia-modprobe`
weiterhin aktualisiert und behalten.

Ohne automatische Fehlerbehebung sowie bei beschädigten Paketzuständen oder
vorhandenen Kernel-/DKMS-Paketen bleibt die Freigabe verweigert. Dies ist keine
allgemeine erzwungene Bereinigung aller LXC-Pakete.

### Zutreffendere Diagnose

- Die LXC-Übersicht verwendet dieselbe Paketklassifizierung wie die Installation.
  `nvidia-opencl-icd` ist Userspace, kein Kernelpaket. Echte Host-Helfer wie
  `nvidia-modprobe:amd64` werden ebenfalls erkannt; die Spalte heißt `HOSTPAKETE`.
- Die generische Kernelmeldung `module verification failed ... tainting kernel`
  wird nicht mehr als abgelehnter Ladevorgang interpretiert. Explizite
  Schlüsselablehnungen und fehlende Signierer bei aktiviertem Secure Boot
  bleiben Fehler – auch wenn noch ein altes Modul geladen ist.
  Die Unterscheidung entspricht der [Kernel-Dokumentation zur Modulsignatur](https://docs.kernel.org/admin-guide/module-signing.html).
  Im gelieferten Host-Log fehlt das rohe Journal; die konkrete Signaturursache
  auf diesem Host ist daher nicht abschließend belegt.

## Nicht automatisch verändert

LXC 102 hat neben Debian-13-Quellen auch Debian-12-Quellen und ein Intel-Repository
für Ubuntu Jammy aktiv. Diese fremden Paketquellen wurden nicht blind entfernt
oder auf eine andere Distribution umgeschrieben. Sie sollten separat geprüft
werden, falls künftig allgemeine APT-Abhängigkeitskonflikte auftreten.

## Verifikation

Die neuen Regressionstests reproduzieren die Auswahl- und Diagnosefehler gegen
2.13.3 und prüfen die korrigierten Pfade in 2.13.4. Zusätzlich wird der gesamte
LXC-Updateablauf einschließlich Simulation, Download, Holds, Entfernen des
Hosthelfers und Versionsbindung mit isolierten Systemgrenzen simuliert.

Alle Tests bleiben lokal; die echte Paketdatenbank, Hardware und Dienste des
Proxmox-Hosts beziehungsweise seiner LXC werden dabei nicht verändert.
