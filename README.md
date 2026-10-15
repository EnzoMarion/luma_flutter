# Luma · Application Flutter et panneau LED

Prototype pour **Android et iOS**, adapté aux parcours couleur, rouge et réglages de la maquette [Projet LED IoT](https://www.figma.com/design/GhrvxUS2ZNhR30qS5GcRi5/Projet-LED-IoT?node-id=13-415).

## Ce qui est livré

- Application Flutter en français : connexion, choix des profils RGB/rouge, états de connexion, message et palette couleur, six pictogrammes, réglages, effacement et confirmations.
- Mode démonstration clairement identifié, sans émission Bluetooth.
- Aperçu de la matrice et couleurs sélectionnées, texte ASCII jusqu'à 60 caractères.
- Luminosité sur 16 niveaux, défilement automatique/fixe/permanent, trois vitesses, deux sens, allumage et effacement.
- Transport BLE Android/iOS avec fragments de 20 octets, commandes sérialisées et confirmation du firmware.
- Firmware ESP32-WROOM-32 pour MAX7219 rouge ou WS2812B RGB 8 × 8, configuration PlatformIO et test Arduino minimal.
- Police Manrope embarquée, utilisable hors ligne, licence dans `assets/fonts/OFL.txt`.

**État réel de validation :** la base du prototype a fait l'objet de contrôles Dart et de tests autonomes du protocole. Les parcours Figma et le profil WS2812B ont été ajoutés ensuite sans compilation ni exécution ; Flutter n'a pas pu être téléchargé dans l'environnement de création. Les dossiers Android/iOS/web sont donc **à générer avec le script fourni** ; aucune compilation Flutter, APK, IPA, exécution visuelle Flutter ou validation matérielle n'est certifiée. Voir [VALIDATION.md](VALIDATION.md).

La reproduction est faite par inspection visuelle de Figma ; les détails de style peuvent différer. Les deux profils matériels sont disponibles dans l'application. Le firmware est compilé pour le profil rouge par défaut ; passez `LUMA_PANEL_COLOR` à `1` pour le WS2812B RGB.

## Démarrer sur votre Windows avec Android Studio

1. Installez le [SDK Flutter stable](https://docs.flutter.dev/install/manual), ainsi que les plugins **Flutter** et **Dart** d'Android Studio. Android Studio seul ne fournit pas le SDK Flutter.
2. Ajoutez `flutter/bin` à votre PATH et ouvrez un nouveau terminal.
3. Extrayez l'archive dans un chemin court, par exemple `C:\dev\luma_flutter`.
4. Depuis ce dossier, exécutez :

```powershell
flutter doctor
dart tool/setup.dart
flutter analyze
flutter test
flutter run
```

Le script crée les projets natifs officiels à partir de **votre version de Flutter**, conserve les fichiers Dart de l'application et configure les déclarations Bluetooth Android/iOS. Il ne remplace pas les dossiers de plateformes déjà existants. L'identifiant de départ est `fr.projetled.luma`.

Ouvrez **le dossier luma_flutter qui contient pubspec.yaml** dans Android Studio, puis sélectionnez votre téléphone Android. Activez le débogage USB pour les tests par câble et acceptez sa demande de connexion. Utilisez le bouton « Essayer sans panneau · Démonstration » pour découvrir les écrans sans ESP32. Après la recherche simulée, touchez le panneau de démonstration proposé.

Les tests BLE réels se font sur un téléphone. L'émulateur sert à vérifier l'interface. Si Android Studio ne reconnaît pas Flutter, renseignez le chemin du SDK dans ses réglages Flutter.

Après validation, un APK de test peut être créé avec `flutter build apk --debug`. Une version de distribution exige votre configuration de signature.

## Votre collègue sur Mac avec Xcode

Votre collègue utilise **le même projet Dart**, avec Flutter installé en plus de Xcode. Partagez le dossier du projet via votre dépôt Git ou cette archive ; utilisez la même version de Flutter et conservez `pubspec.lock` une fois les dépendances résolues.

```sh
flutter doctor
dart tool/setup.dart
flutter analyze
flutter test
flutter run
```

Branchez un iPhone. Dans `ios/Runner.xcworkspace`, choisissez une équipe dans **Signing & Capabilities**, adaptez au besoin l'identifiant de bundle, puis activez le mode développeur de l'iPhone. Suivez les éventuels prérequis indiqués par `flutter doctor`, notamment CocoaPods si votre configuration le requiert. Ne lancez pas seulement les fichiers Dart dans Xcode : Flutter construit l'application, Xcode gère la partie iOS et la signature.

La compilation iOS se fait sur le Mac. [Guide Flutter officiel iOS](https://docs.flutter.dev/platform-integration/ios/setup).

## Architecture

| Fichier/dossier | Responsabilité |
|---|---|
| `lib/main.dart` | Écrans, thème, navigation et interactions |
| `lib/controller.dart` | Recherche, connexion, favoris et état de l'application |
| `lib/transport.dart` | Contrat de transport et simulation |
| `lib/ble_transport.dart` | Permissions, GATT, fragmentation et confirmations |
| `lib/protocol.dart` | UUID, validation, réglages et bitmaps |
| `lib/pixel_preview.dart` | Rendu local des LED |
| `firmware/src/` | Programme ESP32 : BLE, affichage et boucle principale séparés |
| `tool/setup.dart` | Génération Android/iOS/web et déclarations Bluetooth |
| `test/` | Tests Flutter du protocole et du parcours de démonstration |

## Premier essai avec l'ESP32

1. Vérifiez le câblage et testez une seule matrice avec `firmware/minimal/MatrixTest.ino`. Arduino IDE doit placer ce sketch dans un dossier nommé `MatrixTest` lorsqu'il le propose. Installez MD_Parola et MD_MAX72XX, et sélectionnez ESP32 Dev Module avec Arduino-ESP32 2.0.17.
2. Pour le programme complet, ouvrez `firmware/` comme projet PlatformIO. Il cible explicitement Arduino-ESP32 2.x via la plateforme épinglée ; ne migrez pas vers 3.x sans adapter et revalider les API BLE.
3. Profil rouge : ajustez `MODULES` à 1, puis 8 dans `firmware/include/config.h`. Le type `FC16_HW` est une hypothèse à confirmer. Profil couleur : gardez `RGB_WIDTH`/`RGB_HEIGHT` à 8 et branchez DIN sur GPIO4 ; dans `firmware/platformio.ini`, réglez `-DLUMA_PANEL_COLOR=1`.
4. Compilez et téléversez : `pio run`, puis `pio run --target upload`. Ouvrez le port série à 115200 bauds avec `pio device monitor`.
5. L'écran affiche `MERCI` au démarrage ; `Luma rouge` ou `Luma couleur` devient visible en BLE selon le profil.
6. Dans l'application, « Connecter le panneau », puis touchez le périphérique détecté. Envoyez `BONJOUR`, puis un texte de plus de 10 caractères.
7. Vérifiez un pictogramme, les deux sens, l'intensité, l'extinction, le rallumage et l'effacement.

Le firmware ne dépend pas de Wi-Fi ni d'un serveur. La reconnexion est manuelle : après une coupure, relancez la recherche. Le texte saisi est conservé pendant la session, les favoris persistent entre lancements. Les réglages et le dernier message du panneau ne sont pas sauvegardés dans sa mémoire flash.

## Limites connues

- Les réglages montrés sont des valeurs à appliquer, pas une lecture de l'état physique du panneau. Après reconnexion, appuyez sur « Appliquer les réglages » pour les synchroniser.
- « Message reçu » signifie que le firmware a accepté et appliqué la commande. Si le panneau est éteint dans les réglages, il faut le rallumer pour voir le contenu.
- L'aperçu utilise une petite police 5 × 7 ; le panneau utilise la police MD_Parola. Les glyphes/largeurs peuvent différer. Certaines ponctuations apparaissent comme `?` dans l'aperçu mais sont transmises en ASCII au panneau. Les lettres sont prévisualisées en majuscules.
- En mode fixe, un texte dépassant la largeur peut être tronqué. L'auto se déclenche selon le seuil de 10 caractères de la maquette, pas selon la largeur réelle de chaque glyphe.
- La pause de l'aperçu concerne uniquement l'animation du téléphone.
- Prototype BLE sans appairage sécurisé ni authentification : un autre téléphone proche connaissant le protocole peut commander un panneau libre. À renforcer avant un usage hors démonstration.
- Le contrôle BLE est au premier plan ; le fonctionnement en arrière-plan n'est pas implémenté.

## Sources techniques

- [Flutter : installation](https://docs.flutter.dev/install/manual)
- [Flutter Reactive BLE : permissions et API](https://pub.dev/packages/flutter_reactive_ble)
- [permission_handler](https://pub.dev/packages/permission_handler)
- [MD_Parola](https://github.com/MajicDesigns/MD_Parola)
- [ESP32 Arduino BLE 2.0.17](https://github.com/espressif/arduino-esp32/tree/2.0.17/libraries/BLE)
- [Manrope — Google Fonts](https://github.com/google/fonts/tree/main/ofl/manrope)
