import 'dart:convert';

const serviceUuid = '7c8d0001-5b7a-4e9e-9f31-9e8c28480a01';
const writeUuid = '7c8d0002-5b7a-4e9e-9f31-9e8c28480a01';
const notifyUuid = '7c8d0003-5b7a-4e9e-9f31-9e8c28480a01';

enum ScrollMode { auto, fixed, always }

class PanelSettings {
  final int brightness; // Intensité MAX7219 : 0 à 15 (0 n'éteint pas).
  final int speedMs;
  final ScrollMode mode;
  final bool right;
  final bool power;
  const PanelSettings({
    this.brightness = 6,
    this.speedMs = 65,
    this.mode = ScrollMode.auto,
    this.right = false,
    this.power = true,
  });
  PanelSettings copyWith({
    int? brightness,
    int? speedMs,
    ScrollMode? mode,
    bool? right,
    bool? power,
  }) => PanelSettings(
    brightness: brightness ?? this.brightness,
    speedMs: speedMs ?? this.speedMs,
    mode: mode ?? this.mode,
    right: right ?? this.right,
    power: power ?? this.power,
  );
  String get payload =>
      '$brightness:$speedMs:${mode.index}:${right ? 1 : 0}:${power ? 1 : 0}';
}

String? validateMessage(String text) {
  if (text.trim().isEmpty) return 'Écrivez un message avant de l’envoyer.';
  if (text.length > 60) return 'Le panneau accepte 60 caractères maximum.';
  if (text.codeUnits.any((c) => c < 32 || c > 126)) {
    return 'Utilisez des caractères sans accents ni emojis (ASCII).';
  }
  return null;
}

List<List<int>> encodeCommand(String kind, int id, [String payload = '']) {
  if (!{'T', 'S', 'I', 'C', 'P', 'K'}.contains(kind))
    throw ArgumentError('Commande inconnue');
  if (id < 1 || id > 65535) throw ArgumentError('Identifiant invalide');
  if (kind == 'K' && !RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(payload)) {
    throw ArgumentError('Couleur RGB invalide');
  }
  if (kind == 'T' && validateMessage(payload) != null) {
    throw ArgumentError(validateMessage(payload));
  }
  if (payload.contains('\n') || payload.contains('\r'))
    throw ArgumentError('Trame invalide');
  final bytes = ascii.encode(
    '$kind:$id${payload.isEmpty ? '' : ':$payload'}\n',
  );
  return [
    for (var i = 0; i < bytes.length; i += 20)
      bytes.sublist(i, i + 20 < bytes.length ? i + 20 : bytes.length),
  ];
}

class PixelIcon {
  final String label;
  final List<int> rows;
  const PixelIcon(this.label, this.rows);
}

// Bitmaps propres à ce prototype, reproduits sur le panneau et dans l'aperçu.
const pixelIcons = [
  PixelIcon('Sourire', [0x3c, 0x42, 0xa5, 0x81, 0xa5, 0x99, 0x42, 0x3c]),
  PixelIcon('Cœur', [0x00, 0x66, 0xff, 0xff, 0x7e, 0x3c, 0x18, 0x00]),
  PixelIcon('Flèche', [0x10, 0x18, 0xfc, 0xfe, 0xfc, 0x18, 0x10, 0x00]),
  PixelIcon('Soleil', [0x24, 0x18, 0x7e, 0xdb, 0xdb, 0x7e, 0x18, 0x24]),
  PixelIcon('Clin d’œil', [0x3c, 0x42, 0xa9, 0x81, 0xa5, 0x99, 0x42, 0x3c]),
  PixelIcon('Pause', [0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x00]),
];
