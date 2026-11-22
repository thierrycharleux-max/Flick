# Flick sur Erisin ES8189C (Android 9, 1024×600)

Fork adapté à l'autoradio Android Erisin ES8189C. Base : Flick `0.23.0-beta.1+30`
(commit `230c5be`). Package installé : `com.mossapps.flick.erisin`.

## Ce qui change par rapport à l'original

- **Paysage fixe** : l’activité est verrouillée en paysage par le manifeste et
  `MainActivity` pour la dalle 1024×600, afin que Flutter reçoive directement les
  bonnes dimensions.
- **Lecteur plein écran** : en paysage, pochette/titre/paroles à gauche, forme d'onde
  et commandes à droite (`full_player_screen.dart`). Le portrait reste identique.
- **Build** : plugin Google Services + Firebase BoM retirés (rien dans le code ne les
  utilisait, et le build échouait sans `google-services.json`). Signature debug si
  `key.properties` est absent.
- **Package distinct** : cohabite avec la version Play Store, jamais écrasé par elle.
- **ABI** : `armeabi-v7a` + `arm64-v8a` seulement (APK plus léger).
- **Valeurs par défaut allégées** : visualiseur FFT et pochettes animées désactivés
  (Réglages pour les réactiver). Moteur audio par défaut : ExoPlayer (standard Android).

## Compiler sans rien installer (GitHub Actions)

