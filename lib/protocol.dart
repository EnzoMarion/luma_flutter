const legacyServiceUuid = '7A2F0007-CB86-4B6D-8F78-38D24B9E1940';
const rgbServiceUuid = '7A2F0008-CB86-4B6D-8F78-38D24B9E1940';
const writeUuid = '7A2F0002-CB86-4B6D-8F78-38D24B9E1940';

enum PanelHardware { max7219, ws2812b }

extension PanelHardwareProtocol on PanelHardware {
  String get serviceUuid =>
      this == PanelHardware.ws2812b ? rgbServiceUuid : legacyServiceUuid;
  int get maxColumns => this == PanelHardware.ws2812b ? 960 : 359;
}

const panelRgbColors = <(int, int, int)>[
  (215, 255, 127), (238, 243, 235), (247, 188, 119),
  (255, 53, 79), (98, 185, 232), (163, 77, 255),
];

List<int> clockSyncPacket(DateTime now) {
  final seconds =
      now.millisecondsSinceEpoch ~/ 1000 + now.timeZoneOffset.inSeconds;
  if (seconds < 0 || seconds > 0xffffffff) throw ArgumentError('Date invalide');
  return [
    0x41,
    seconds & 255,
    (seconds >> 8) & 255,
    (seconds >> 16) & 255,
    (seconds >> 24) & 255
  ];
}

enum ScrollMode { auto, fixed, always, appearance }

enum PanelAlphabet { latin, cyrillic, greek, hebrew, japanese, korean }

extension PanelAlphabetLabel on PanelAlphabet {
  String get label => switch (this) {
        PanelAlphabet.latin => 'Latin',
        PanelAlphabet.cyrillic => 'Cyrillique',
        PanelAlphabet.greek => 'Grec',
        PanelAlphabet.hebrew => 'Hébreu',
        PanelAlphabet.japanese => 'Japonais',
        PanelAlphabet.korean => 'Coréen',
      };
  bool get usesRasterFont => index >= PanelAlphabet.hebrew.index;
  bool get rightToLeft => this == PanelAlphabet.hebrew;
}

class PanelSettings {
  final int brightness; // 0 à 15 ; converti en 0 à 100 pour le panneau RGB.
  final int colorIndex;
  final int speedMs;
  final ScrollMode mode;
  final bool right;
  final bool power;
  final PanelAlphabet alphabet;
  const PanelSettings({
    this.brightness = 6,
    this.colorIndex = 0,
    this.speedMs = 50,
    this.mode = ScrollMode.auto,
    this.right = false,
    this.power = true,
    this.alphabet = PanelAlphabet.latin,
  });
  PanelSettings copyWith({
    int? brightness,
    int? colorIndex,
    int? speedMs,
    ScrollMode? mode,
    bool? right,
    bool? power,
    PanelAlphabet? alphabet,
  }) =>
      PanelSettings(
        brightness: brightness ?? this.brightness,
        colorIndex: colorIndex ?? this.colorIndex,
        speedMs: speedMs ?? this.speedMs,
        mode: mode ?? this.mode,
        right: right ?? this.right,
        power: power ?? this.power,
        alphabet: alphabet ?? this.alphabet,
      );
  String get payload =>
      '$brightness:$speedMs:${mode.index}:${right ? 1 : 0}:${power ? 1 : 0}:$colorIndex';
}

String normalizeMessage(String text) {
  var value = text.toUpperCase();
  const composed = {
    'E\u0301': 'É',
    'E\u0300': 'È',
    'E\u0302': 'Ê',
    'A\u0300': 'À',
    'C\u0327': 'Ç',
    'U\u0300': 'Ù',
    'O\u0302': 'Ô',
    'I\u0308': 'Ï',
    'Α\u0301': 'Ά',
    'Ε\u0301': 'Έ',
    'Η\u0301': 'Ή',
    'Ι\u0301': 'Ί',
    'Ο\u0301': 'Ό',
    'Υ\u0301': 'Ύ',
    'Ω\u0301': 'Ώ',
    'Ι\u0308': 'Ϊ',
    'Υ\u0308': 'Ϋ',
  };
  for (final entry in composed.entries) {
    value = value.replaceAll(entry.key, entry.value);
  }
  return value;
}

