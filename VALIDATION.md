# Validation de cette livraison

Date : 30 septembre 2026.

## Vérifications exécutées

- Les 10 fichiers Dart ont été lus et formatés par Dart 3.13.5 : aucune erreur de syntaxe.
- Analyse statique de `lib/protocol.dart`, `lib/transport.dart` et `tool/setup.dart` : **No issues found**.
- `dart tool/check_protocol.dart` : **67 cas** de longueur/validation, fragmentation de 20 octets, valeurs de réglage, dimensions des six bitmaps et transport de démonstration, tous réussis.
- La police Manrope et sa licence sont incluses dans le projet, sans chargement distant au lancement.

## Ce qui reste à exécuter sur vos postes

- Génération des dossiers natifs Android/iOS/web par `dart tool/setup.dart` avec Flutter installé.
- Résolution des dépendances, analyse statique complète via `flutter analyze` et tests via `flutter test`.
- Compilation Android et iOS, validation de la signature iOS.
- Comparaison visuelle de l'application réellement exécutée avec la maquette Figma ; la création a utilisé une inspection du navigateur et non les outils d'extraction Figma.
- Compilation du firmware PlatformIO, téléversement et essais matériels.
- Autorisations BLE sur Android et iOS, recherche, découverte GATT, notifications et reconnexion sur téléphones physiques.

Les tentatives d'installation de Flutter dans l'environnement de création ont échoué (téléchargement inaccessible). Dart seul a pu être installé pour les vérifications indépendantes de Flutter. Cette livraison contient donc du **code source de prototype**, pas une application compilée ni un résultat matériel validé. Aucun APK ou IPA n'est inclus.

## Modifications du parcours Figma (30 septembre 2026)

Après les vérifications listées plus haut, les écrans ont été étendus au parcours archivé de la maquette (choix RGB/rouge, palette, pictogrammes, réglages et confirmations) et le firmware a reçu un profil WS2812B. Ces ajouts n'ont **pas** été compilés ni exécutés. Vérifier la compilation Flutter et les deux profils PlatformIO avant de les utiliser sur du matériel ; la compatibilité dépend du type exact de matrice et de son câblage.
