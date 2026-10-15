import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'protocol.dart';
import 'transport.dart';

class BleTransport implements PanelTransport {
  final _ble = FlutterReactiveBle();
  final _connection = StreamController<bool>.broadcast();
  StreamSubscription<ConnectionStateUpdate>? _link;
  StreamSubscription<List<int>>? _notifications;
  final Map<int, Completer<void>> _pending = {};
  String? _device;
  String _buffer = '';
  int _sequence = 0;
  bool _sending = false;
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
    yield* _ble
        .scanForDevices(
          withServices: [Uuid.parse(serviceUuid)],
          scanMode: ScanMode.lowLatency,
        )
        .map(
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
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('Connexion interrompue.'));
    }
    _pending.clear();
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
            ) &&
            s.characteristics.any(
              (c) => c.characteristicId == Uuid.parse(notifyUuid),
            ),
      );
      if (!valid)
        throw StateError(
          'Le firmware de ce panneau ne correspond pas au protocole Luma v1.',
        );
      _buffer = '';
      _notifications = _ble
          .subscribeToCharacteristic(_characteristic(notifyUuid))
          .listen(
            _receive,
            onError: (Object e) {
              _failPending();
              _connection.add(false);
            },
          );
      // Le premier ping attend la mise en place de l'abonnement aux notifications.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      try {
        await send('P');
      } on TimeoutException {
        await send('P');
      }
      _connection.add(true);
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  void _receive(List<int> bytes) {
    _buffer += ascii.decode(bytes, allowInvalid: true);
    if (_buffer.length > 256) {
      _buffer = '';
      return;
    }
    while (_buffer.contains('\n')) {
      final end = _buffer.indexOf('\n');
      final line = _buffer.substring(0, end).trim();
      _buffer = _buffer.substring(end + 1);
      final fields = line.split(':');
      if (fields.length < 2) continue;
      final id = int.tryParse(fields[1]);
      final c = _pending.remove(id);
      if (c == null || c.isCompleted) continue;
      if (fields[0] == 'OK') {
        c.complete();
      } else {
        c.completeError(StateError('Le panneau a refusé la commande : $line'));
      }
    }
  }

  @override
  Future<void> send(String kind, [String payload = '']) async {
    if (_device == null) throw StateError('Panneau déconnecté.');
    if (_sending) throw StateError('Un envoi est déjà en cours.');
    final id = _sequence = (_sequence % 65535) + 1;
    final chunks = encodeCommand(kind, id, payload);
    _sending = true;
    final completion = Completer<void>();
    _pending[id] = completion;
    // Le gestionnaire est attaché immédiatement, même si la liaison tombe pendant l'écriture.
    Object? ackError;
    final acknowledgement = completion.future
        .timeout(const Duration(seconds: 5))
        .catchError((Object e) {
          ackError = e;
        });
    try {
      for (final bytes in chunks) {
        await _ble
            .writeCharacteristicWithResponse(
              _characteristic(writeUuid),
              value: bytes,
            )
            .timeout(const Duration(seconds: 5));
      }
      await acknowledgement;
      if (ackError != null) throw ackError!;
    } finally {
      _pending.remove(id);
      if (!completion.isCompleted) completion.complete();
      _sending = false;
    }
  }

  @override
  Future<void> disconnect() async {
    await _notifications?.cancel();
    _notifications = null;
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
