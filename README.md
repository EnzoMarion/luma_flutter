# Luma — application Flutter

Application de commande d'un panneau LED à matrices MAX7219 piloté par un ESP32 en Bluetooth Low Energy (BLE). Le même code Flutter est prévu pour Android et iOS.

## Fonctionnalités

- Recherche et connexion BLE, avec un mode démonstration sans panneau.
- Messages fixes ou défilants, réglage de la vitesse et de la luminosité, pictogrammes, dessin, favoris et aperçu 32 × 8 pixels.
- Alphabets latin, cyrillique, grec, hébreu, japonais et coréen dans les réglages. Un favori dans un autre alphabet peut être envoyé sans changer le réglage choisi.
- Clavier natif du téléphone. Sa langue dépend des claviers installés par l'utilisateur ; l'application ne peut pas forcer l'installation ni le changement de langue sur Android ou iOS.
- Activités complémentaires dans `lib/activities.dart` : commandes programmées, météo, connexion OBD et visualisation audio. Leur disponibilité dépend du firmware et de la plateforme.

L'écran physique n'a que 8 lignes. Les caractères non latins complexes sont convertis en pixels sur le téléphone ; leur lisibilité varie selon le glyphe et la matrice.

## Lancer sur Android

Installez Flutter et Android Studio, branchez un téléphone avec le débogage USB autorisé, puis ouvrez le dossier contenant `pubspec.yaml` :

```powershell
flutter doctor
flutter pub get
flutter devices
flutter run
```

Pour produire un APK de test : `flutter build apk --debug`. Les avertissements relatifs au Kotlin Gradle Plugin proviennent de dépendances actuelles et ne bloquent pas forcément la compilation.

## Lancer sur iOS

Sur un Mac équipé de Flutter, Xcode et CocoaPods :

```sh
flutter pub get
flutter run
```

Configurez l'équipe de signature dans Xcode et utilisez un iPhone pour tester le BLE. La partie iOS n'a pas été compilée ni testée dans l'environnement Windows de ce dépôt. Les fonctions propres à Android, notamment la capture audio via le canal natif, nécessitent une implémentation iOS avant usage.

## Code

| Chemin | Rôle |
|---|---|
| `lib/main.dart` | Écrans et navigation |
| `lib/controller.dart` | État, connexion et favoris |
| `lib/protocol.dart` | Paquets BLE, glyphes et validation des messages |
| `lib/raster_font.dart` | Conversion des écritures complexes en colonnes LED |
| `lib/ble_transport.dart` | Transport BLE réel |
| `lib/transport.dart` | Interface de transport et démonstration |
| `lib/pixel_preview.dart` | Aperçu de la matrice |
| `lib/drawing_editor.dart` | Éditeur de dessin |
| `lib/activities.dart` | Activités complémentaires |
| `test/` | Tests du protocole, du contrôleur et de l'interface |

Le code Bluetooth cible le service `7A2F0007-CB86-4B6D-8F78-38D24B9E1940` et la caractéristique d'écriture `7A2F0002-CB86-4B6D-8F78-38D24B9E1940`. Vérifiez que le firmware installé sur l'ESP32 utilise ces identifiants et comprend les commandes de `lib/protocol.dart` avant un essai matériel. Le sketch local `firmware/Luma_ESP32_C3.ino` est un ancien essai avec un autre UUID de service ; il n'est pas inclus dans cette mise à jour.

Voir [VALIDATION.md](VALIDATION.md) pour les vérifications et les limites connues.
