import 'dart:async';

import 'protocol.dart';

class PanelDevice {
  final String id;
  final String name;
  final int rssi;
  const PanelDevice(this.id, this.name, this.rssi);
}

abstract class PanelTransport {
  Stream<PanelDevice> scan();
  Stream<bool> get connection;
  Future<void> connect(PanelDevice device);
  Future<void> send(String kind, [String payload = '']);
  Future<void> disconnect();
  Future<void> dispose();
}

class DemoTransport implements PanelTransport {
  final _connection = StreamController<bool>.broadcast();
  bool _connected = false;
  final List<String> commands = [];
  @override
  Stream<bool> get connection => _connection.stream;
  @override
  Stream<PanelDevice> scan() async* {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    yield const PanelDevice('demo', 'Luma rouge · Démonstration', -45);
  }

  @override
  Future<void> connect(PanelDevice device) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    _connected = true;
    _connection.add(true);
  }

  @override
  Future<void> send(String kind, [String payload = '']) async {
    if (!_connected) throw StateError('Panneau déconnecté');
    encodeCommand(kind, 1, payload);
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
