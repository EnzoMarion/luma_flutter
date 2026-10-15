# Protocole Luma v1

Ce protocole est une **proposition implémentée des deux côtés**, et non un protocole déjà présent sur votre ESP32. Installez le firmware fourni ou adaptez votre firmware existant.

| Élément | UUID / propriété |
|---|---|
| Service annoncé | `7c8d0001-5b7a-4e9e-9f31-9e8c28480a01` |
| Commandes | `7c8d0002-5b7a-4e9e-9f31-9e8c28480a01` — WRITE avec réponse |
| Confirmations | `7c8d0003-5b7a-4e9e-9f31-9e8c28480a01` — NOTIFY |

Une commande est une ligne ASCII terminée par un **octet LF (0x0A)**. Le transport coupe la ligne en paquets de 20 octets au maximum, compatibles avec le MTU ATT minimum. L'ESP32 reconstitue la ligne avant de l'appliquer. Les commandes sont envoyées une par une ; ne pas entrelacer leurs fragments.

| Commande | Exemple, avec `\n` représentant LF | Signification |
|---|---|---|
| Ping | `P:1\n` | Vérifier la chaîne WRITE → firmware → NOTIFY |
| Texte | `T:2:MERCI\n` | De 1 à 60 caractères ASCII imprimables, pas uniquement des espaces |
| Icône | `I:3:0\n` | 0 sourire, 1 cœur, 2 flèche, 3 soleil, 4 clin d'œil, 5 pause |
| Couleur | `K:6:D7FF7F\n` | Couleur RGB hexadécimale, sans `#` ; disponible uniquement avec le firmware WS2812B couleur |
| Réglages | `S:4:6:65:0:0:1\n` | Intensité, délai en ms, mode, direction, alimentation logique |
| Effacer | `C:5\n` | Effacer l'affichage sans supprimer le texte dans l'application |

Pour les réglages : intensité 0–15 ; délai 20–200 ms par pas ; mode 0 auto, 1 fixe, 2 toujours ; direction 0 gauche, 1 droite ; alimentation 0 arrêt, 1 marche. Le niveau 0 est la luminosité minimale du MAX7219, **pas l'extinction**. Sur WS2812B, l'intensité est convertie en luminosité globale.

Le deuxième champ est un identifiant de commande entre 1 et 65535. Réponses : `OK:identifiant\n` après application, ou `ERR:identifiant:INVALID\n` si les paramètres sont refusés. Les lignes sans identifiant valide, les données non ASCII, les lignes trop longues et les lignes perdues lorsque la queue est pleine n'ont pas de confirmation. L'application interrompt l'attente après cinq secondes et affiche une erreur.

La connexion n'est présentée comme établie dans l'application qu'après découverte des caractéristiques et confirmation d'un ping. Un second ping est autorisé en cas de délai d'installation des notifications. Les commandes utilisateur ne sont pas automatiquement rejouées après une coupure.

## Vérifier avec nRF Connect

1. Scanner, se connecter à `Luma rouge` (MAX7219) ou `Luma couleur` (WS2812B), et ouvrir le service personnalisé.
2. Activer les notifications de la caractéristique `...0003...`.
3. Sur `...0002...`, choisir une écriture **avec réponse**. En mode hexadécimal, envoyer `50 3A 31 0A` (ping).
4. Attendre `OK:1` en notification.
5. Envoyer `54 3A 32 3A 4D 45 52 43 49 0A` (texte `MERCI`) et attendre `OK:2`.
6. Déconnecter nRF Connect avant de lancer Luma : ce prototype est conçu pour un seul téléphone à la fois.

Attention : saisir les caractères visibles `\` puis `n` dans un champ texte ne remplace pas nécessairement un véritable LF. Utilisez le mode hexadécimal pour le premier test.
