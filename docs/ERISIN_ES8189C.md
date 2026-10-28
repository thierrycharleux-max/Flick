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
- **Limites connues** : les listes/menus gardent la disposition téléphone (étirée) avec la
  barre de navigation en bas ; seul le lecteur plein écran a une vraie mise en page paysage.

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
