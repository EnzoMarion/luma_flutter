import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_transport.dart';
import 'protocol.dart';
import 'transport.dart';

enum LinkState { idle, scanning, connecting, connected, empty, offline, error }

class LumaController extends ChangeNotifier {
  PanelTransport? _transport;
  StreamSubscription<PanelDevice>? _scan;
  StreamSubscription<bool>? _connection;
  Timer? _scanTimer;
  bool _disposed = false;
  int _operation = 0;
  LinkState state = LinkState.idle;
  bool demo = false;
  bool busy = false;
  String? error;
  PanelDevice? selected;
  final Map<String, PanelDevice> devices = {};
  PanelSettings settings = const PanelSettings();
  List<String> favorites = ['MERCI', 'BONJOUR', 'A BIENTOT'];
  String message = 'MERCI';
  int icon = 0;
  int page = 0;
  bool get connected => state == LinkState.connected;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('favorites');
      if (saved != null)
        favorites = saved
            .where((s) => validateMessage(s) == null)
            .take(8)
            .toList();
      _emit();
    } catch (_) {
      /* Le contrôle du panneau reste utilisable sans stockage. */
    }
  }

  Future<void> toggleFavorite() async {
    if (validateMessage(message) != null) {
      error = validateMessage(message);
      _emit();
      return;
    }
    if (favorites.contains(message)) {
      favorites.remove(message);
    } else {
      favorites = [...favorites, message];
      if (favorites.length > 8) favorites.removeAt(0);
    }
    _emit();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('favorites', favorites);
    } catch (_) {
      error = 'Favori conservé pour cette session uniquement.';
      _emit();
    }
  }

  Future<void> _stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    await _scan?.cancel();
    _scan = null;
  }

  Future<void> search({required bool demonstration}) async {
    final generation = ++_operation;
    await _stopScan();
    await _connection?.cancel();
    await _transport?.dispose();
    if (_disposed || generation != _operation) return;
    demo = demonstration;
    _transport = demo ? DemoTransport() : BleTransport();
    devices.clear();
    error = null;
    state = LinkState.scanning;
    _emit();
    _connection = _transport!.connection.listen((up) {
      if (!up && state == LinkState.connected) {
        state = LinkState.offline;
        error = 'Le lien s’est interrompu. Votre message reste disponible.';
        _emit();
      }
    });
    _scan = _transport!.scan().listen(
      (device) {
        if (generation != _operation) return;
        devices[device.id] = device;
        _emit();
      },
      onError: (Object e) {
        if (generation != _operation) return;
        error = _friendly(e);
        state = LinkState.error;
        unawaited(_stopScan());
        _emit();
      },
      onDone: () {
        if (generation == _operation) _finishScan();
      },
    );
    _scanTimer = Timer(const Duration(seconds: 10), () {
      if (generation == _operation) _finishScan();
    });
  }

  void _finishScan() {
    unawaited(_stopScan());
    if (state != LinkState.scanning) return;
    state = devices.isEmpty ? LinkState.empty : LinkState.idle;
    _emit();
  }

  Future<void> connect(PanelDevice device) async {
    if (state == LinkState.connecting) return;
    final generation = ++_operation;
    await _stopScan();
    selected = device;
    state = LinkState.connecting;
    error = null;
    _emit();
    try {
      await _transport!.connect(device);
      if (_disposed || generation != _operation) return;
      state = LinkState.connected;
    } catch (e) {
      if (_disposed || generation != _operation) return;
      error = _friendly(e);
      state = LinkState.error;
    }
    _emit();
  }

  Future<bool> send(String kind, [String payload = '']) async {
    if (!connected || busy) return false;
    busy = true;
    error = null;
    _emit();
    try {
      await _transport!.send(kind, payload);
      return true;
    } catch (e) {
      error = _friendly(e);
      return false;
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> disconnect() async {
    ++_operation;
    await _stopScan();
    await _transport?.disconnect();
    state = LinkState.idle;
    devices.clear();
    selected = null;
    error = null;
    _emit();
  }

  void updateMessage(String value) {
    message = value;
    _emit();
  }

  void selectIcon(int value) {
    icon = value;
    _emit();
  }

  void selectPage(int value) {
    page = value;
    error = null;
    _emit();
  }

  void updateSettings(PanelSettings value) {
    settings = value;
    _emit();
  }

  static String _friendly(Object e) => e is TimeoutException
      ? 'Le panneau ne répond pas. Rapprochez-vous puis réessayez.'
      : e
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Invalid argument(s): ', '');
  @override
  void dispose() {
    _disposed = true;
    ++_operation;
    _scanTimer?.cancel();
    unawaited(_scan?.cancel());
    unawaited(_connection?.cancel());
    unawaited(_transport?.dispose());
    super.dispose();
  }
}