1. Dans [ce fork](https://github.com/thierrycharleux-max/Flick), ouvrir **Actions**
   et activer les workflows si GitHub le demande.
2. **Build APK (Erisin ES8189C) → Run workflow**, branche `main`.
3. Après une compilation réussie, télécharger l'artefact
   `flick-erisin-es8189c-apk` (zip contenant l'APK).

Optionnel : secrets `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`
pour conserver la même clé de signature entre les builds. Sans ces secrets, chaque
runner neuf génère sa propre clé debug : une mise à jour signée avec une autre clé
nécessite de désinstaller l'ancienne application, ce qui efface ses données.
Deux builds signés avec la même clé peuvent être installés l'un sur l'autre.
Le workflow est manuel ; son ajout au dépôt ne constitue pas un test de compilation
sur GitHub Actions.

## Compiler en local

Prérequis utilisés pour l'APK locale : Flutter `3.47.8`, Java 17, Rust + cibles
`aarch64-linux-android` et `armv7-linux-androideabi`, Android SDK (compileSdk 37)
et NDK `28.2.13676358`, `ANDROID_NDK_HOME` défini.

La génération des bindings natifs doit disposer des en-têtes Android. Définir
`BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android` et
`BINDGEN_EXTRA_CLANG_ARGS_armv7_linux_androideabi` avec la cible correspondante
(`--target=aarch64-linux-android26` ou `--target=armv7-linux-androideabi26`) et
`--sysroot=<NDK>/toolchains/llvm/prebuilt/<hôte>/sysroot`. Si le chemin du NDK
contient des espaces, utiliser un lien symbolique temporaire sans espaces pour
le sysroot. Le workflow configure ces variables sur le runner Linux.

```bash
flutter pub get
flutter build apk --flavor full --release --target-platform android-arm,android-arm64
```

Sortie : `build/app/outputs/flutter-apk/app-full-release.apk`.

## Installer sur l'autoradio

- Clé USB : copier l'APK, l'ouvrir depuis le gestionnaire de fichiers, autoriser les
  sources inconnues. Ou : `adb install -r app-full-release.apk`.

## À vérifier sur l'appareil

```bash
adb shell getprop ro.product.cpu.abilist   # armeabi-v7a seul = Android 32 bits
adb shell wm size                          # attendu : 1024x600
adb shell wm density                       # densité utilisée pour le dimensionnement en dp
```

- **Touches volant** : vérifier que l'autoradio transmet les commandes
  Suivant/Précédent/Lecture-Pause à la MediaSession de Flick ; cette intégration
  n'a pas été validée sur l'Erisin.
- **Fluidité** : si ça rame, Réglages → désactiver animations et fond animé.
- **Disposition paysage** : les albums et leur détail disposent maintenant de
  leur propre disposition compacte ; les autres listes et menus restent adaptés
  depuis leurs vues téléphone.

## Validation de l'APK locale du 28 octobre 2026

- Compilation `full --release` réussie ; analyse Flutter sans erreur, avec
  29 diagnostics de niveau information.
- APK : `0.23.0-beta.1+30`, minSdk 26, bibliothèques ARM32/ARM64 seulement,
  signature APK v2 avec la clé debug locale.
- Installation et lancement vérifiés sur émulateur ARM64 Android 10, 1024×600 ;
  l'activité est au premier plan en `SCREEN_ORIENTATION_LANDSCAPE`, sans erreur
  fatale ni rejet de surface dans le journal du lancement observé.
- SHA-256 de `Flick-Erisin-ES8189C-0.23.0-beta.1+30.apk` :
  `0a5196ed7d0321b3353cbf4e6fa2d02ad2a923f00c24ef4ee8c1bb859ef96e95`.

L'Erisin physique, Android 9, les sorties audio, les touches volant et l'endurance
restent à valider sur l'appareil. Les contrôles sur émulateur ne les établissent pas.

## Mise à jour Erisin 0.23.0-erisin.1+31 (13 novembre 2026)

- En paysage, le mini-lecteur et la navigation partagent une barre compacte
  réservée sous la bibliothèque et les pages de détail. Les cartes de la vue
  orbitale restent dans leur zone, même lorsque la densité de l'écran augmente.
- Les lecteurs flottants et les fenêtres automatiques de séries/succès ne
  s'affichent plus en paysage. Le bandeau de connexion est masqué en paysage.
- Le mode audio direct pour DAC USB, ses invitations et ses réglages sont
  désactivés ; les anciens choix USB sont ignorés. Le stockage USB reste utilisable.
  L'audio normal passe par Android, qui conserve le choix de sa route système.
- APK signé avec la même clé locale que la version `0.23.0-beta.1+30`.
  Une mise à jour peut donc conserver les données de l'application si la version
  installée possède bien cette signature.
- Essais réalisés sur émulateur Android 10 à 1024×600 : mise à jour depuis
  l'APK précédent avec des préférences USB et lecteur flottant préexistantes,
  conservation de la bibliothèque de test, navigation, recherche et lecture
  M4A via la sortie Android partagée. Densités 160 et 240 vérifiées.
- Ces essais ne remplacent pas une vérification sur l'Erisin Android 9 réel :
  le son physique, la densité exacte et les commandes de l'autoradio restent
  à confirmer sur place.


## Mise à jour Erisin 0.23.0-erisin.2+32 (14 novembre 2026)

- Masquage des barres système demandé nativement à Android au lancement et au
  retour au premier plan, avec rétablissement après fermeture du clavier.
- Bibliothèque : en-tête compact, recherche intégrée sur demande, davantage de
  hauteur réservée aux pochettes. Albums : suppression du résumé « Your
  collection at a glance » et du titre « Collection » redondant.
- Détail album : pochette et actions fixes à gauche, pistes défilantes à droite.
  Les commandes sont accessibles dès l'ouverture. Les petites hauteurs utilisent
  un en-tête plus court avec commandes fixes.
- Un seul retour au morceau en cours : pastille fixe en haut, sans second bandeau
  du morceau en bas. La navigation Menu / Songs / Settings reste en bas.
- Lecteur : pochette carrée à gauche par défaut, commandes visibles à droite.
  Une migration unique applique ce défaut aux anciennes préférences, puis les
  choix ultérieurs de l'utilisateur sont conservés.
- Ouverture des albums : une seule cible tactile par carte et protection contre
  les doubles ouvertures ; réutilisation des regroupements déjà chargés et
  report du travail secondaire après la transition.
- Diagnostic audio : les sondages natifs Rust synchrones ne sont plus demandés
  pendant la lecture ExoPlayer. Cela retire une source de contention possible,
  sans établir la cause de la fenêtre « Flick ne répond pas » photographiée.
- Bibliothèque : une analyse rapide des dossiers déjà sélectionnés est lancée
  une seule fois, deux secondes après le démarrage. Aucun déclenchement au simple
  retour dans l'application, ni périodique ou lié à MediaStore/USB. Les analyses
  manuelles restent disponibles. Les fichiers inchangés utilisent le cache.
- Une clé absente ou un dossier SAF dont l'accès est incertain conserve son
  catalogue. Un dossier SAF réellement entièrement vidé conserve également ses
  anciennes entrées ; le retirer de la bibliothèque permet de les supprimer.
- Le chemin audio direct vers un DAC USB reste désactivé ; le stockage USB reste
  utilisable et la lecture conserve la sortie audio gérée par Android.

Validation locale : suites de tests d'affichage, de diagnostics, de scanner et de
coordination réussies ; analyse Flutter sans erreur (29 informations préexistantes).
Sur émulateur Android 10, 1024×600 à 240 dpi : mise à jour depuis la version 31
sans perte de bibliothèque, commandes du lecteur et de l'album immédiatement
visibles, pastille haute unique, recherche intégrée et barres système masquées
après fermeture du clavier. La MediaSession signale une lecture active normale.
Ajout d'un sixième album dans le dossier SAF de test : dix titres conservés au
retour au premier plan, puis douze détectés automatiquement au démarrage suivant.
Aucune erreur fatale ni ANR observée pendant ces vérifications ponctuelles.
Les captures de démonstration utilisent des albums synthétiques, sans modifier
la musique de l'utilisateur. L'Erisin Android 9 physique n'est pas connecté.


Livraison vérifiée : APK `0.23.0-erisin.2+32`, ARM32/ARM64, minSdk 26,
signature locale identique à la version 31. Copie temporaire sur MBUX contrôlée
par SHA-256 avant renommage, puis contrôle du fichier final avant retrait de la
version 31. Clé éjectée. SHA-256 :
`4775485c4fd56703e3d08364c7bb2b9a228fb0139fbf2836b2d4db262496a5d8`.


## Mise à jour Erisin 0.23.0-erisin.3+33 (16 novembre 2026)

### Carte microSD et nouveaux albums

La sélection d'un dossier parent (ou de la racine de la carte) remplace désormais
les anciens dossiers d'albums qu'il contient, au lieu de refuser leur chevauchement.
Une transaction conserve les identifiants des morceaux, leurs modifications,
les fenêtres CUE, et donc les références des favoris / playlists / historique.
Les chemins SAF sont adaptés au nouveau droit d'accès ou au chemin brut utilisé
par le scanner ; les anciens droits restent disponibles pour les files restaurées.
La modification des racines attend les scans déjà en cours.

Après installation, choisir une seule fois **Réglages → Bibliothèque → Ajouter
un dossier → racine de la microSD**, puis autoriser l'accès. Il n'est pas
nécessaire de retirer d'abord chaque ancien dossier. Le scan inclut alors les
nouveaux sous-dossiers, même s'ils n'ont jamais été ajoutés manuellement.
L'actualisation automatique reste limitée au démarrage de l'application.

### Blocage au début de lecture

Le décodage du fichier de pochette de notification était synchrone dans le
service Android principal. Il est déplacé sur un exécuteur d'arrière-plan ;
la notification et le démarrage du service n'attendent plus cette lecture.
Une pochette ancienne ne peut pas remplacer celle d'un nouveau morceau, et les
résultats reçus après destruction du service sont ignorés.
Cette contention possible est retirée. Aucun journal ANR de l'Erisin physique
n'est disponible : cela n'établit pas la cause exacte des blocages rapportés.

### Vérifications et livraison

- 47 tests Flutter ciblés réussis, dont un test avec la vraie base Isar pour
  la sélection d'une carte remplaçant un dossier album sans perdre l'identifiant,
  les éditions et une fenêtre CUE ; identifiant favori conservé.
- Deux tests JVM du chargeur de pochettes : absence de lecture sur l'appelant,
  résultat périmé ignoré, service détruit protégé.
- Émulateur Android 10, 1024×600 : refus de la version 32 reproduit, mise à jour
  vers 33 sans désinstallation, choix du parent accepté ; bibliothèque passée
  de deux à six titres, dont un album jamais sélectionné auparavant. Ajout
  d'un autre album après fermeture : huit titres détectés au lancement suivant.
- Lectures AAC et ALAC synthétiques et cinq changements successifs de morceau :
  MediaSession active, interface réactive, aucune erreur fatale / ANR observée.
- Mise en page et blocage sur l'Erisin Android 9 réel : à confirmer sur appareil.
- APK ARM32/ARM64, minSdk 26, même certificat local que la version 32.
- Copie sur MBUX vérifiée avant retrait de la version 32, sauvegardée localement.
- SHA-256 : `be1825b47171efa03ad2a306a9975f9b68122b2aa66c661972990c076977d659`.


## Mise à jour Erisin 0.23.0-erisin.4+34 (16 novembre 2026)

Disposition du lecteur paysage adaptée à la maquette validée : grande pochette
carrée encadrée à gauche ; titre du morceau en haut à droite ; album et artistes
réunis dans un petit encadré placé sous le titre. La forme d'onde, les durées et
les commandes occupent la partie inférieure droite. Le bandeau supérieur perd
ses marges verticales dans ce mode, en conservant les dimensions des boutons.
Les raccourcis et informations techniques restent disponibles sous la pochette.
Les liens de navigation vers l'album et l'artiste sont conservés dans l'encadré.
Les modes paroles / visualisation et la présentation portrait sont conservés.

Vérification : 16 tests d'affichage et de compatibilité réussis ; après le dernier
ajustement de titre et de marges, les six tests ciblés repassent. La composition
est contrôlée en 1024×600, densités 160 et 240, texte normal et agrandi à 130 %,
avec titre long, album, artistes et raccourcis occupant deux rangées.
Analyse ciblée sans erreur (une information préexistante). Moteur audio et
actualisation au lancement inchangés par cette version.


APK final installé et observé sur émulateur : mise à jour sans désinstallation,
bibliothèque de test conservée ; lecteur contrôlé en densité 240 après le dernier
ajustement, commandes visibles, MediaSession en lecture et aucun débordement
signalé dans le journal observé. Les images de test utilisent une pochette et
un intitulé de démonstration ; aucune musique de l'utilisateur n'est modifiée.
Copie MBUX vérifiée avant retrait de la version 33 (sauvegardée localement).
Même certificat local ; SHA-256 : `8d72de6a21d7c155d369af08fc0f6612c1230a0e123a3f15cd30e5c27d864192`.


## Mise à jour Erisin 0.23.0-erisin.5+35 (17 novembre 2026)

Ajout du français : catalogue complet de 2 519 messages, pluriels adaptés et
choix « Français » dans les réglages de langue. En l’absence de choix enregistré,
l’édition Erisin démarre en français, même si Android est en anglais. Un choix
explicite antérieur (autre langue ou langue du système) est conservé. Les titres,
artistes et albums issus des fichiers musicaux ne sont pas traduits.

Les commandes de notification reçoivent également les libellés de la langue
choisie dans Flick, sans lecture supplémentaire du stockage au début d’un titre.
La disposition du lecteur, la sortie audio Android et l’actualisation de la
bibliothèque au lancement restent inchangées.

Vérifications : 103 tests de traduction et d’affichage réussis ; contrôle des
clés et paramètres du catalogue français, des pluriels, de la préférence
persistante et des libellés de notification. Analyse ciblée sans anomalie.

Après harmonisation des compteurs singulier/pluriel dans les vues Titres et Albums,
13 tests ciblés supplémentaires réussissent. Installation par-dessus la version
34 sur émulateur Android 10 (1024×600), ouverture en français sur un système
anglais, analyse d’un dossier de démonstration et lecture WAV vérifiées. Les
commandes natives de notification sont également en français. Aucun essai
sur l’Erisin physique n’a été effectué pour cette traduction.

L’outil local `graphify` n’est pas installé ; la mise à jour du graphe n’a pas
pu être exécutée. Aucun fichier de graphe n’est livré avec le fork.


## Mise à jour Erisin 0.23.0-erisin.6+36 (17 novembre 2026)

Révision de 86 messages français dans le contexte musical : « lecteur »,
« Lire ensuite », « écoutes », « pochette », « barre de progression »,
« origine de l’extraction », etc. Les noms des morceaux restent inchangés.

Sur le moteur Android utilisé par cette adaptation : fondu de 240 ms à la pause
et à la reprise ; fondu sortant de 160 ms avant une sélection manuelle de titre,
puis remontée de 240 ms. Un chargement se fait à volume nul pour éviter une
attaque au volume maximal. La courbe douce ne modifie ni le volume mémorisé,
ni la fréquence d’échantillonnage. Les mises à jour de volume et ReplayGain
sont multipliées par le gain temporaire, y compris pendant une transition.

Le fondu enchaîné automatique est activé par défaut pour 0,6 seconde, si aucun
choix n’avait été enregistré. Un réglage antérieur explicite est conservé ;
l’option et sa durée restent modifiables dans les réglages audio. Pause ou
sélection manuelle annulent la préparation du successeur ; aucune lecture
différée ne doit redémarrer après un arrêt. L’égaliseur reste rattaché à la
session du lecteur actif lors d’un fondu enchaîné. Les chemins Rust et DAC
externe ne reçoivent pas ces nouveaux fondus ; le DAC direct reste désactivé.

Validation : 169 tests ciblés réussis ; après la dernière protection contre
un échec de réglage du gain, les 10 tests du moteur de fondu repassent. Ces tests
couvrent pause/reprise, chargement silencieux, volume nul, changement de volume,
annulation d’une préparation, pause pendant un fondu, arrêt et destruction.

APK ARM32/ARM64 installé par-dessus la version 35 sur émulateur Android 10
1024×600, densité 240 : bibliothèque conservée ; enchaînement automatique entre
deux WAV, précédent/suivant, pause et reprise via commandes média observés.
Aucune exception fatale ni erreur de gain relevée dans le journal de ces essais.
Les sept tests du catalogue français et des invariants repassent après la
dernière correction de vocabulaire. Émulateur arrêté à la fin des vérifications.
Le rendu audible sur l’Erisin réel reste à confirmer.

Copie MBUX vérifiée avant retrait de la version 35, sauvegardée localement.
Même certificat ; SHA-256 : `91e935bbf9af9edf725a4b22eddacefac238169d5d1d5bc50e27b36d44db42a4`.


## Contrôles GitHub après la version 36 (17 novembre 2026)

Le contrôle de fraîcheur signalait des fichiers générés périmés, alors que le
seul fichier modifié était `pubspec.lock`. La CI flottante utilisait Flutter
3.50.0 au lieu du 3.47.8 de l’APK, entraînant sept changements de dépendances.
La CI est alignée sur 3.47.8 et vérifie désormais le verrouillage des dépendances
dès `pub get --enforce-lockfile`. Le contrôle de fraîcheur reste actif.

La suite complète est adaptée à la suppression du DAC externe : les tests
vérifient que l’activation directe est refusée sans requête USB, changement
de route ni modification de volume. Les écrans UAC2 amont conservés dans les
sources restent absents de la recherche des réglages. Deux écritures de cache
Apple Music/pochettes sont attendues avant de signaler la fin d’une résolution,
ce qui empêche une lecture ou une actualisation immédiate de retrouver l’ancien
contenu. Enfin, les compteurs de pistes/disques manquants conservent le chiffre
zéro avec la règle française de pluriel.


## Mise à jour Erisin 0.23.0-erisin.7+37 (22 novembre 2026)

Le retour de l’Erisin a établi que le moteur sélectionné était Haute qualité
(Rust/Oboe). Les fondus de la version 36 couvraient seulement Standard/Android :
ils ne s’appliquaient donc pas à ce chemin.

Ajout d’un gain PCM temporaire dans le rendu natif Rust, après les traitements
audio. Il multiplie les échantillons sans modifier le volume mémorisé, sa courbe,
ReplayGain ou la fréquence d’échantillonnage. Il est conservé lorsqu’un nouveau
format entraîne la préparation d’un autre flux audio. Les sorties bit-perfect
ne reçoivent pas ce gain ; l’accès DAC externe reste désactivé.

En Haute qualité, pause/reprise : 400 ms ; changement manuel : baisse de 240 ms
avant le chargement, puis remontée de 400 ms. La remontée attend le démarrage
effectif de la source demandée, même si un ancien état Playing arrive en retard.
Pause et arrêt annulent les remontées différées. Les commandes ne sont pas
bloquées en attendant la fin du décodage d’une source en cours de chargement.

Validation : 1 112 tests Flutter et 337 tests Rust réussis. Le test natif de
rendu compare les échantillons PCM à plusieurs gains temporaires, y compris
zéro et 0,0001, et aux volumes utilisateur 0, 0,1, 0,4, 1 et 1,5. Les tests
Haute qualité couvrent pause/reprise, titre suivant, chargement lent, état
Playing périmé, volume nul, arrêt, destruction et erreur du contrôle de gain.
Les tests Rust locaux utilisent un dossier temporaire de projet canonique
pour éviter le lien symbolique /var → /private/var propre à macOS.

APK installé par-dessus la version 36 sur émulateur Android 10, 1024×600 :
bibliothèque conservée, moteur Haute qualité sélectionné et route effective
RUST_OBOE confirmée dans les diagnostics. Pause, reprise et sélection du titre
suivant contrôlées ; aucune erreur du nouveau contrôle de gain ni exception
fatale relevée. Émulateur fermé après les essais. L’écoute sur l’Erisin physique
reste à confirmer.

APK ARM32/ARM64, même certificat que la version 36.
SHA-256 : `9d8f64998893716b7c6c315ebc2e52287bb65372b29888231b7799bd28510796`.