List<String> appearancePages(String text,
        [PanelAlphabet alphabet = PanelAlphabet.latin]) =>
    normalizeMessage(text)
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .expand((word) {
      final chars = word.runes.map(String.fromCharCode).toList();
      return [
        for (var i = 0;
            i < chars.length;
            i += requiresRasterFont(word, alphabet) ? 3 : 5)
          chars.skip(i).take(requiresRasterFont(word, alphabet) ? 3 : 5).join()
      ];
    }).toList();

String? validateMessage(String text,
    [PanelAlphabet alphabet = PanelAlphabet.latin]) {
  text = normalizeMessage(text);
  if (text.trim().isEmpty) return 'Écrivez un message avant de l’envoyer.';
  if (text.runes.length > 60)
    return 'Le panneau accepte 60 caractères maximum.';
  final supported = <String>{..._font.keys};
  if (alphabet == PanelAlphabet.cyrillic) supported.addAll(_cyrillicFont.keys);
  if (alphabet == PanelAlphabet.greek) supported.addAll(_greekFont.keys);
  final unsupported = text.runes
      .where((rune) =>
          !supported.contains(String.fromCharCode(rune)) &&
          !_scriptSupports(alphabet, rune))
      .map(String.fromCharCode)
      .toSet();
  if (unsupported.isNotEmpty)
    return 'Caractères non pris en charge : ${unsupported.join()}';
  return null;
}

PanelAlphabet? alphabetForMessage(String text) {
  for (final alphabet in PanelAlphabet.values) {
    if (validateMessage(text, alphabet) == null) return alphabet;
  }
  return null;
}

bool usesBitmapGlyph(String character) =>
    _font.containsKey(normalizeMessage(character));

bool requiresRasterFont(String text, PanelAlphabet alphabet) =>
    alphabet.usesRasterFont &&
    normalizeMessage(text)
        .runes
        .any((rune) => !usesBitmapGlyph(String.fromCharCode(rune)));

bool _scriptSupports(PanelAlphabet alphabet, int rune) => switch (alphabet) {
      PanelAlphabet.hebrew => rune >= 0x0590 && rune <= 0x05ff,
      PanelAlphabet.japanese => (rune >= 0x3040 && rune <= 0x30ff) ||
          (rune >= 0x31f0 && rune <= 0x31ff) ||
          _han(rune) ||
          _cjkPunctuation(rune),
      PanelAlphabet.korean => (rune >= 0xac00 && rune <= 0xd7af) ||
          (rune >= 0x1100 && rune <= 0x11ff) ||
          (rune >= 0x3130 && rune <= 0x318f) ||
          _han(rune) ||
          _cjkPunctuation(rune),
      _ => false,
    };

bool _han(int rune) =>
    (rune >= 0x3400 && rune <= 0x4dbf) ||
    (rune >= 0x4e00 && rune <= 0x9fff) ||
    (rune >= 0x20000 && rune <= 0x2fa1f);

bool _cjkPunctuation(int rune) =>
    (rune >= 0x3000 && rune <= 0x303f) || (rune >= 0xff00 && rune <= 0xffef);

List<List<int>> encodeRenderedText(
    List<int> columns, int speedMs, ScrollMode mode,
    [List<List<int>> pages = const [],
    PanelHardware hardware = PanelHardware.max7219]) {
  if (mode == ScrollMode.fixed ||
      (mode == ScrollMode.auto && columns.length <= 32)) {
    return [..._modeResetPackets(hardware), ..._columnImagePackets(columns)];
  }
  if (mode == ScrollMode.appearance) {
    if (pages.isEmpty || pages.length > 30) {
      throw ArgumentError('Nombre de pages invalide pour le panneau.');
    }
    final joined = <int>[];
    for (final page in pages) {
      final shown = page.take(32).toList();
      final left = (32 - shown.length) ~/ 2;
      joined.addAll(List<int>.filled(left, 0));
      joined.addAll(shown);
      joined.addAll(List<int>.filled(32 - left - shown.length, 0));
    }
    if (joined.length > hardware.maxColumns) {
      throw ArgumentError(
          'Message trop long pour le panneau en mode Apparition.');
    }
    return [
      [0x46, 0],
      [0x47, pages.length],
      ..._scrollPackets(joined, speedMs)
    ];
  }
  if (columns.length > hardware.maxColumns) {
    throw ArgumentError('Message trop long en pixels pour ce panneau.');
  }
  return [..._modeResetPackets(hardware), ..._scrollPackets(columns, speedMs)];
}

