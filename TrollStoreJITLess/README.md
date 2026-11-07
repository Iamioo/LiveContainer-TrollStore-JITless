# LiveContainer TS – experimentell, ohne JIT

Diese Variante ergänzt LiveContainer um einen Signierer auf Basis von
TrollStores fastPathSign. Die enthaltenen Apps und ihre Bibliotheken werden nach
den Änderungen durch LiveContainer auf dem Gerät signiert. Der Start nutzt
keinen JIT-Aufruf und kein `apple-magnifier://`-URL-Schema.

## Voraussetzungen und Grenzen

- Erste Zielversion: **iOS 15.0 bis 16.6.1**, Installation mit TrollStore.
- Nur entschlüsselte ARM64-Apps, die selbst kein JIT benötigen.
- Kein Zertifikat aus SideStore/AltStore erforderlich.
- Ein App-Start gleichzeitig; App-Erweiterungen werden beim Verpacken entfernt.
- Ein erfolgreicher Build beweist noch nicht, dass der Start auf einem iPhone
  funktioniert. Ohne Gerätetest ist diese Version ausdrücklich experimentell.
- Bei Signierfehlern erscheint eine Fehlermeldung; es gibt keinen JIT-Fallback.
- Die Einstellung „Nicht signieren“ wird für diesen Modus ignoriert.
- Die App besitzt zum Signieren die zusätzliche Berechtigung
  `com.apple.private.security.no-sandbox`. Alle enthaltenen Apps laufen im
  selben Prozess und teilen dessen Berechtigungen.

## Build und Installation

1. Auf GitHub unter **Actions → TrollStore JIT-less (experimental)** den Build
   öffnen oder den Workflow auf dem Branch `trollstore-jitless` starten.
2. Nach erfolgreichem Build das Artefakt herunterladen und das ZIP entpacken.
3. `Nextcloud-LiveContainer-TrollStore.tipa` mit TrollStore installieren.
4. Nextcloud öffnen und eine entschlüsselte IPA importieren.
5. In den Einstellungen der importierten App „Launch with JIT“ ausschalten.
6. Die App normal starten.

Diese Variante heißt Nextcloud und verwendet `it.twsweb.Nextcloud`. Die
URL `nextcloudlc://`, die App-Gruppe und die Schlüsselbund-Gruppen sind getrennt
vom normalen LiveContainer. Bestehende Apps werden nicht automatisch übernommen.
Es ist weiterhin LiveContainer, keine Nextcloud-Client-App. Das Icon stammt vom Nutzer.

Bei einem Fehler liegt nach Möglichkeit `Nextcloud-Diagnose.txt` im
App-Ordner in der Dateien-App. Die vorherige Version wurde mit einem Absturz
und „failed to open“ gemeldet. Die genaue Ursache ist ohne Geräteprotokoll noch
nicht bestätigt. Diese Überarbeitung setzt den Datencontainer ausdrücklich,
vermeidet gemeinsame Datenbereiche und erstellt temporäre Signierdateien mit
festen Dateirechten.

Auf einem Mac lässt sich derselbe Build so erstellen:

```sh
git submodule update --init --recursive
python3 TrollStoreJITLess/prepare-icon.py
xcodebuild archive -project LiveContainer.xcodeproj -scheme LiveContainer \
  -archivePath /tmp/LiveContainer.xcarchive -sdk iphoneos -arch arm64 \
  -configuration Release CODE_SIGNING_ALLOWED=NO
python3 TrollStoreJITLess/package.py \
  /tmp/LiveContainer.xcarchive/Products/Applications/LiveContainer.app
```

## Technischer Stand und Prüfung am Gerät

Der [neue Build vom 7. November 2026](https://github.com/Iamioo/LiveContainer-TrollStore-JITless/actions/runs/42350420397)
hat die App samt Signierer erfolgreich kompiliert und verpackt. Die tatsächliche
TIPA wurde auf Namen, Versionsdaten, eigene Identität, Dateien-App-Zugriff und
Container-/Signierberechtigungen geprüft. Das kompilierte Icon wurde aus der TIPA
entnommen und visuell mit der Nutzervorlage verglichen.

Gerätetest der Fehlerbehebung: **noch nicht ausgeführt**. Der gemeldete Absturz
ist deshalb noch nicht nachweislich behoben. Bei einem erneuten Fehler bitte den
vollständigen Fehlertext und gegebenenfalls `Nextcloud-Diagnose.txt` bereitstellen.

SHA-256 der neuen TIPA:
`532d5eb959db6a7058c858431a7dbed6756b86589fe4dc4db14eb80112014755`.

LiveContainer-Basis: `9108ae624ea001f7d7696d48407f890b48fa2653`.
Die normale Variante behält ihren bisherigen Signier- und Startweg. Erst der
Verpackungsschritt setzt `LCTrollStoreJITLess` und fügt den Signierer hinzu.

Zum Prüfen auf einem Gerät: eine einfache ARM64-App importieren, starten,
LiveContainer vollständig schließen und nochmals starten. Es darf weder eine
Lupe noch ein JIT-Helfer aufgehen. Danach eine App mit eingebetteten Frameworks
und optional einem eigenen Tweak prüfen. 32-Bit-Apps und „Launch with JIT“ müssen
eine verständliche Fehlermeldung liefern. Diese Gerätetests wurden bei der
Erstellung nicht ausgeführt.

## Quellen und Lizenzen

- [LiveContainer](https://github.com/LiveContainer/LiveContainer), AGPL-3.0.
- [TrollStore](https://github.com/opa334/TrollStore), Commit
  `88424f683b2a08f34a3f88985f790f97d84ce1df`, MIT-Lizenz.
- [ChOma](https://github.com/opa334/ChOma), Commit
  `964023ddac2286ef8e843f90df64d44ac6a673df`, MIT-Lizenz.

Der Build holt diese festgelegten Quellen und legt sie samt Lizenzen in
`TrollStoreSignerSources` innerhalb der App ab. `Signer.m` ist der neue Adapter;
TrollStores Signaturverfahren wird aus dessen Originalquellen gebaut.
