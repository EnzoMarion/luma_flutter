import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'controller.dart';
import 'protocol.dart';

List<int> modePacket(int mode, [int seconds = 0]) {
  if (mode < 1 || mode > 9 || seconds < 0 || seconds > 5999 || (mode == 3 && seconds == 0)) {
    throw ArgumentError('Mode ou durée invalide');
  }
  return [0x40, mode, seconds & 255, (seconds >> 8) & 255, (seconds >> 16) & 255, (seconds >> 24) & 255];
}

List<int> clockPacket(DateTime now) {
  return clockSyncPacket(now);
}

List<int> schedulePacket(int index, int hour, int minute, String text) {
  final normalized = normalizeMessage(text);
  if (index < 0 || index > 1 || hour < 0 || hour > 23 || minute < 0 || minute > 59 ||
      normalized.length > 16 || !RegExp(r'^[A-Z0-9 :/]*$').hasMatch(normalized)) {
    throw ArgumentError('Utilise 16 caractères ASCII maximum : lettres, chiffres, espaces, : et /.');
  }
  return [0x44, index, hour, minute, ...ascii.encode(normalized)];
}

class ActivitiesPage extends StatefulWidget {
  final LumaController controller;
  const ActivitiesPage({super.key, required this.controller});
  @override
  State<ActivitiesPage> createState() => _ActivitiesPageState();
}