List<List<int>> _modeResetPackets(PanelHardware hardware) =>
    hardware == PanelHardware.ws2812b ? [[0x46, 0], [0x47, 0]] : [];

List<List<int>> encodeCommand(String kind, int id,
    [String payload = '',
    int speedMs = 100,
    ScrollMode mode = ScrollMode.auto,
    PanelAlphabet alphabet = PanelAlphabet.latin,
    PanelHardware hardware = PanelHardware.max7219]) {
  if (kind == 'S') {
    final parts = payload.split(':');
    final brightness = int.tryParse(parts.first) ?? 0;
    if (brightness < 0 || brightness > 15)
      throw ArgumentError('Luminosité invalide');
    if (hardware == PanelHardware.ws2812b) {
      final colorIndex = parts.length > 5 ? int.tryParse(parts[5]) : 0;
      if (colorIndex == null ||
          colorIndex < 0 ||
          colorIndex >= panelRgbColors.length) {
        throw ArgumentError('Couleur invalide');
      }
      final rgb = panelRgbColors[colorIndex];
      return [[0x0A, (brightness * 100 / 15).round(), rgb.$1, rgb.$2, rgb.$3]];
    }
    return [
      [0x0A, brightness],
    ];
  }
  if (kind == 'I') {
    final index = int.tryParse(payload) ?? 0;
    final rows = pixelIcons[index].rows;
    return [..._modeResetPackets(hardware), ..._imagePackets(rows)];
  }
  if (kind == 'C') return [
    ..._modeResetPackets(hardware),
    ..._imagePackets(const [0, 0, 0, 0, 0, 0, 0, 0]),
  ];
  if (kind == 'D') {
    if (payload.length != 256 || payload.contains(RegExp(r'[^01]'))) {
      throw ArgumentError('Dessin invalide');
    }
    final image = <int>[];
    for (var y = 0; y < 8; y++) {
      for (var matrix = 0; matrix < 4; matrix++) {
        var value = 0;
        for (var x = 0; x < 8; x++) {
          if (payload[y * 32 + matrix * 8 + x] == '1') value |= 0x80 >> x;
        }
        image.add(value);
      }
    }
    return [
      ..._modeResetPackets(hardware),
      [0x20, ...image.sublist(0, 16)],
      [0x21, ...image.sublist(16, 32)]
    ];
  }
  if (kind == 'T') {
    final error = validateMessage(payload, alphabet);
    if (error != null) throw ArgumentError(error);
    final columns = _textColumns(payload, alphabet);
    if (mode == ScrollMode.fixed ||
        (mode == ScrollMode.auto && columns.length <= 32)) {
      return [..._modeResetPackets(hardware), ..._columnImagePackets(columns)];
    }
    if (mode == ScrollMode.appearance) {
      final pages = appearancePages(payload, alphabet);
      final pageColumns = <int>[];
      for (final page in pages) {
        final glyphs = _textColumns(page, alphabet);
        final left = ((32 - glyphs.length) / 2).floor();
        pageColumns.addAll(List<int>.filled(left, 0));
        pageColumns.addAll(glyphs);
        pageColumns.addAll(List<int>.filled(32 - left - glyphs.length, 0));
      }
      if (pageColumns.length > hardware.maxColumns || pages.length > 30) {
        throw ArgumentError('Message trop long pour ce panneau.');
      }
      return [
        [0x46, 0],
        [0x47, pages.length],
        ..._scrollPackets(pageColumns, speedMs)
      ];
    }
    if (columns.length > hardware.maxColumns) {
      throw ArgumentError('Message trop long en pixels pour ce panneau.');
    }
    return [..._modeResetPackets(hardware), ..._scrollPackets(columns, speedMs)];
  }
  throw ArgumentError('Commande inconnue pour ce firmware');
}

