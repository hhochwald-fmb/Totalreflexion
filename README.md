# Totalreflexion

AirPlay-Empfänger für macOS (ähnlich wie AirServer oder Reflector): iPads spiegeln ihren Bildschirm auf den Mac, auch mehrere gleichzeitig.

## Funktionen

- **Mehrere iPads gleichzeitig.** Jedes Gerät bekommt eine eigene AirPlay-Sitzung mit eigenen Schlüsseln.
- **Passt sich automatisch an.** Wird das iPad gedreht, ändert sich das Seitenverhältnis sofort mit. Das Raster ordnet sich selbst neu.
- **Rahmen:** nur der Bildschirm, ein gezeichneter iPad-Rahmen (randlos oder mit Home-Button, mehrere Farben) oder ein eigenes PNG-Mockup. Den Bildschirmbereich des PNGs erkennt die App automatisch; das Bild dreht sich mit dem iPad mit.
- **Zoom überall:** Pinch auf dem Trackpad, ⌥ + Scrollrad oder ⌘+ / ⌘− / ⌘0. Bei Zoom wird mit zwei Fingern verschoben.
- **Fokus:** Doppelklick auf ein Gerät zeigt es allein, Esc kehrt zurück.
- **Präsentationsmodus** (⇧⌘P): Hintergrund (Farbe, Verlauf oder Bild) füllt den Bildschirm, die iPads liegen darüber und lassen sich frei verschieben und über den Griff unten rechts in der Größe ändern. Die Anordnung wird pro Gerät gespeichert. Ein Doppelklick holt ein Gerät groß nach vorne („Spotlight“). Die Leiste blendet sich automatisch aus.
- **Geräte-Fenster** (⇧⌘G, auch über die Symbolleiste oder das Menüleisten-Symbol): alle verbundenen iPads mit Live-Vorschau. Pro Gerät ein- und ausblenden, Vollbild (bei mehreren Bildschirmen gedrückt halten, um den Bildschirm zu wählen; Esc oder Doppelklick beendet), Rahmen, drehen, stumm, umbenennen, trennen.
- **Eigene Fenster** (wie bei AirServer): Statt des Hauptfensters bekommt jedes iPad ein eigenes randloses Fenster. Verschieben mit der Maus, Größe über die Kanten oder den Griff unten rechts, Doppelklick für Vollbild. Die Position wird pro Gerät gespeichert. Mit „Immer im Vordergrund“ bleiben die iPads über anderen Apps sichtbar, z. B. über einer laufenden PowerPoint-Präsentation. „Anordnen“ verteilt alle Fenster auf dem Bildschirm.
- **Menüleisten-Symbol:** Status, iPads ein-/ausblenden, Modus umschalten, Fenster öffnen. So bleibt die App auch ohne offenes Fenster bedienbar.
- Pro Gerät: Rahmen und Farbe, drehen, stummschalten, umbenennen, trennen (Rechtsklick oder „…“).
- Ton wird mitübertragen (AAC-ELD).
- **Hilfe** (⌘?, „?“ im Geräte-Fenster, Menüleiste): erklärt alle Funktionen, die drei Ansichten und wie man umschaltet. Öffnet sich beim ersten Start einmal von selbst.

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
| `Views/` | Übersicht, Geräte-Fenster, eigene Fenster pro iPad, Präsentation, Rahmen, Zoom, Einstellungen |
| `FairPlay/` | C-Code aus [UxPlay](https://github.com/FDH2/UxPlay) (wird per Skript geladen) |

## Lizenz

Der FairPlay-Teil stammt aus UxPlay und steht unter der GPL-3. Damit steht auch die gesamte App unter der GPL-3 (siehe `Totalreflexion/FairPlay/playfair/LICENSE.md`).
