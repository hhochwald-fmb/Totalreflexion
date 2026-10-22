# Totalreflexion

AirPlay-Empfänger für macOS (ähnlich wie AirServer oder Reflector): iPads spiegeln ihren Bildschirm auf den Mac, auch mehrere gleichzeitig.

## Funktionen

**Bedienung:** Ein Steuerfenster „Totalreflexion“ (⌘1, auch ⌘, oder über das Menüleisten-Symbol) steuert alles. Die Ansichten zeigen nur die iPads; dort wirken nur Maus und Tastatur: ziehen, Doppelklick, Rechtsklick, Zoom, Esc.

- **Drei Ansichten, immer genau eine aktiv** (oben im Steuerfenster):
  - **Raster:** ein Fenster, alle iPads automatisch nebeneinander. Doppelklick zeigt ein iPad allein, Esc kehrt zurück.
  - **Bühne:** Hintergrund (Farbe, Verlauf oder Bild, z. B. eine PowerPoint-Folie) füllt den Bildschirm, die iPads lassen sich frei verschieben und über den Griff unten rechts skalieren. Die Anordnung wird pro Gerät gespeichert. Doppelklick = „Spotlight“. Fixieren und automatisch anordnen im Steuerfenster.
  - **Frei schwebend** (wie bei AirServer): jedes iPad als eigenes randloses Fenster. Verschieben mit der Maus, Größe über Kanten oder Griff, Doppelklick für Vollbild. Optional „Immer im Vordergrund“, z. B. über einer laufenden PowerPoint-Präsentation.
  - Raster und Bühne lassen sich aus dem Steuerfenster auf einen anderen Bildschirm (Beamer) legen und ins Vollbild schalten.
- **iPads einzeln steuern** (Liste im Steuerfenster mit Live-Vorschau): ein- und ausblenden, Vollbild in jeder Ansicht (bei mehreren Bildschirmen gedrückt halten, um den Bildschirm zu wählen), Rahmen, Farbe, drehen, stumm, umbenennen, trennen. Dasselbe Menü per Rechtsklick auf das iPad.
- **Mehrere iPads gleichzeitig.** Jedes Gerät bekommt eine eigene AirPlay-Sitzung mit eigenen Schlüsseln.
- **Passt sich automatisch an.** Wird das iPad gedreht, ändert sich das Seitenverhältnis sofort mit.
- **Rahmen:** nur der Bildschirm, ein gezeichneter iPad-Rahmen (randlos oder mit Home-Button, mehrere Farben) oder ein eigenes PNG-Mockup. Den Bildschirmbereich des PNGs erkennt die App automatisch; das Bild dreht sich mit dem iPad mit.
- **Zoom** in Raster und Bühne: Pinch, ⌥ + Scrollrad oder ⌘+ / ⌘− / ⌘0. Bei Zoom wird mit zwei Fingern verschoben.
- Ton wird mitübertragen (AAC-ELD).
- **Hilfe** (⌘?, „?“ im Steuerfenster): erklärt alle Funktionen und die drei Ansichten. Öffnet sich beim ersten Start einmal von selbst.

## Bauen

```sh
./scripts/fetch-fairplay.sh      # einmalig: FairPlay-Code aus UxPlay laden (GPL-3)
xcodegen generate                # Projektdatei mit den neuen Dateien neu erzeugen
open Totalreflexion.xcodeproj
```

Die Projektdatei wird aus `project.yml` mit [XcodeGen](https://github.com/yonaskolb/XcodeGen) erzeugt. Beim Build läuft SwiftLint (`.swiftlint.yml`). Das App-Icon erzeugt `swift scripts/make-icon.swift Design/AppIcon-source.jpg Totalreflexion/Resources/Assets.xcassets/AppIcon.appiconset`.

## Hinweise

- Beim ersten Start fragt macOS nach dem Zugriff auf das lokale Netzwerk bzw. nach eingehenden Verbindungen. Beides muss erlaubt sein.
- macOS hat einen eigenen AirPlay-Empfänger (Systemeinstellungen › Allgemein › AirDrop & Handoff). Er darf aktiv bleiben, Totalreflexion nutzt einen anderen Port (7100). Damit die iPads nicht zwei Einträge sehen, kann man ihn aber ausschalten.
- Unterstützt wird die Bildschirmsynchronisierung (H.264). Das „Streamen“ einzelner Videos aus Apps (HLS) wird nicht unterstützt.

## Aufbau

| Ordner | Inhalt |
|---|---|
| `AirPlay/` | Bonjour, RTSP-Steuerverbindung, Pairing (CryptoKit), FairPlay-Anbindung, Video-/Audio-Streams |
| `Video/` | Hardware-Decoder (VideoToolbox) und Verteilung der Frames an alle Ansichten |
| `Audio/` | AAC-ELD-Decoder und Wiedergabe |
| `Model/` | Empfänger, Geräte, Einstellungen |
| `Views/` | Steuerfenster, Raster, Bühne, frei schwebende Fenster, Rahmen, Zoom, Hilfe |
| `FairPlay/` | C-Code aus [UxPlay](https://github.com/FDH2/UxPlay) (wird per Skript geladen) |

## Lizenz

Der FairPlay-Teil stammt aus UxPlay und steht unter der GPL-3. Damit steht auch die gesamte App unter der GPL-3 (siehe `Totalreflexion/FairPlay/playfair/LICENSE.md`).
