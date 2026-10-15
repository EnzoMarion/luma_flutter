import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/protocol.dart';
import 'package:luma/transport.dart';

void main() {
  test('60 caractères arrivent intacts avec un MTU BLE minimum', () {
    final text = List.filled(60, 'A').join();
    final chunks = encodeCommand('T', 42, text);
    expect(chunks.every((c) => c.length <= 20), isTrue);
    expect(ascii.decode(chunks.expand((c) => c).toList()), 'T:42:$text\n');
  });
  test('les caractères de contrôle et les textes non ASCII sont refusés', () {
    for (final text in [
      '',
      '   ',
      'CAFÉ',
      'OK\nC:2',
      List.filled(61, 'A').join(),
    ]) {
      expect(validateMessage(text), isNotNull);
      expect(() => encodeCommand('T', 1, text), throwsArgumentError);
    }
    expect(validateMessage('A:B !'), isNull);
  });
  test('les réglages utilisent les niveaux matériels et le protocole v1', () {
    const settings = PanelSettings(
      brightness: 15,
      speedMs: 30,
      mode: ScrollMode.always,
      right: true,
      power: false,
    );
    expect(settings.payload, '15:30:2:1:0');
    expect(
      ascii.decode(
        encodeCommand('S', 9, settings.payload).expand((c) => c).toList(),
      ),
      'S:9:15:30:2:1:0\n',
    );
  });
  test('la démo refuse les envois après déconnexion', () async {
    final demo = DemoTransport();
    await expectLater(demo.send('T', 'MERCI'), throwsStateError);
    await demo.connect(const PanelDevice('demo', 'Démo', -40));
    await demo.send('T', 'MERCI');
    expect(demo.commands, ['T:MERCI']);
    await demo.disconnect();
    await expectLater(demo.send('C'), throwsStateError);
    await demo.dispose();
  });
}
