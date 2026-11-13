# mPIE

Clone personnel de Pieoneer (App ahead) : un menu circulaire à quatre modules — Lanceur (applis, dossiers, fichiers), Applis ouvertes,
Contrôleur (raccourcis des autres applis) et Musique (Apple Musique et Spotify). Swift, sans bac à sable, sans fenêtre au lancement (`LSUIElement`).

- Interface : suivre le design system Socle (standard : plat, sombre, dense) — https://claude.ai/artifact/TkNj2Y6SQGZwT6EyME92Ah.
  `Sources/mPIE/Socle.swift`, `Updater.swift` et `UpdaterView.swift` sont recopiés par `build_app.sh`, ne pas les modifier ici.
  Maquettes validées : `maquettes/index.html`.
- Textes : `Resources/<langue>.lproj/Localizable.strings` (fr d'abord, puis en, es, it). `swift test` vérifie mêmes clés, mêmes `%`, et que chaque clé du code existe.
- Cœur testable (`Sources/mPIECore`) : `PieGeometry` (part visée), `LauncherStore`, `ControlStore` + `ControlDefaults` (jeux de raccourcis fournis),
  `MusicScripts`, `Presets` (lanceurs de départ, profils de déclenchement), modèles.
- Application : `PieController` (panneau sans bord non activant, visée à 90 Hz sur `NSEvent.mouseLocation`, moniteurs clavier/souris/molette),
  `PieViews` (SwiftUI), `Keys` (Carbon : appui ET relâchement ; souris : bouton milieu/4/5 ; `KeySender` en `CGEvent`, autorisation Accessibilité),
  `MusicRemote` (osascript hors fil principal, jamais lancé si le lecteur est fermé), `AppTracker`, `SettingsView` (7 onglets), `Welcome`, `About`.
- Données : `~/Library/Application Support/mPIE` (`MPIE_DATA_DIR` pour les essais ; l'édition DEV utilise `mPIE-dev`).
- Essais sans fenêtre : `mPIE --demo --capture-pie <launcher|switcher|controller|music> sortie.png [--hover N]`,
  `--capture-settings <general|trigger|presets|launcher|controller|music|updates> sortie.png`, `--capture-welcome`, `--capture-about` ;
  `--discret-reglages [onglet]`, `--discret-accueil`, `--no-welcome`.
- Build : `./build_app.sh` (installe dans Applications Personnelles) ou `_tools/build_all.sh mPIE` ; `DEV=1 ./build_app.sh` : « mPIE DEV.app » (id `fr.stephan.mpie.dev`, non installée).
- Limites connues : 16 éléments au plus par cercle ; le clic du bouton souris est aussi reçu par l'appli sous le pointeur (d'où la touche à tenir par défaut) ;
  le Contrôleur envoie des codes de touche de la disposition active (⌘. et ⌃` ne sont pas fournis, ils changent selon la disposition) ; la télécommande
  demande l'autorisation Automatisation au premier usage.