List<List<int>> _imagePackets(List<int> rows) {
  final columns = List<int>.generate(8, (x) {
    var bits = 0;
    for (var y = 0; y < 8; y++) {
      if ((rows[y] & (0x80 >> x)) != 0) bits |= 0x80 >> y;
    }
    return bits;
  });
  return _columnImagePackets(columns);
}

List<List<int>> _columnImagePackets(List<int> columns) {
  final width = columns.length > 32 ? 32 : columns.length;
  final left = (32 - width) ~/ 2;
  final image = <int>[];
  for (var row = 0; row < 8; row++) {
    for (var matrix = 0; matrix < 4; matrix++) {
      var value = 0;
      for (var x = 0; x < 8; x++) {
        final source = matrix * 8 + x - left;
        if (source >= 0 &&
            source < width &&
            (columns[source] & (0x80 >> row)) != 0) {
          value |= 0x80 >> x;
        }
      }
      image.add(value);
    }
  }
  return [
    [0x20, ...image.sublist(0, 16)],
    [0x21, ...image.sublist(16, 32)],
  ];
}

List<List<int>> _scrollPackets(List<int> columns, int speedMs) {
  final packets = <List<int>>[
    [0x30, columns.length & 255, columns.length >> 8, speedMs.clamp(20, 200)],
  ];
  for (var start = 0; start < columns.length; start += 17) {
    final end = (start + 17).clamp(0, columns.length).toInt();
    packets
        .add([0x31, start & 255, start >> 8, ...columns.sublist(start, end)]);
  }
  packets.add([0x32]);
  return packets;
}

const Map<String, String> _font = {
  'A': '01110/10001/10001/11111/10001/10001/10001',
  'B': '11110/10001/10001/11110/10001/10001/11110',
  'C': '01111/10000/10000/10000/10000/10000/01111',
  'D': '11110/10001/10001/10001/10001/10001/11110',
  'E': '11111/10000/10000/11110/10000/10000/11111',
  'F': '11111/10000/10000/11110/10000/10000/10000',
  'G': '01110/10001/10000/10111/10001/10001/01110',
  'H': '10001/10001/10001/11111/10001/10001/10001',
  'I': '11111/00100/00100/00100/00100/00100/11111',
  'J': '00111/00010/00010/00010/00010/10010/01100',
  'K': '10001/10010/10100/11000/10100/10010/10001',
  'L': '10000/10000/10000/10000/10000/10000/11111',
  'M': '10001/11011/10101/10101/10001/10001/10001',
  'N': '10001/11001/10101/10011/10001/10001/10001',
  'O': '01110/10001/10001/10001/10001/10001/01110',
  'P': '11110/10001/10001/11110/10000/10000/10000',
  'Q': '01110/10001/10001/10001/10101/10010/01101',
  'R': '11110/10001/10001/11110/10100/10010/10001',
  'S': '01111/10000/10000/01110/00001/00001/11110',
  'T': '11111/00100/00100/00100/00100/00100/00100',
  'U': '10001/10001/10001/10001/10001/10001/01110',
  'V': '10001/10001/10001/10001/10001/01010/00100',
  'W': '10001/10001/10001/10101/10101/11011/10001',
  'X': '10001/10001/01010/00100/01010/10001/10001',
  'Y': '10001/10001/01010/00100/00100/00100/00100',
  'Z': '11111/00001/00010/00100/01000/10000/11111',
  '0': '01110/10001/10011/10101/11001/10001/01110',
  '1': '00100/01100/00100/00100/00100/00100/01110',
  '2': '01110/10001/00001/00010/00100/01000/11111',
  '3': '11110/00001/00001/01110/00001/00001/11110',
  '4': '00010/00110/01010/10010/11111/00010/00010',
  '5': '11111/10000/10000/11110/00001/00001/11110',
  '6': '01110/10000/10000/11110/10001/10001/01110',
  '7': '11111/00001/00010/00100/01000/01000/01000',
  '8': '01110/10001/10001/01110/10001/10001/01110',
  '9': '01110/10001/10001/01111/00001/00001/01110',
  ' ': '00000/00000/00000/00000/00000/00000/00000',
  '!': '00100/00100/00100/00100/00100/00000/00100',
  '?': '01110/10001/00001/00010/00100/00000/00100',
  '.': '00000/00000/00000/00000/00000/00110/00110',
  ',': '00000/00000/00000/00000/00110/00100/01000',
  ':': '00000/00100/00100/00000/00100/00100/00000',
  "'": '00100/00100/00000/00000/00000/00000/00000',
  '-': '00000/00000/00000/11111/00000/00000/00000',
  '(': '00010/00100/01000/01000/01000/00100/00010',
  ')': '01000/00100/00010/00010/00010/00100/01000',
  '=': '00000/00000/11111/00000/11111/00000/00000',
  '_': '00000/00000/00000/00000/00000/00000/11111',
  '+': '00000/00100/00100/11111/00100/00100/00000',
  '/': '00001/00010/00010/00100/01000/01000/10000',
  'É': '00010/00100/11111/10000/11110/10000/11111',
  'È': '01000/00100/11111/10000/11110/10000/11111',
  'Ê': '00100/01010/11111/10000/11110/10000/11111',
  'À': '01000/00100/01110/10001/11111/10001/10001',
  'Ç': '01111/10000/10000/10000/01111/00100/01000',
  'Ù': '01000/00100/10001/10001/10001/10001/01110',
  'Ô': '00100/01010/01110/10001/10001/10001/01110',
  'Ï': '01010/00000/11111/00100/00100/00100/11111',
};

