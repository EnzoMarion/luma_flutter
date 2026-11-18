import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/controller.dart';
import 'package:luma/protocol.dart';
import 'package:luma/transport.dart';

class _FakePanelTransport implements PanelTransport {
  final _connection = StreamController<bool>.broadcast();
  int connections = 0;
  int failuresRemaining = 0;
  @override
  Stream<bool> get connection => _connection.stream;
  @override
  Stream<PanelDevice> scan() async* {
    yield const PanelDevice('panel', 'Luma test', -40);
  }

  @override
  Future<void> connect(PanelDevice device) async {
    connections++;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('Panneau indisponible');
    }
    _connection.add(true);
  }

  void drop() => _connection.add(false);
  @override
  Future<void> disconnect() async => _connection.add(false);
  @override
  Future<void> dispose() => _connection.close();
  @override
  Future<void> send(String kind,
      [String payload = '',
      int speedMs = 100,
      ScrollMode mode = ScrollMode.auto,
      PanelAlphabet alphabet = PanelAlphabet.latin]) async {}
  @override
  Future<void> sendPackets(List<List<int>> packets) async {}
  @override
  Future<void> sendLive(List<int> packet) async {}
}

void main() {
  testWidgets('reconnexion limitée et annulée à la déconnexion',
      (tester) async {
    final transport = _FakePanelTransport();
    final controller = LumaController(transportFactory: () => transport);
    await controller.search(demonstration: false);
    await controller.connect(const PanelDevice('panel', 'Luma test', -40));
    expect(controller.connected, isTrue);
    transport.drop();
    await tester.pump();
    expect(controller.state, LinkState.offline);
    expect(controller.reconnectAttempts, 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(controller.connected, isTrue);
    expect(transport.connections, 2);
    transport.drop();
    await tester.pump();
    await controller.disconnect();
    await tester.pump(const Duration(seconds: 3));
    expect(controller.state, LinkState.idle);
    expect(transport.connections, 2);
    controller.dispose();
  });
  testWidgets('trois essais automatiques au maximum', (tester) async {
    final transport = _FakePanelTransport();
    final controller = LumaController(transportFactory: () => transport);
    await controller.search(demonstration: false);
    await controller.connect(const PanelDevice('panel', 'Luma test', -40));
    transport.failuresRemaining = 3;
    transport.drop();
    await tester.pump();
    for (final delay in [2, 4, 6]) {
      await tester.pump(Duration(seconds: delay));
      await tester.pump();
    }
    expect(controller.state, LinkState.offline);
    expect(controller.reconnectAttempts, LumaController.maxReconnectAttempts);
    expect(transport.connections, 4);
    await tester.pump(const Duration(seconds: 10));
    expect(transport.connections, 4);
    controller.dispose();
  });
  test('anciens index et messages arabes sont migrés', () async {
    SharedPreferences.setMockInitialValues({
      'luma.alphabet': 5,
      'luma.message': 'مرحبا',
      'favorites': ['MERCI', 'مرحبا'],
    });
    final controller = LumaController();
    await controller.loadFavorites();
    expect(controller.settings.alphabet, PanelAlphabet.japanese);
    expect(controller.message, 'MERCI');
    expect(controller.favorites, ['MERCI']);
    controller.dispose();
  });
  test('restaure message, réglages et favoris', () async {
    SharedPreferences.setMockInitialValues({
      'luma.message': 'À BIENTÔT',
      'luma.brightness': 10,
      'luma.speed': 20,
      'luma.mode': ScrollMode.fixed.index,
      'luma.power': false,
      'luma.icon': 3,
      'favorites': ['MERCI', 'À BIENTÔT'],
    });
    final controller = LumaController();
    await controller.loadFavorites();
    expect(controller.message, 'À BIENTÔT');
    expect(controller.settings.brightness, 10);
    expect(controller.settings.speedMs, 20);
    expect(controller.settings.mode, ScrollMode.fixed);
    expect(controller.settings.power, isFalse);
    expect(controller.icon, 3);
    expect(controller.favorites, ['MERCI', 'À BIENTÔT']);
    await controller.toggleFavorite();
    expect((await SharedPreferences.getInstance()).getStringList('favorites'),
        ['MERCI']);
    controller.updateMessage('merci');
    await controller.toggleFavorite();
    expect(controller.favorites, isEmpty);
    controller.dispose();
  });
}
