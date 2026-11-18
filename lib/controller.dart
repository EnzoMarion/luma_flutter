import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_transport.dart';
import 'protocol.dart';
import 'transport.dart';

enum LinkState { idle, scanning, connecting, connected, empty, offline, error }

class LumaController extends ChangeNotifier {
  LumaController({PanelTransport Function()? transportFactory})
      : _transportFactory = transportFactory ?? BleTransport.new;

  final PanelTransport Function() _transportFactory;
  PanelTransport? _transport;
  StreamSubscription<PanelDevice>? _scan;
  StreamSubscription<bool>? _connection;
  Timer? _scanTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 3;
  bool _disposed = false;
  int _operation = 0;
  LinkState state = LinkState.idle;
  bool demo = false;
  bool busy = false;
  String? error;
  PanelDevice? selected;
  final Map<String, PanelDevice> devices = {};
  PanelSettings settings = const PanelSettings();
  PanelAlphabet alphabetForText(String text) =>
      validateMessage(text, settings.alphabet) == null
          ? settings.alphabet
          : alphabetForMessage(text) ?? settings.alphabet;
  PanelAlphabet get messageAlphabet => alphabetForText(message);
  List<String> favorites = ['MERCI', 'BONJOUR', 'À BIENTÔT'];
  String message = 'MERCI';
  int icon = 0;
  int page = 0;
  String? _displayedKind;
  String _displayedPayload = '';
  bool get connected => state == LinkState.connected;
  int get reconnectAttempts => _reconnectAttempts;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAlphabetName = prefs.getString('luma.alphabet_name');
      final legacyAlphabetIndex = prefs.getInt('luma.alphabet') ?? 0;
      final alphabet = savedAlphabetName != null
          ? PanelAlphabet.values.firstWhere(
              (value) => value.name == savedAlphabetName,
              orElse: () => PanelAlphabet.latin,
            )
          : switch (legacyAlphabetIndex) {
              1 => PanelAlphabet.cyrillic,
              2 => PanelAlphabet.greek,
              3 => PanelAlphabet.hebrew,
              5 => PanelAlphabet.japanese,
              7 => PanelAlphabet.korean,
              _ => PanelAlphabet.latin,
            };
      settings = settings.copyWith(alphabet: alphabet);
      final saved = prefs.getStringList('favorites');
      if (saved != null)
        favorites = saved
            .where((s) => alphabetForMessage(s) != null)
            .map(normalizeMessage)
            .toSet()
            .take(20)
            .toList();
      final savedMessage = prefs.getString('luma.message');
      if (savedMessage != null && alphabetForMessage(savedMessage) != null) {
        message = savedMessage;
      }
      final brightness = prefs.getInt('luma.brightness') ?? settings.brightness;
      final speed = prefs.getInt('luma.speed') ?? settings.speedMs;
      final mode = prefs.getInt('luma.mode') ?? settings.mode.index;
      icon =
          (prefs.getInt('luma.icon') ?? icon).clamp(0, pixelIcons.length - 1);
      settings = settings.copyWith(
        brightness: brightness.clamp(0, 15),
        speedMs: speed.clamp(20, 200),
        mode: ScrollMode.values[mode.clamp(0, ScrollMode.values.length - 1)],
        power: prefs.getBool('luma.power') ?? true,
      );
      _emit();
    } catch (_) {
      /* Le contrôle du panneau reste utilisable sans stockage. */
    }
  }

  Future<void> toggleFavorite() async {
    final detectedAlphabet = alphabetForMessage(message);
    if (detectedAlphabet == null) {
      error = validateMessage(message, settings.alphabet);
      _emit();
      return;
    }
    final normalized = normalizeMessage(message);
    if (favorites.contains(normalized)) {
      favorites.remove(normalized);
    } else {
      if (favorites.length >= 20) {
        error =
            '20 messages favoris maximum. Retire-en un pour en ajouter un autre.';
        _emit();
        return;
      }
      favorites = [...favorites, normalized];
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
    final subscription = _scan;
    _scan = null;
    await subscription?.cancel();
  }

  Future<void> search({required bool demonstration}) async {
    final generation = ++_operation;
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    await _stopScan();
    await _connection?.cancel();
    await _transport?.dispose();
    if (_disposed || generation != _operation) return;
    demo = demonstration;
    _transport = demo ? DemoTransport() : _transportFactory();
    devices.clear();
    error = null;
    state = LinkState.scanning;
    _emit();
    _connection = _transport!.connection.listen((up) {
      if (!up && state == LinkState.connected) {
        state = LinkState.offline;
        error = 'Connexion perdue. Votre message reste disponible.';
        _emit();
        _scheduleReconnect();
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

  void _scheduleReconnect() {
    if (_disposed ||
        demo ||
        selected == null ||
        _reconnectAttempts >= maxReconnectAttempts) return;
    _reconnectTimer?.cancel();
    final attempt = ++_reconnectAttempts;
    final generation = _operation;
    _reconnectTimer = Timer(Duration(seconds: attempt * 2), () {
      if (_disposed || generation != _operation || state != LinkState.offline) {
        return;
      }
      unawaited(connect(selected!, automatic: true));
    });
    _emit();
  }

  Future<void> reconnect() async {
    final device = selected;
    if (device == null) {
      await search(demonstration: false);
      return;
    }
    await connect(device);
  }

  Future<void> connect(PanelDevice device, {bool automatic = false}) async {
    if (state == LinkState.connecting) return;
    final generation = ++_operation;
    _reconnectTimer?.cancel();
    if (!automatic) _reconnectAttempts = 0;
    await _stopScan();
    selected = device;
    state = LinkState.connecting;
    error = null;
    _emit();
    try {
      await _transport!.connect(device);
      if (_disposed || generation != _operation) return;
      state = LinkState.connected;
      _reconnectAttempts = 0;
      try {
        await _transport!.sendPackets([clockSyncPacket(DateTime.now())]);
      } catch (e) {
        error =
            'Panneau connecté ; synchronisation de l’heure impossible : ${_friendly(e)}';
      }
    } catch (e) {
      if (_disposed || generation != _operation) return;
      error = _friendly(e);
      state = automatic ? LinkState.offline : LinkState.error;
      if (automatic) _scheduleReconnect();
    }
    _emit();
  }

  Future<bool> send(String kind, [String payload = '']) async {
    if (!connected || busy) return false;
    busy = true;
    error = null;
    _emit();
    try {
      if (kind == 'T' || kind == 'I' || kind == 'D') {
        final brightness = !settings.power && settings.brightness == 0
            ? 1
            : settings.brightness;
        await _transport!.send(
            'S',
            '$brightness:${settings.speedMs}:${settings.mode.index}:0:1',
            settings.speedMs,
            settings.mode,
            settings.alphabet);
        settings = settings.copyWith(power: true, brightness: brightness);
        unawaited(_saveDraft());
      }
      final effectivePayload = kind == 'S' && !settings.power
          ? '0:${settings.speedMs}:${settings.mode.index}:0:0'
          : payload;
      await _transport!.send(
          kind,
          effectivePayload,
          settings.speedMs,
          settings.mode,
          kind == 'T' ? alphabetForText(effectivePayload) : settings.alphabet);
      if (kind == 'C') {
        await _transport!.send(
            'S',
            '0:${settings.speedMs}:${settings.mode.index}:0:0',
            settings.speedMs,
            settings.mode,
            settings.alphabet);
        settings = settings.copyWith(power: false);
        unawaited(_saveDraft());
      }
      if (kind == 'S' && settings.power && _displayedKind != null) {
        await _transport!.send(
            _displayedKind!,
            _displayedPayload,
            settings.speedMs,
            settings.mode,
            _displayedKind == 'T'
                ? alphabetForText(_displayedPayload)
                : settings.alphabet);
      } else if (kind == 'T' || kind == 'I' || kind == 'D') {
        _displayedKind = kind;
        _displayedPayload = payload;
      } else if (kind == 'C') {
        _displayedKind = null;
        _displayedPayload = '';
      }
      return true;
    } catch (e) {
      error = _friendly(e);
      return false;
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<bool> sendPackets(List<List<int>> packets) async {
    if (!connected || busy) return false;
    busy = true;
    error = null;
    _emit();
    try {
      await _transport!.sendPackets(packets);
      return true;
    } catch (e) {
      error = _friendly(e);
      return false;
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<bool> sendLive(List<int> packet) async {
    if (!connected || packet.isEmpty || packet.length > 20) return false;
    try {
      await _transport!.sendLive(packet);
      return true;
    } catch (e) {
      error = _friendly(e);
      _emit();
      return false;
    }
  }

  Future<void> disconnect() async {
    ++_operation;
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    state = LinkState.idle;
    await _stopScan();
    await _transport?.disconnect();
    devices.clear();
    selected = null;
    error = null;
    _emit();
  }

  void updateMessage(String value) {
    message = value;
    unawaited(_saveDraft());
    _emit();
  }

  void selectIcon(int value) {
    icon = value;
    unawaited(_saveDraft());
    _emit();
  }

  void selectPage(int value) {
    page = value;
    error = null;
    _emit();
  }

  void updateSettings(PanelSettings value) {
    settings = value;
    unawaited(_saveDraft());
    _emit();
  }

  Future<void> _saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('luma.message', message);
      await prefs.setInt('luma.brightness', settings.brightness);
      await prefs.setInt('luma.speed', settings.speedMs);
      await prefs.setInt('luma.mode', settings.mode.index);
      await prefs.setInt('luma.alphabet', settings.alphabet.index);
      await prefs.setString('luma.alphabet_name', settings.alphabet.name);
      await prefs.setBool('luma.power', settings.power);
      await prefs.setInt('luma.icon', icon);
    } catch (_) {
      error = 'Impossible de sauvegarder les réglages.';
      _emit();
    }
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
    _reconnectTimer?.cancel();
    unawaited(_scan?.cancel());
    unawaited(_connection?.cancel());
    unawaited(_transport?.dispose());
    super.dispose();
  }
}