// 5x7 pixel glyphs for the modern Cyrillic alphabet. Glyphs that look like
// Latin letters reuse the Latin bitmap; distinct letters are drawn below.
final Map<String, String> _cyrillicFont = {
  'А': _font['A']!,
  'В': _font['B']!,
  'Е': _font['E']!,
  'К': _font['K']!,
  'М': _font['M']!,
  'Н': _font['H']!,
  'О': _font['O']!,
  'Р': _font['P']!,
  'С': _font['C']!,
  'Т': _font['T']!,
  'У': _font['Y']!,
  'Х': _font['X']!,
  'І': _font['I']!,
  'Б': '11110/10001/10000/11110/10001/10001/11110',
  'Г': '11111/10000/10000/10000/10000/10000/10000',
  'Д': '00110/01010/01010/01010/10001/11111/10001',
  'Ё': '01010/00000/11111/10000/11110/10000/11111',
  'Ж': '10101/10101/01110/00100/01110/10101/10101',
  'З': '11110/00001/00001/00110/00001/00001/11110',
  'И': '10001/10011/10101/11001/10001/10001/10001',
  'Й': '01010/00100/10001/10011/10101/11001/10001',
  'Л': '00111/01001/01001/01001/10001/10001/10001',
  'П': '11111/10001/10001/10001/10001/10001/10001',
  'Ф': '00100/01110/10101/10101/10101/01110/00100',
  'Ц': '10001/10001/10001/10001/10001/11111/00001',
  'Ч': '10001/10001/10001/01111/00001/00001/00001',
  'Ш': '10101/10101/10101/10101/10101/10101/11111',
  'Щ': '10101/10101/10101/10101/10101/11111/00001',
  'Ъ': '11000/01000/01000/01110/01001/01001/01110',
  'Ы': '10001/10001/10001/11101/10011/10011/11101',
  'Ь': '10000/10000/10000/11110/10001/10001/11110',
  'Э': '01110/10001/00001/00111/00001/10001/01110',
  'Ю': '10011/10101/10101/11101/10101/10101/10011',
  'Я': '01111/10001/10001/01111/00101/01001/10001',
  'Є': '01111/10000/10000/11110/10000/10000/01111',
  'Ї': '01010/00000/00100/00100/00100/00100/00100',
  'Ґ': '11111/10000/10000/10000/10000/10000/10000',
  'Ў': '01010/00100/10001/10001/01010/00100/00100',
  'Ђ': '10000/11110/10001/10001/11110/10100/10010',
  'Ѓ': '01000/00100/11111/10000/10000/10000/10000',
  'Ќ': '10001/01010/01100/01010/01001/01001/01001',
  'Љ': '00111/01001/01001/11101/10011/10011/11101',
  'Њ': '10001/10001/10001/11101/10011/10011/11101',
  'Ћ': '11111/00100/00100/11110/00101/00101/11110',
  'Џ': '10001/10001/10001/10001/10001/11111/00100',
  'Ѕ': '01111/10000/10000/01110/00001/00001/11110',
  'Ј': '00111/00010/00010/00010/00010/10010/01100',
};

