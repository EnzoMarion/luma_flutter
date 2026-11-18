import 'dart:async';

import 'protocol.dart';
import 'raster_font.dart';

class PanelDevice {
  final String id;
  final String name;
  final int rssi;
  final PanelHardware hardware;
  const PanelDevice(this.id, this.name, this.rssi,
      {this.hardware = PanelHardware.max7219});
}

abstract class PanelTransport {
  Stream<PanelDevice> scan();
  Stream<bool> get connection;
  Future<void> connect(PanelDevice device);
  Future<void> send(String kind,
      [String payload = '',
      int speedMs = 100,
      ScrollMode mode = ScrollMode.auto,
      PanelAlphabet alphabet = PanelAlphabet.latin]);
  Future<void> sendPackets(List<List<int>> packets);
  Future<void> sendLive(List<int> packet);
  Future<void> disconnect();
  Future<void> dispose();
}

class DemoTransport implements PanelTransport {
  final _connection = StreamController<bool>.broadcast();
  bool _connected = false;
  PanelHardware _hardware = PanelHardware.max7219;
  final List<String> commands = [];
  @override
  Future<void> sendLive(List<int> packet) async {
    if (!_connected) throw StateError('Panneau déconnecté');
    commands.add('live:${packet.first}:${packet.length}');
  }

  @override
  Future<void> sendPackets(List<List<int>> packets) async {
    if (!_connected) throw StateError('Panneau déconnecté');
    commands.add('paquets:${packets.length}');
  }

  @override
  Stream<bool> get connection => _connection.stream;
  @override
  Stream<PanelDevice> scan() async* {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    yield const PanelDevice('demo', 'Luma RGB · Démonstration', -45,
        hardware: PanelHardware.ws2812b);
  }

  @override
  Future<void> connect(PanelDevice device) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    _hardware = device.hardware;
    _connected = true;
    _connection.add(true);
  }

  @override
  Future<void> send(String kind,
      [String payload = '',
      int speedMs = 100,
      ScrollMode mode = ScrollMode.auto,
      PanelAlphabet alphabet = PanelAlphabet.latin]) async {
    if (!_connected) throw StateError('Panneau déconnecté');
    if (kind == 'T' && requiresRasterFont(payload, alphabet)) {
      final error = validateMessage(payload, alphabet);
      if (error != null) throw ArgumentError(error);
      final columns = await rasterTextColumns(payload, alphabet);
      final pages = mode == ScrollMode.appearance
          ? await Future.wait(appearancePages(payload, alphabet)
              .map((page) => rasterTextColumns(page, alphabet)))
          : <List<int>>[];
      encodeRenderedText(columns, speedMs, mode, pages, _hardware);
    } else {
      encodeCommand(kind, 1, payload, speedMs, mode, alphabet, _hardware);
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
    commands.add('$kind:$payload');
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _connection.add(false);
  }

  @override
  Future<void> dispose() async {
    await _connection.close();
  }
}
