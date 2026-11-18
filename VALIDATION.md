# Validation

Mise à jour du 18 novembre 2026.

- Les tests Flutter couvrent désormais la reconnexion après coupure, sa limite de trois essais, l'annulation après déconnexion volontaire, ainsi que les libellés et dimensions des touches de couleur.
- `flutter test --no-pub` : 15 tests réussis. `flutter build apk --debug --no-pub` : APK Android compilé avec succès.
- Le comportement BLE réel après coupure et l'annonce TalkBack/VoiceOver restent à vérifier sur téléphone avec le panneau ; les tests utilisent un transport simulé.
- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings lib test` ne relève aucune erreur bloquante dans les sources de l'application. Il reste 21 remarques de style ou avertissements. L'analyse globale échoue sur des tests incompatibles du code tiers dans `vendor/reactive_ble_mobile`.
- L'application Android a été compilée et lancée sur le téléphone Xiaomi de développement lors des itérations précédentes.
- Le présent changement regroupe les modifications Flutter locales et actualise la documentation pour leur publication. Les essais physiques du panneau et la validation des écritures non latines sur chaque matrice restent à faire avec l'ESP32.
- La compilation iOS et les fonctions natives spécifiques à iOS ne sont pas validées : ce travail requiert un Mac avec Xcode et un iPhone.
- Les claviers sont ceux du système. Le choix d'alphabet dans l'app n'installe ni ne sélectionne automatiquement une langue de clavier.
- Les glyphes hébreux, japonais et coréens sont rasterisés dans la hauteur de 8 pixels du panneau ; certains peuvent être difficiles à distinguer. L'arabe a été retiré car il était illisible sur cette matrice.
- Le firmware présent sur le panneau doit employer les UUID et le protocole décrits dans `lib/protocol.dart`. Le sketch d'essai local dont l'UUID est différent n'est pas publié avec l'application.