class _ActivitiesPageState extends State<ActivitiesPage> with WidgetsBindingObserver {
  static const _audio = MethodChannel('fr.projetled.luma/audio');
  int minutes = 5;
  int animation = 5;
  int maximumRpm = 6000;
  bool sending = false;
  bool audioActive = false;
  List<int> audioLevels = List<int>.filled(32, 0);
  String audioState = 'Arrêté';
  String obdState = 'Arrêté';
  String weatherState = '';
  String host = '';
  int rpm = 0;
  Socket? obdSocket;
  StreamIterator<List<int>>? obdInput;
  bool obdActive = false;
  bool obdPolling = false;
  Timer? obdLoop;
  final hostInput = TextEditingController();
  final schedules = List.generate(2, (i) => _ScheduleDraft(
    hour: i == 0 ? 8 : 20,
    minute: 0,
    text: i == 0 ? 'BONJOUR' : 'BONNE NUIT',
  ));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSchedules();
    _audio.setMethodCallHandler((call) async {
      if (call.method == 'levels' && audioActive && call.arguments is List) {
        final levels = (call.arguments as List).map((v) => (v as num).toInt().clamp(0, 8)).toList();
        if (levels.length == 32) {
          if (mounted) setState(() => audioLevels = levels);
          final packet = <int>[0x50];
          for (var i = 0; i < 32; i += 2) {
            packet.add((levels[i] << 4) | levels[i + 1]);
          }
          unawaited(widget.controller.sendLive(packet));
        }
      }
    });
  }

  Future<void> _loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < 2; i++) {
        schedules[i].hour = prefs.getInt('luma.schedule.$i.hour') ?? schedules[i].hour;
        schedules[i].minute = prefs.getInt('luma.schedule.$i.minute') ?? schedules[i].minute;
        schedules[i].text.text = prefs.getString('luma.schedule.$i.text') ?? schedules[i].text.text;
      }
    });
  }

  Future<void> send(List<List<int>> packets, {String label = 'Commande'}) async {
    if (sending) return;
    setState(() => sending = true);
    final success = await widget.controller.sendPackets(packets);
    if (!mounted) return;
    setState(() => sending = false);
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      icon: Icon(success ? Icons.check_circle_outline : Icons.error_outline),
      title: Text(success ? '$label envoyé' : 'Envoi impossible'),
      content: Text(success ? 'Transfert Bluetooth terminé. L’affichage sur le panneau n’est pas confirmé.' : widget.controller.error ?? 'Connecte le panneau puis réessaie.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Terminé'))],
    ));
  }

  Future<void> _program(int index) async {
    final item = schedules[index];
    List<int> packet;
    try { packet = schedulePacket(index, item.hour, item.minute, item.text.text); }
    catch (e) { _message('$e'); return; }
    final ok = await widget.controller.sendPackets([packet]);
    if (!mounted) return;
    if (ok) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('luma.schedule.$index.hour', item.hour);
      await prefs.setInt('luma.schedule.$index.minute', item.minute);
      await prefs.setString('luma.schedule.$index.text', item.text.text);
      _message(item.text.text.isEmpty ? 'Message programmé désactivé.' : 'Message programmé envoyé à l’ESP32. Il se déclenche seulement pendant la connexion Bluetooth.');
    } else { _message(widget.controller.error ?? 'Connecte le panneau puis réessaie.'); }
  }

  Future<void> _weather() async {
    if (sending) return;
    setState(() => weatherState = 'Recherche…');
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': '45.1885', 'longitude': '5.7245', 'current': 'temperature_2m,weather_code',
      });
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) throw HttpException('Service météo indisponible (${response.statusCode}).');
      final data = jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final current = data['current'] as Map<String, dynamic>;
      final temp = (current['temperature_2m'] as num).round();
      final code = (current['weather_code'] as num).toInt();
      final condition = switch (code) {
        0 => 'SOLEIL', 1 || 2 => 'NUAGEUX', 3 => 'COUVERT', 45 || 48 => 'BROUILLARD',
        51 || 53 || 55 || 56 || 57 || 61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => 'PLUIE',
        71 || 73 || 75 || 77 || 85 || 86 => 'NEIGE', 95 || 96 || 99 => 'ORAGE', _ => 'METEO',
      };
      final text = 'GRENOBLE ${temp}C $condition';
      final content = encodeCommand('T', 1, text, widget.controller.settings.speedMs, ScrollMode.appearance);
      final packets = [[0x0A, widget.controller.settings.brightness], ...content];
      final ok = await widget.controller.sendPackets(packets);
      if (!mounted) return;
      setState(() => weatherState = ok ? text : 'Envoi au panneau impossible.');
    } catch (e) {
      if (mounted) setState(() => weatherState = 'Météo indisponible : $e');
    } finally { client?.close(force: true); }
  }

  Future<String> _readPrompt(StreamIterator<List<int>> input) async {
    final buffer = StringBuffer();
    while (await input.moveNext().timeout(const Duration(seconds: 2))) {
      final chunk = latin1.decode(input.current, allowInvalid: true);
      buffer.write(chunk);
      if (buffer.toString().contains('>')) break;
    }
    return buffer.toString();
  }

  Future<void> _startObd() async {
    final address = hostInput.text.trim();
    if (address.isEmpty || address.length > 253 || !RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(address)) {
      _message('Entre l’adresse IP ou le nom du Mac affiché par le simulateur.'); return;
    }
    await _stopAudio();
    setState(() { obdState = 'Connexion…'; host = address; });
    try {
      final socket = await Socket.connect(address, 35000, timeout: const Duration(seconds: 5));
      obdSocket = socket;
      obdInput = StreamIterator<List<int>>(socket);
      for (final command in ['ATZ\r', 'ATE0\r']) {
        socket.write(command); await socket.flush(); await _readPrompt(obdInput!);
      }
      socket.write('010C\r'); await socket.flush(); await _readPrompt(obdInput!);
      final ok = await widget.controller.sendPackets([[0x61, 1]]);
      if (!ok) throw StateError(widget.controller.error ?? 'Activation Bluetooth impossible.');
      if (!mounted) return;
      setState(() { obdActive = true; obdState = 'En attente des données'; });
      obdLoop = Timer.periodic(const Duration(milliseconds: 200), (_) => unawaited(_pollObd()));
    } catch (e) {
      await _stopObd(sendOff: false);
      if (mounted) setState(() => obdState = 'Connexion impossible : $e');
    }
  }

  Future<void> _pollObd() async {
    final socket = obdSocket; final input = obdInput;
    if (!obdActive || obdPolling || socket == null || input == null) return;
    if (!widget.controller.connected) { await _stopObd(sendOff: false); return; }
    obdPolling = true;
    try {
      socket.write('010C\r'); await socket.flush();
      final response = await _readPrompt(input);
      final match = RegExp(r'41\\s*0C\\s*([0-9A-Fa-f]{2})\\s*([0-9A-Fa-f]{2})').firstMatch(response);
      if (match == null) return;
      final value = (int.parse(match.group(1)!, radix: 16) * 256 + int.parse(match.group(2)!, radix: 16)) ~/ 4;
      if (!mounted || !obdActive) return;
      setState(() { rpm = value; obdState = 'Données simulées'; });
      await widget.controller.sendLive([0x60, value & 255, (value >> 8) & 255, maximumRpm & 255, (maximumRpm >> 8) & 255]);
    } catch (e) {
      if (mounted) setState(() => obdState = 'Données en attente : $e');
    } finally {
      obdPolling = false;
    }
  }

  Future<void> _stopObd({bool sendOff = true}) async {
    obdActive = false;
    obdLoop?.cancel(); obdLoop = null;
    await obdInput?.cancel(); obdInput = null;
    obdSocket?.destroy(); obdSocket = null;
    if (sendOff && widget.controller.connected) await widget.controller.sendPackets([[0x61, 0]]);
    if (mounted) setState(() { rpm = 0; obdState = 'Arrêté'; });
  }

  Future<void> _startAudio() async {
    await _stopObd();
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) { _message('Autorise le microphone dans les réglages Android pour utiliser le visualiseur.'); return; }
    final ok = await widget.controller.sendPackets([[0x51, 1]]);
    if (!ok) { _message(widget.controller.error ?? 'Connecte le panneau puis réessaie.'); return; }
    try {
      await _audio.invokeMethod<void>('start');
      if (mounted) setState(() { audioActive = true; audioState = 'Écoute locale active'; });
    } on PlatformException catch (e) {
      await widget.controller.sendPackets([[0x51, 0]]);
      if (mounted) setState(() => audioState = 'Microphone indisponible : ${e.message}');
    } on MissingPluginException {
      await widget.controller.sendPackets([[0x51, 0]]);
      if (mounted) setState(() => audioState = 'Visualiseur audio Android indisponible.');
    }
  }

  Future<void> _stopAudio() async {
    if (!audioActive) return;
    audioActive = false;
    try { await _audio.invokeMethod<void>('stop'); } catch (_) {}
    if (widget.controller.connected) {
      await widget.controller.sendPackets([[0x51, 0]]);
    }
    if (mounted) setState(() {
      audioState = 'Arrêté';
      audioLevels = List<int>.filled(32, 0);
    });
  }

  void _message(String text) {
    if (!mounted) return;
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      content: Text(text), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ));
  }

  Widget section(String title, List<Widget> children) => Card(child: Padding(
    padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12), ...children,
    ]),
  ));

  Widget audioMeter() => SizedBox(
    height: 76,
    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (final level in audioLevels)
        Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Container(
            height: 6 + level * 8.0,
            decoration: BoxDecoration(
              color: level == 0 ? const Color(0xff35453b) : const Color(0xffd7ff7f),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        )),
    ]),
  );

  Widget rpmMeter() {
    final lit = (rpm / maximumRpm * 32).floor().clamp(0, 32);
    return Row(children: [
      for (var i = 0; i < 32; i++)
        Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Container(height: 18, decoration: BoxDecoration(
            color: i < lit ? const Color(0xffd7ff7f) : const Color(0xff35453b),
            borderRadius: BorderRadius.circular(3),
          )),
        )),
    ]);
  }

  Widget controls() => Wrap(spacing: 8, children: [
    for (final item in const [(0, 'Pause'), (1, 'Reprendre'), (2, 'Remise à zéro')])
      OutlinedButton(onPressed: sending ? null : () => send([[0x42, item.$1]], label: item.$2), child: Text(item.$2)),
  ]);

  Widget scheduleCard(int index) {
    final item = schedules[index];
    return section(index == 0 ? 'Message du matin' : 'Message du soir', [
      Row(children: [
        Expanded(child: DropdownButtonFormField<int>(initialValue: item.hour, decoration: const InputDecoration(labelText: 'Heure'),
          items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')} h'))],
          onChanged: (v) { if (v != null) setState(() => item.hour = v); })),
        const SizedBox(width: 12),
        Expanded(child: DropdownButtonFormField<int>(initialValue: item.minute, decoration: const InputDecoration(labelText: 'Minute'),
        items: [for (var m = 0; m < 60; m++) DropdownMenuItem(value: m, child: Text('${m.toString().padLeft(2, '0')} min'))],
          onChanged: (v) { if (v != null) setState(() => item.minute = v); })),
      ]),
      const SizedBox(height: 12),
      TextField(controller: item.text, maxLength: 16, textCapitalization: TextCapitalization.characters,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9 :/]'))], decoration: const InputDecoration(labelText: 'Texte programmé')),
      FilledButton(onPressed: sending ? null : () => _program(index), child: Text(item.text.text.isEmpty ? 'Désactiver' : 'Programmer')),
    ]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) { unawaited(_stopAudio()); unawaited(_stopObd()); }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audio.setMethodCallHandler(null);
    unawaited(_stopAudio()); unawaited(_stopObd());
    hostInput.dispose(); for (final item in schedules) { item.text.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Activités')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Les activités avancées nécessitent le firmware ESP32-C3 récent de ton collègue.'),
      section('Horloge', [
        const Text('Heure, date et jour alternent sur le panneau.'),
        FilledButton(onPressed: sending ? null : () => send([clockPacket(DateTime.now()), modePacket(1)], label: 'Horloge'), child: const Text('Afficher l’horloge')),
      ]),
      section('Chronomètre', [
        FilledButton(onPressed: sending ? null : () => send([modePacket(2)], label: 'Chronomètre'), child: const Text('Démarrer à zéro')),
        controls(),
      ]),
      section('Minuteur', [
        Row(children: [
          IconButton(onPressed: minutes > 1 ? () => setState(() => minutes--) : null, icon: const Icon(Icons.remove)),
          Text('$minutes min'),
          IconButton(onPressed: minutes < 99 ? () => setState(() => minutes++) : null, icon: const Icon(Icons.add)),
        ]),
        FilledButton(onPressed: sending ? null : () => send([modePacket(3, minutes * 60)], label: 'Minuteur'), child: const Text('Lancer le minuteur')),
        controls(),
      ]),
      section('Pomodoro', [
        const Text('25 minutes de concentration, puis 5 minutes de pause.'),
        FilledButton(onPressed: sending ? null : () => send([modePacket(4, 1500)], label: 'Pomodoro'), child: const Text('Démarrer Pomodoro')),
        controls(),
      ]),
      section('Animations', [
        DropdownButton<int>(value: animation, items: const [
          DropdownMenuItem(value: 5, child: Text('Cœur')), DropdownMenuItem(value: 6, child: Text('Étoiles')),
          DropdownMenuItem(value: 7, child: Text('Pluie')), DropdownMenuItem(value: 8, child: Text('Flèche')),
          DropdownMenuItem(value: 9, child: Text('Surprise')),
        ], onChanged: (v) { if (v != null) setState(() => animation = v); }),
        FilledButton(onPressed: sending ? null : () => send([modePacket(animation)], label: 'Animation'), child: const Text('Afficher l’animation')),
      ]),
      section('Compte-tours OBD simulé', [
        const Text('Le simulateur doit tourner sur le Mac de ton collègue, sur le même Wi-Fi (port 35000). Il ne lit pas une vraie voiture.'),
        TextField(controller: hostInput, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Adresse IP du Mac')),
        Row(children: [const Text('Maximum'), Expanded(child: Slider(value: maximumRpm.toDouble(), min: 1000, max: 12000, divisions: 22, label: '$maximumRpm tr/min', onChanged: (v) => setState(() => maximumRpm = (v / 500).round() * 500))) ]),
        Text('$rpm tr/min · $obdState'),
        rpmMeter(),
        FilledButton(onPressed: obdActive ? () => _stopObd() : _startObd, child: Text(obdActive ? 'Arrêter le simulateur' : 'Connecter le simulateur')),
      ]),
      section('Visualiseur audio', [
        const Text('Le son est analysé localement par le microphone du téléphone. Seules les barres sont envoyées.'),
        audioMeter(),
        Text(audioState),
        FilledButton(onPressed: audioActive ? _stopAudio : _startAudio, child: Text(audioActive ? 'Arrêter le visualiseur' : 'Activer le microphone')),
      ]),
      section('Météo de Grenoble', [
        const Text('La météo est demandée sur Internet uniquement lorsque tu touches le bouton.'),
        if (weatherState.isNotEmpty) Text(weatherState),
        FilledButton(onPressed: _weather, child: const Text('Afficher la météo actuelle')),
      ]),
      scheduleCard(0), scheduleCard(1),
    ]),
  );
}

class _ScheduleDraft {
  int hour;
  int minute;
  final TextEditingController text;
  _ScheduleDraft({required this.hour, required this.minute, required String text}) : text = TextEditingController(text: text);
}