// Modern Greek, including the common uppercase tonos forms.
final Map<String, String> _greekFont = {
  'Α': _font['A']!,
  'Β': _font['B']!,
  'Ε': _font['E']!,
  'Ζ': _font['Z']!,
  'Η': _font['H']!,
  'Ι': _font['I']!,
  'Κ': _font['K']!,
  'Μ': _font['M']!,
  'Ν': _font['N']!,
  'Ο': _font['O']!,
  'Ρ': _font['P']!,
  'Τ': _font['T']!,
  'Υ': _font['Y']!,
  'Χ': _font['X']!,
  'Γ': '11111/10000/10000/10000/10000/10000/10000',
  'Δ': '00100/01010/01010/10001/10001/11111/10001',
  'Θ': '01110/10001/10001/11111/10001/10001/01110',
  'Λ': '00100/01010/01010/10001/10001/10001/10001',
  'Ξ': '11111/00000/01110/00000/01110/00000/11111',
  'Π': '11111/10001/10001/10001/10001/10001/10001',
  'Σ': '11111/10000/01000/00100/01000/10000/11111',
  'Φ': '00100/01110/10101/10101/10101/01110/00100',
  'Ψ': '10101/10101/10101/01110/00100/00100/00100',
  'Ω': '01110/10001/10001/10001/10101/01010/11011',
  'Ά': '01000/00100/01110/10001/11111/10001/10001',
  'Έ': '01000/00100/11111/10000/11110/10000/11111',
  'Ή': '01000/00100/10001/10001/11111/10001/10001',
  'Ί': '01000/00100/11111/00100/00100/00100/11111',
  'Ό': '00100/01010/01110/10001/10001/10001/01110',
  'Ύ': '01000/00100/10001/10001/01010/00100/00100',
  'Ώ': '00100/01010/01110/10001/10101/01010/11011',
  'Ϊ': '01010/00000/00100/00100/00100/00100/00100',
  'Ϋ': '01010/00000/10001/01010/00100/00100/00100',
};

List<int> _textColumns(String text,
    [PanelAlphabet alphabet = PanelAlphabet.latin]) {
  final characters = normalizeMessage(text).split('');
  final columns = <int>[];
  for (var index = 0; index < characters.length; index++) {
    final rows = (_font[characters[index]] ??
            (alphabet == PanelAlphabet.cyrillic
                ? _cyrillicFont[characters[index]]
                : null) ??
            (alphabet == PanelAlphabet.greek
                ? _greekFont[characters[index]]
                : null) ??
            _font[' ']!)
        .split('/');
    for (var x = 0; x < 5; x++) {
      var value = 0;
      for (var y = 0; y < rows.length; y++) {
        if (rows[y][x] == '1') value |= 0x80 >> y;
      }
      columns.add(value);
    }
    if (index + 1 < characters.length) columns.add(0);
  }
  return columns;
}

List<int> textColumns(String text,
        [PanelAlphabet alphabet = PanelAlphabet.latin]) =>
    _textColumns(text, alphabet);

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
  PixelIcon('Soleil', [0x18, 0x5a, 0x3c, 0xff, 0xff, 0x3c, 0x5a, 0x18]),
  PixelIcon('Clin d’œil', [0x3c, 0x42, 0xad, 0x81, 0xa5, 0x99, 0x42, 0x3c]),
  PixelIcon('Pause', [0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x00]),
];
