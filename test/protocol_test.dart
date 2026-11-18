import 'package:flutter_test/flutter_test.dart';
import 'package:luma/protocol.dart';
import 'package:luma/transport.dart';
import 'package:luma/activities.dart';

void main() {
  test('nouveau panneau RGB et ancien panneau rouge ont des paquets distincts', () {
    expect(rgbServiceUuid, '7A2F0008-CB86-4B6D-8F78-38D24B9E1940');
    expect(legacyServiceUuid, '7A2F0007-CB86-4B6D-8F78-38D24B9E1940');
    expect(encodeCommand('S', 1, '6:50:0:0:1:3', 50, ScrollMode.auto,
        PanelAlphabet.latin, PanelHardware.ws2812b), [[0x0a, 40, 255, 53, 79]]);
    expect(encodeCommand('S', 1, '6:50:0:0:1:3'), [[0x0a, 6]]);
    final fixedRgb = encodeCommand('T', 1, 'E', 50, ScrollMode.fixed,
        PanelAlphabet.latin, PanelHardware.ws2812b);
    expect(fixedRgb.take(2).toList(), [[0x46, 0], [0x47, 0]]);
    expect(fixedRgb.skip(2).map((p) => p.first), [0x20, 0x21]);
    final longColumns = List<int>.filled(500, 0x80);
    expect(encodeRenderedText(longColumns, 50, ScrollMode.always, const [],
        PanelHardware.ws2812b).last, [0x32]);
    expect(() => encodeRenderedText(longColumns, 50, ScrollMode.always),
        throwsArgumentError);
  });
  test('commandes horloge et minuteur du firmware récent', () {
    expect(modePacket(3, 300), [0x40, 3, 44, 1, 0, 0]);
    expect(modePacket(1), [0x40, 1, 0, 0, 0, 0]);
    expect(clockPacket(DateTime.utc(1970, 1, 1, 0, 0, 1)), [0x41, 1, 0, 0, 0]);
    expect(() => modePacket(3, 0), throwsArgumentError);
  });
  test('texte de 60 caractères : fragments ordonnés et longueur maximale', () {
    final packets = encodeCommand('T', 1, 'A' * 60, 50, ScrollMode.auto);
    expect(packets.first, [0x30, 0x67, 0x01, 50]);
    expect(packets.last, [0x32]);
    var offset = 0;
    final columns = <int>[];
    for (final packet in packets.skip(1).take(packets.length - 2)) {
      expect(packet.first, 0x31);
      expect(packet.length, lessThanOrEqualTo(20));
      expect(packet[1] | (packet[2] << 8), offset);
      columns.addAll(packet.skip(3));
      offset += packet.length - 3;
    }
    expect(columns, textColumns('A' * 60));
    expect(columns.length, 359);
  });
  test('message fixe et dessin utilisent deux images complètes', () {
    final fixed = encodeCommand('T', 1, 'E', 50, ScrollMode.fixed);
    expect(fixed.map((p) => p.length), [17, 17]);
    expect(fixed.map((p) => p.first), [0x20, 0x21]);
    final pixels = List.filled(256, '0');
    pixels[0] = '1';
    pixels[255] = '1';
    final drawing = encodeCommand('D', 1, pixels.join());
    expect(drawing[0][1], 0x80);
    expect(drawing[1].last, 0x01);
    expect(() => encodeCommand('D', 1, '1'), throwsArgumentError);
  });
  test('lettres accentuées et caractères non pris en charge', () {
    expect(validateMessage('À BIENTÔT !'), isNull);
    expect(validateMessage('Cafe\u0301'), isNull);
    expect(textColumns('Cafe\u0301'), textColumns('CAFÉ'));
    expect(validateMessage(''), isNotNull);
    expect(validateMessage('HELLO🙂'), isNotNull);
    expect(validateMessage('A' * 61), isNotNull);
    expect(textColumns('E').first, 0xfe);
  });
  test('arabe retiré, autres alphabets conservés', () {
    expect(PanelAlphabet.values.map((value) => value.label),
        ['Latin', 'Cyrillique', 'Grec', 'Hébreu', 'Japonais', 'Coréen']);
    expect(alphabetForMessage('مرحبا'), isNull);
    expect(alphabetForMessage('שלום'), PanelAlphabet.hebrew);
    expect(alphabetForMessage('안녕하세요'), PanelAlphabet.korean);
  });
  test('pictogrammes soleil et clin d’œil identiques à iOS', () {
    expect(pixelIcons[3].rows, [0x18, 0x5a, 0x3c, 0xff, 0xff, 0x3c, 0x5a, 0x18]);
    expect(pixelIcons[4].rows, [0x3c, 0x42, 0xad, 0x81, 0xa5, 0x99, 0x42, 0x3c]);
  });
  test('luminosité et connexion de démonstration', () async {
    expect(encodeCommand('S', 1, '7:50:0:0:1'), [[0x0a, 7]]);
    final demo = DemoTransport();
    await expectLater(demo.send('T', 'MERCI'), throwsStateError);
    await demo.connect(const PanelDevice('demo', 'Démo', -40));
    await demo.send('T', 'MERCI');
    expect(demo.commands, ['T:MERCI']);
    await demo.disconnect();
    await demo.dispose();
  });
}
