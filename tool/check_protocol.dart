import 'dart:convert';

import '../lib/protocol.dart';
import '../lib/transport.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  var cases = 0;
  for (var length = 1; length <= 60; length++) {
    final message = List.filled(length, 'A').join();
    final chunks = encodeCommand('T', 65535, message);
    check(chunks.every((c) => c.length <= 20), 'MTU dépassé');
    check(
      ascii.decode(chunks.expand((c) => c).toList()) == 'T:65535:$message\n',
      'Texte altéré',
    );
    cases++;
  }
  for (final text in [
    '',
    ' ',
    'é',
    '🙂',
    'A\nB',
    'A\rB',
    List.filled(61, 'A').join(),
  ]) {
    check(validateMessage(text) != null, 'Validation absente');
    var rejected = false;
    try {
      encodeCommand('T', 1, text);
    } on ArgumentError {
      rejected = true;
    }
    check(rejected, 'Trame invalide acceptée');
    cases++;
  }
  check(validateMessage('MERCI: BONJOUR!') == null, 'Ponctuation rejetée');
  check(const PanelSettings().payload == '6:65:0:0:1', 'Réglages incohérents');
  for (final icon in pixelIcons) {
    check(
      icon.rows.length == 8 && icon.rows.every((r) => r >= 0 && r <= 255),
      'Bitmap invalide',
    );
  }
  final demo = DemoTransport();
  var disconnected = false;
  try {
    await demo.send('C');
  } on StateError {
    disconnected = true;
  }
  check(disconnected, 'Envoi hors connexion accepté');
  await demo.connect(const PanelDevice('demo', 'Démo', -45));
  await demo.send('T', 'MERCI');
  check(demo.commands.single == 'T:MERCI', 'Démo incorrecte');
  await demo.disconnect();
  await demo.dispose();
  print(
    'OK : $cases cas de longueur/validation, fragmentation, réglages, 6 bitmaps et transport démo.',
  );
}
