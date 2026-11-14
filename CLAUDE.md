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
- Animations (relevées image par image, 30 images/s, sur les 4 boucles de la page et sur l'aperçu App Store de Pieoneer ; design Socle plat : ni ombre ni dégradé) :
  ouverture = un anneau fin plus grand de 7 % se resserre sur le centre (ease-out cubique 0,2 s) pendant que les icônes se dévoilent une à une, dans le sens horaire
  depuis le haut (flou transitoire, redressement de 18°, 0,2 s chacune, décalage 0,04 s — `PieReveal`) ; Lanceur et Sélecteur = couronne continue, surlignage arrondi
  (en retrait au Lanceur, qui dépasse de la couronne au Sélecteur) et pastille du nom au centre ; survol immédiat ; Sélecteur = loupe façon Dock (`PieLayout`, ressort 0,07 s) ;
  Contrôleur et Musique = parts séparées par un écart constant ; Contrôleur = icône qui se penche vers le pointeur ; Musique = pochette qui tourne à 33 tours/min pendant
  la lecture ; changement de module = les icônes se redévoilent ; fermeture = fondu de 0,1 s (estimée). Réglage « Animations de l'interface » ; coupées aussi si macOS réduit
  les animations (`Prefs.animationsActive`). Essais : `MPIE_IRIS` (0 à 1) et `MPIE_REVEAL` (secondes) figent une image de l'ouverture dans `--capture-pie`.
- Icône de l'appli : les quatre parts de la barre des menus, en couleurs (ambre, rose, bleu, vert) sur la tuile `bg` Socle ; `scripts/make_icon.swift`, régénérée si `assets/mPIE.icns` manque.
- Données : `~/Library/Application Support/mPIE` (`MPIE_DATA_DIR` pour les essais ; l'édition DEV utilise `mPIE-dev`).
- Essais sans fenêtre : `mPIE --demo --capture-pie <launcher|switcher|controller|music> sortie.png [--hover N]`,
  `--capture-settings <general|trigger|presets|launcher|controller|music|updates> sortie.png`, `--capture-welcome`, `--capture-about` ;
  `--discret-reglages [onglet]`, `--discret-accueil`, `--no-welcome`.
- Build : `./build_app.sh` (installe dans Applications Personnelles) ou `_tools/build_all.sh mPIE` ; `DEV=1 ./build_app.sh` : « mPIE DEV.app » (id `fr.stephan.mpie.dev`, non installée).
- Limites connues : 16 éléments au plus par cercle ; le clic du bouton souris est aussi reçu par l'appli sous le pointeur (d'où la touche à tenir par défaut) ;
  le Contrôleur envoie des codes de touche de la disposition active (⌘. et ⌃` ne sont pas fournis, ils changent selon la disposition) ; la télécommande
  demande l'autorisation Automatisation au premier usage.
