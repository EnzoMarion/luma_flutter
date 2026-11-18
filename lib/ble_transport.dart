import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'protocol.dart';
import 'raster_font.dart';
import 'transport.dart';

class BleTransport implements PanelTransport {
  final _ble = FlutterReactiveBle();
  final _connection = StreamController<bool>.broadcast();
  StreamSubscription<ConnectionStateUpdate>? _link;
  String? _device;
  bool _sending = false;
  bool _liveSending = false;
  @override
  Stream<bool> get connection => _connection.stream;

  Future<void> _prepare() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw StateError(
        'Le BLE nécessite un téléphone Android ou un iPhone. Utilisez le mode démonstration ici.',
      );
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      final permissions = sdk >= 31
          ? [Permission.bluetoothScan, Permission.bluetoothConnect]
          : [Permission.locationWhenInUse];
      final result = await permissions.request();
      if (result.values.any((p) => !p.isGranted)) {
        throw StateError(
          'Autorisez le Bluetooth dans les réglages du téléphone, puis relancez la recherche.',
        );
      }
    }
    // CoreBluetooth déclenche lui-même la demande iOS via le plugin BLE.
    var status = _ble.status;
    if (status == BleStatus.unknown) {
      status = await _ble.statusStream
          .firstWhere((s) => s != BleStatus.unknown)
          .timeout(const Duration(seconds: 12));
    }
    if (status != BleStatus.ready) {
      throw StateError(
        'Bluetooth indisponible : ${status.name}. Activez-le et vérifiez les autorisations.',
      );
    }
  }

  @override
  Stream<PanelDevice> scan() async* {
    await _prepare();
    yield* _ble.scanForDevices(
      withServices: [Uuid.parse(serviceUuid)],
      scanMode: ScanMode.lowLatency,
    ).map(
      (d) => PanelDevice(
        d.id,
        d.name.isEmpty ? 'Panneau Luma' : d.name,
        d.rssi,
      ),
    );
  }

  QualifiedCharacteristic _characteristic(String uuid) =>
      QualifiedCharacteristic(
        serviceId: Uuid.parse(serviceUuid),
        characteristicId: Uuid.parse(uuid),
        deviceId: _device!,
      );

  void _failPending() {
    // Ce firmware n'expose pas de caractéristique de notification.
  }

  @override
  Future<void> connect(PanelDevice device) async {
    await disconnect();
    await _prepare();
    final ready = Completer<void>();
    _device = device.id;
    _link = _ble
        .connectToDevice(
      id: device.id,
      connectionTimeout: const Duration(seconds: 12),
    )
        .listen(
      (update) {
        if (update.connectionState == DeviceConnectionState.connected) {
          if (!ready.isCompleted) ready.complete();
        } else if (update.connectionState ==
            DeviceConnectionState.disconnected) {
          _device = null;
          _failPending();
          if (!ready.isCompleted)
            ready.completeError(
              StateError('Connexion refusée ou interrompue.'),
            );
          _connection.add(false);
        }
      },
      onError: (Object error) {
        _device = null;
        _failPending();
        if (!ready.isCompleted) ready.completeError(error);
        _connection.add(false);
      },
    );
    try {
      await ready.future.timeout(const Duration(seconds: 15));
      final services = await _ble.discoverServices(device.id);
      final valid = services.any(
        (s) =>
            s.serviceId == Uuid.parse(serviceUuid) &&
            s.characteristics.any(
              (c) => c.characteristicId == Uuid.parse(writeUuid),
            ),
      );
      if (!valid)
        throw StateError(
          'Le firmware de ce panneau ne correspond pas au protocole Luma v1.',
        );
      _connection.add(true);
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  @override
  Future<void> sendPackets(List<List<int>> packets) async {
    if (_device == null) throw StateError('Panneau déconnecté.');
    if (_sending) throw StateError('Un envoi est déjà en cours.');
    _sending = true;
    try {
      for (final bytes in packets) {
        if (bytes.isEmpty || bytes.length > 20)
          throw ArgumentError('Paquet Bluetooth invalide');
        await _ble
            .writeCharacteristicWithResponse(_characteristic(writeUuid),
                value: bytes)
            .timeout(const Duration(seconds: 5));
      }
    } finally {
      _sending = false;
    }
  }

  @override
  Future<void> sendLive(List<int> packet) async {
    if (_device == null) throw StateError('Panneau déconnecté.');
    if (packet.isEmpty || packet.length > 20)
      throw ArgumentError('Paquet Bluetooth invalide');
    if (_sending || _liveSending)
      return; // Les trames audio/OBD en attente sont abandonnées.
    _liveSending = true;
    try {
      await _ble
          .writeCharacteristicWithoutResponse(_characteristic(writeUuid),
              value: packet)
          .timeout(const Duration(milliseconds: 500));
    } finally {
      _liveSending = false;
    }
  }

  @override
  Future<void> send(String kind,
      [String payload = '',
      int speedMs = 100,
      ScrollMode mode = ScrollMode.auto,
      PanelAlphabet alphabet = PanelAlphabet.latin]) async {
    if (_device == null) throw StateError('Panneau déconnecté.');
    final List<List<int>> chunks;
    if (kind == 'T' && requiresRasterFont(payload, alphabet)) {
      final error = validateMessage(payload, alphabet);
      if (error != null) throw ArgumentError(error);
      final columns = await rasterTextColumns(payload, alphabet);
      final pages = mode == ScrollMode.appearance
          ? await Future.wait(appearancePages(payload, alphabet)
              .map((page) => rasterTextColumns(page, alphabet)))
          : <List<int>>[];
      chunks = encodeRenderedText(columns, speedMs, mode, pages);
    } else {
      chunks = encodeCommand(kind, 1, payload, speedMs, mode, alphabet);
    }
    await sendPackets(chunks);
  }

  @override
  Future<void> disconnect() async {
    await _link?.cancel();
    _link = null;
    _device = null;
    _failPending();
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _connection.close();
  }
}
