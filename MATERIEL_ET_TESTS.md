# Matériel et validation sur table

## Connexions prévues

| Signal | ESP32 | Adaptateur logique 74AHCT125, si utilisé | Entrée chaîne MAX7219 |
|---|---|---|---|
| Données | GPIO23 | Entrée A → sortie Y du canal 1 | DIN |
| Horloge | GPIO18 | Entrée A → sortie Y du canal 2 | CLK |
| Sélection | GPIO5 | Entrée A → sortie Y du canal 3 | CS / LOAD |
| Masse | GND | GND | GND |
| Alimentation matrices | Source 5 V externe | VCC 5 V | VCC 5 V |

### Matrice couleur WS2812B 8 × 8 (profil alternatif)

| Signal | ESP32 | Matrice WS2812B |
|---|---|---|
| Données | GPIO4 | DIN (unidirectionnel) |
| Masse | GND | GND, commun avec la source 5 V |
| Alimentation | Source 5 V externe adaptée au courant maximal de la matrice | 5V |

Ne pas alimenter les 64 LED par la carte ESP32. Mettre une masse commune, vérifier le sens DIN, et employer un convertisseur logique 3,3 V vers 5 V si la matrice ne reconnaît pas de façon fiable le signal ESP32. Le profil se choisit dans `firmware/platformio.ini` (`-DLUMA_PANEL_COLOR=1`). Tester à luminosité faible et vérifier le courant réel avant d'augmenter l'intensité.

Vérifier le brochage du boîtier exact du 74AHCT125 avant câblage. Activer les trois canaux en mettant leurs entrées `/OE` à 0. Désactiver le canal inutilisé (`/OE` à 1) et fixer son entrée à un niveau logique défini. Prévoir 100 nF entre son VCC et GND, proche du composant.

Les matrices doivent recevoir le 5 V du convertisseur prévu, avec une masse commune à l'ESP32. Ne pas faire passer leur courant dans une broche de la carte ESP32. Vérifier la méthode d'alimentation de votre DevKit et éviter deux sources d'alimentation simultanées non prévues par la carte. Le montage automobile 12 V, sa protection et son convertisseur restent à valider séparément ; commencer sur une alimentation de table adaptée.

## Checklist fonctionnelle

- [ ] Téléversement et diagnostic série ESP32 seul.
- [ ] Une matrice, `MODULES=1`, faible luminosité, avec le sketch minimal.
- [ ] Vérifier le sens DIN → DOUT et le type matériel FC16/GENERIC approprié.
- [ ] Passer à huit modules et `MODULES=8` ; vérifier le texte fixe puis le défilement.
- [ ] Contrôler la tension en début et fin de chaîne sous charge ; relever la consommation réelle.
- [ ] Profil WS2812B : vérifier GPIO4, l'ordre/câblage de la matrice, les couleurs RGB, six pictogrammes, luminosité et défilement.
- [ ] BLE : ping et message avec nRF Connect, puis application.
- [ ] Refuser accents/emojis, message vide, 61 caractères ; accepter 60 caractères.
- [ ] Envoyer un texte long : aucun fragment perdu ou affiché séparément.
- [ ] Vérifier l'orientation de la flèche et des six pictogrammes ; adapter le type matériel si miroir/rotation.
- [ ] Tester intensité 0 et 15, vitesse lente/rapide, deux directions, modes fixe/auto/toujours.
- [ ] Extinction/rallumage et effacement ; ne pas confondre intensité 0 et extinction.
- [ ] Couper puis rétablir l'alimentation ESP32 ; constater la déconnexion, rechercher puis reconnecter.
- [ ] Refuser les autorisations puis les réactiver ; tester Bluetooth désactivé et recherche sans périphérique.
- [ ] Refaire sur un téléphone Android et un iPhone physiques.
- [ ] Tester petite taille d'écran, clavier ouvert et taille de texte système augmentée.
- [ ] Lancer `flutter analyze` et `flutter test`, puis compiler sur Windows/Android et Mac/iOS.

## Avant Fusion 360

Mesurer : dimensions réelles de chaque PCB, espacement des modules, pas et hauteur des LED, largeur assemblée, position/diamètre des perçages, connecteurs et débordement des câbles, ESP32 avec câble USB branché, convertisseur et bornes, hauteur totale nécessaire. La largeur de 480 mm du contexte est une estimation à confirmer, pas une cote de fabrication.
