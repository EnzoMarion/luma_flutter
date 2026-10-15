import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller.dart';
import 'protocol.dart';
import 'pixel_preview.dart';
import 'transport.dart';

const lime = Color(0xffd7ff7f);
const ink = Color(0xff0d1612);
const surface = Color(0xff18251e);
const muted = Color(0xffa4b2a8);
const stroke = Color(0xff35453b);
const red = Color(0xffff7770);
const panelColors = [
  Color(0xffd7ff7f),
  Color(0xffeef3eb),
  Color(0xfff7bc77),
  Color(0xffff7770),
  Color(0xff62b9e8),
  Color(0xffad91f5),
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const LumaApp());
}

class LumaApp extends StatelessWidget {
  const LumaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Luma',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Manrope',
      scaffoldBackgroundColor: ink,
      colorScheme: const ColorScheme.dark(
        primary: lime,
        onPrimary: ink,
        surface: surface,
        onSurface: Color(0xffedf3e9),
        error: red,
      ),
      dividerColor: stroke,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: stroke),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    ),
    home: const LumaHome(),
  );
}

class LumaHome extends StatefulWidget {
  const LumaHome({super.key});
  @override
  State<LumaHome> createState() => _LumaHomeState();
}

class _LumaHomeState extends State<LumaHome> {
  final c = LumaController();
  final input = TextEditingController(text: 'MERCI');
  bool colorPanel = true;
  bool _sendingAction = false;
  int selectedColor = 0;
  Color get previewColor => allowsColor ? panelColors[selectedColor] : red;
  bool get allowsColor => colorPanel;
  bool get messageScrolls => colorPanel
      ? c.message.length * 6 > 8 && c.settings.mode != ScrollMode.fixed
      : c.message.length > 10 && c.settings.mode != ScrollMode.fixed;
  @override
  void initState() {
    super.initState();
    c.loadFavorites();
  }

  @override
  void dispose() {
    c.dispose();
    input.dispose();
    super.dispose();
  }

  Future<void> _send(String kind, [String payload = '']) async {
    if (_sendingAction) return;
    setState(() => _sendingAction = true);
    try {
      if (colorPanel && (kind == 'T' || kind == 'I')) {
        final colorValue = panelColors[selectedColor].value & 0xFFFFFF;
        final hex = colorValue.toRadixString(16).padLeft(6, '0').toUpperCase();
        final colorSent = await c.send('K', hex);
        if (!mounted || !colorSent) return;
      }
      final ok = await c.send(kind, payload);
      if (!mounted || !ok) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: false,
        backgroundColor: surface,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check, color: lime, size: 24),
              const SizedBox(height: 16),
              Text(_sendTitle(kind),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(_sendDetail(kind),
                  style: const TextStyle(color: muted, fontSize: 12, height: 1.4)),
              const SizedBox(height: 18),
              SizedBox(width: double.infinity, child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Terminé'),
              )),
            ],
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingAction = false);
    }
  }

  String _sendTitle(String kind) {
    if (c.demo) return 'Démonstration terminée';
    if (kind == 'I') return '${pixelIcons[c.icon].label} affiché';
    if (kind == 'S') return 'Réglages appliqués';
    if (kind == 'C') return 'Panneau effacé';
    return 'Message affiché';
  }

  String _sendDetail(String kind) {
    if (c.demo) return 'Aucune donnée n’a été envoyée à un panneau réel.';
    if (kind == 'I') return 'Le pictogramme est maintenant sur votre panneau.';
    if (kind == 'S') return 'Les réglages du panneau ont été mis à jour.';
    if (kind == 'C') return 'Toutes les LED sont éteintes. Votre texte reste disponible dans l’application.';
    if (messageScrolls) {
      return '${c.message} défile maintenant sur votre panneau.';
    }
    if (!colorPanel) return '${c.message} est maintenant affiché en rouge.';
    return '${c.message} est maintenant sur votre panneau.';
  }

  Future<void> _confirmClear() async => _send('C');

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final connected = c.connected;
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                    child: Row(
                      children: [
                        const Text(
                          'luma',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.5,
                          ),
                        ),
                        const Text(
                          '·',
                          style: TextStyle(
                            color: lime,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: surface,
                            border: Border.all(color: stroke),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.circle,
                                size: 6,
                                color: connected ? lime : muted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                c.demo
                                    ? 'Démo'
                                    : connected
                                    ? 'Connecté'
                                    : 'Hors ligne',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.bluetooth,
                                size: 14,
                                color: muted,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (c.demo)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'MODE DÉMONSTRATION · SANS MATÉRIEL',
                        style: TextStyle(
                          color: lime,
                          fontSize: 10,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (connected)
                            ..._content()
                          else
                            ..._connectionScreen(),
                          if (c.error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 20),
                              child: _card(
                                child: Text(
                                  c.error!,
                                  style: const TextStyle(color: red),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (connected) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: FilledButton.icon(
                        onPressed:
                            c.busy || _sendingAction ||
                                (c.page == 0 &&
                                    validateMessage(c.message) != null)
                            ? null
                            : () {
                                if (c.page == 0)
                                  _send('T', c.message);
                                else if (c.page == 1)
                                  _send('I', '${c.icon}');
                                else
                                  _send('S', c.settings.payload);
                              },
                        icon: c.busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                c.page == 2 ? Icons.tune : Icons.north_east,
                                size: 17,
                              ),
                        label: Text(
                          c.busy
                              ? 'Envoi en cours…'
                              : c.page == 2
                              ? 'Appliquer les réglages'
                              : c.page == 0 && messageScrolls
                              ? 'Afficher le message défilant'
                              : c.page == 1
                              ? _iconActionLabel()
                              : 'Afficher sur le panneau',
                        ),
                      ),
                    ),
                    if (c.page == 0 || c.page == 2)
                      TextButton(
                        onPressed: c.busy || _sendingAction
                            ? null
                            : c.page == 2 ? _changePanel : _confirmClear,
                        child: Text(
                          c.page == 2 ? 'Changer de panneau' : 'Effacer le panneau',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ),
                    NavigationBar(
                      height: 60,
                      selectedIndex: c.page,
                      onDestinationSelected: c.busy || _sendingAction ? null : c.selectPage,
                      backgroundColor: ink,
                      indicatorColor: const Color(0xff253928),
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.text_fields),
                          label: 'Message',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.tag_faces),
                          label: 'Icônes',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.tune),
                          label: 'Panneau',
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Future<void> _changePanel() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Changer de panneau ?'),
        content: const Text('La connexion actuelle sera fermée.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Rester ici'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Changer de panneau'),
          ),
        ],
      ),
    );
    if (yes == true) await c.disconnect();
  }

  List<Widget> _connectionScreen() {
    final connecting = c.state == LinkState.connecting;
    final scanning = c.state == LinkState.scanning;
    if (connecting) {
      return [
        _title('Un instant de connexion.', 'Quelques secondes pour faire le lien.'),
        const SizedBox(height: 72),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 20),
        Center(child: Text(c.selected?.name ?? 'Luma', style: const TextStyle(color: lime))),
        const SizedBox(height: 24),
        Center(child: TextButton(onPressed: c.disconnect, child: const Text('Annuler'))),
      ];
    }
    final offline = c.state == LinkState.offline;
    final failed = c.state == LinkState.error;
    return [
      _title(offline ? 'Le lien s’est interrompu.' : failed ? 'Connexion impossible' : 'Votre panneau',
          offline ? 'Votre message reste disponible. Reconnectez votre panneau.'
              : failed ? 'Vérifiez le panneau et le Bluetooth, puis réessayez.'
                  : 'Connectez-le une fois. Faites-lui parler.'),
      _preview(connection: true),
      const SizedBox(height: 18),
      const Text('Allumez votre panneau, puis choisissez-le ci-dessous.',
          style: TextStyle(color: muted, fontSize: 12, height: 1.4)),
      const SizedBox(height: 16),
      _panelOption(
        title: 'Panneau couleur',
        detail: '8 × 8 pixels · WS2812B',
        badge: 'RGB',
        isColor: true,
        scanning: scanning || connecting,
      ),
      const SizedBox(height: 10),
      _panelOption(
        title: 'Panneau rouge',
        detail: '64 × 8 pixels · MAX7219',
        badge: '1 couleur',
        isColor: false,
        scanning: scanning || connecting,
      ),
      if (scanning || connecting)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Row(children: [
            const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text(connecting ? 'Connexion en cours…' : 'Recherche des panneaux…',
                style: const TextStyle(color: muted, fontSize: 12)),
          ]),
        ),
      for (final d in c.devices.values)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _card(child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bluetooth, color: lime),
            title: Text(d.name),
            subtitle: Text('${d.rssi} dBm · Toucher pour connecter',
                style: const TextStyle(color: muted, fontSize: 11)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _connectDevice(d),
          )),
        ),
      if (c.state == LinkState.empty)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text('Aucun panneau détecté. Vérifiez son alimentation et réessayez.',
              style: TextStyle(color: muted, fontSize: 12)),
        ),
      const SizedBox(height: 14),
      Center(
        child: TextButton(
          onPressed: scanning || connecting
              ? null
              : () => c.search(demonstration: true),
          child: const Text('Essayer la démonstration'),
        ),
      ),
    ];
  }

  Widget _panelOption({required String title, required String detail,
      required String badge, required bool isColor, required bool scanning}) {
    final accent = isColor ? lime : red;
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.developer_board_outlined, color: accent, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(detail, style: const TextStyle(color: muted, fontSize: 11)),
            ])),
          Text(badge, style: TextStyle(color: accent, fontSize: 10,
              fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, height: 48,
          child: isColor
              ? FilledButton(onPressed: scanning ? null : () => _selectPanel(true),
                  child: const Text('Connecter'))
              : OutlinedButton(onPressed: scanning ? null : () => _selectPanel(false),
                  child: const Text('Connecter')),
        ),
      ]),
    );
  }

  Future<void> _selectPanel(bool color) async {
    setState(() => colorPanel = color);
    await c.search(demonstration: false);
  }

  Future<void> _connectDevice(PanelDevice device) async {
    if (!c.demo) {
      final name = device.name.toLowerCase();
      setState(() => colorPanel = name.contains('rgb') || name.contains('couleur'));
    }
    await c.connect(device);
  }

  List<Widget> _content() {
    if (c.page == 2) return _settings();
    if (c.page == 1) {
      return [
        _title('Petits signes', 'Des dessins faits pour vos LED.'),
        _preview(),
        const SizedBox(height: 8),
        const Text('Choisir un pictogramme',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, constraints) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < pixelIcons.length; i++)
              SizedBox(
                width: (constraints.maxWidth - 16) / 3,
                child: Semantics(
                  selected: c.icon == i,
                  button: true,
                  label: pixelIcons[i].label,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => c.selectIcon(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                      decoration: BoxDecoration(
                        color: c.icon == i ? const Color(0xff25352a) : surface,
                        border: Border.all(color: c.icon == i ? lime : stroke),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(children: [
                        SizedBox(width: 38, height: 38,
                          child: CustomPaint(painter: _IconPainter(pixelIcons[i], previewColor))),
                        const SizedBox(height: 6),
                        Text(pixelIcons[i].label,
                            style: const TextStyle(fontSize: 10, color: muted)),
                      ]),
                    ),
                  ),
                ),
              ),
          ],
        )),
        const SizedBox(height: 10),
        const Text('8 × 8 pixels · Des signes dessinés pour le panneau.',
            style: TextStyle(fontSize: 11, color: muted)),
      ];
    }
    return [
      _title('Votre message', colorPanel
          ? 'Un mot, une intention. À vous de jouer.'
          : 'Le même geste, en rouge.'),
      _preview(),
      const SizedBox(height: 10),
      Row(children: [
        const Text('Message', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        const Spacer(),
        Text('${c.message.length}/60', style: const TextStyle(color: muted, fontSize: 10)),
      ]),
      const SizedBox(height: 7),
      TextField(
        controller: input,
        maxLength: 60,
        onChanged: c.updateMessage,
        textCapitalization: TextCapitalization.characters,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          counterText: '',
          hintText: 'Votre message',
          errorText: c.message.isNotEmpty ? validateMessage(c.message) : null,
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('${c.message.length} caractères · ' +
            (messageScrolls ? 'Le message défile.' : 'Affichage fixe.'),
            style: const TextStyle(color: muted, fontSize: 10)),
      ),
      const SizedBox(height: 12),
      if (allowsColor) ...[
        const Text('Couleur', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(spacing: 9, children: [
          for (var i = 0; i < panelColors.length; i++)
            Semantics(
              label: 'Couleur ${i + 1}',
              selected: selectedColor == i,
              button: true,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => selectedColor = i),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: panelColors[i],
                    border: Border.all(color: selectedColor == i ? Colors.white : stroke,
                        width: selectedColor == i ? 2 : 1),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, height: 40,
          child: OutlinedButton(
            onPressed: () {
              input.text = 'BONJOUR';
              c.updateMessage('BONJOUR');
            },
            child: const Text('Essayer « BONJOUR » →', style: TextStyle(fontSize: 11)),
          ),
        ),
      ] else ...[
        _card(child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Rouge, naturellement', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
          SizedBox(height: 3),
          Text('La couleur est définie par les LED du panneau.',
              style: TextStyle(color: muted, fontSize: 10)),
          SizedBox(height: 8),
          Text('Jusqu’à 10 caractères fixes. Au-delà, le message défile automatiquement.',
              style: TextStyle(color: muted, fontSize: 9)),
        ])),
      ],
    ];
  }

  Widget _preview({bool connection = false}) => _card(
    color: const Color(0xff1b2a21),
    child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('APERÇU DU PANNEAU',
            style: TextStyle(fontSize: 9, color: muted, letterSpacing: .4)),
        Text(colorPanel ? '8 × 8' : '64 × 8', style: const TextStyle(fontSize: 9, color: muted)),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(color: const Color(0xff080e0a),
            borderRadius: BorderRadius.circular(10)),
        child: Center(
          child: SizedBox(
            width: colorPanel ? 112 : double.infinity,
            child: PixelPreview(
              text: c.message,
              icon: c.connected && c.page == 1 ? pixelIcons[c.icon] : null,
              settings: c.settings,
              foreground: previewColor,
              columns: colorPanel ? 8 : 64,
              paused: true,
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Row(children: [
        Text(connection
            ? 'À portée de Bluetooth'
            : messageScrolls
                ? 'Défilement en cours' : 'Affichage fixe',
            style: const TextStyle(fontSize: 9, color: muted)),
        const Spacer(),
        Text(allowsColor ? 'Couleur' : 'Rouge',
            style: TextStyle(fontSize: 9, color: previewColor,
                fontWeight: FontWeight.w700)),
      ]),
    ]),
  );

  List<Widget> _settings() => [
    _title('Votre panneau', 'Les bons réglages, tout simplement.'),
    _card(child: Row(children: [
      Icon(Icons.developer_board_outlined, color: colorPanel ? lime : red, size: 24),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(colorPanel ? 'Panneau couleur' : 'Panneau rouge',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        Text(colorPanel ? '8 × 8 pixels · connecté en Bluetooth'
            : '64 × 8 pixels · connecté en Bluetooth',
            style: const TextStyle(color: muted, fontSize: 10)),
      ])),
      const Text('Connecté', style: TextStyle(color: lime, fontSize: 10,
          fontWeight: FontWeight.w700)),
    ])),
    const SizedBox(height: 18),
    Row(children: [
      const Text('Luminosité', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
      const Spacer(),
      Text('${(c.settings.brightness * 100 / 15).round()} %',
          style: const TextStyle(color: lime, fontWeight: FontWeight.w700, fontSize: 11)),
    ]),
    Slider(
      value: c.settings.brightness.toDouble(),
      min: 0, max: 15, divisions: 15,
      onChanged: c.busy ? null : (v) => c.updateSettings(
          c.settings.copyWith(brightness: v.round())),
    ),
    const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text('Faible', style: TextStyle(color: muted, fontSize: 9)),
      Text('Forte', style: TextStyle(color: muted, fontSize: 9)),
    ]),
    const SizedBox(height: 14),
    const Text('Défilement du texte',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
    const SizedBox(height: 8),
    Row(children: [
      Expanded(child: _modeButton('Automatique', ScrollMode.auto)),
      const SizedBox(width: 8),
      Expanded(child: _modeButton('Fixe', ScrollMode.fixed)),
    ]),
    const SizedBox(height: 4),
    const Text('Le texte défile seulement s’il dépasse le panneau.',
        style: TextStyle(color: muted, fontSize: 9)),
    const SizedBox(height: 14),
    Row(children: [
      const Text('Vitesse', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
      const Spacer(),
      Text(_speedName(c.settings.speedMs),
          style: const TextStyle(color: lime, fontSize: 10, fontWeight: FontWeight.w700)),
    ]),
    Slider(
      value: (150 - c.settings.speedMs).clamp(30, 120).toDouble(),
      min: 30, max: 120,
      onChanged: c.busy ? null : (v) => c.updateSettings(
          c.settings.copyWith(speedMs: 150 - v.round())),
    ),
    const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text('Lente', style: TextStyle(color: muted, fontSize: 9)),
      Text('Rapide', style: TextStyle(color: muted, fontSize: 9)),
    ]),
  ];

  Widget _modeButton(String label, ScrollMode mode) {
    final selected = mode == ScrollMode.auto
        ? c.settings.mode != ScrollMode.fixed
        : c.settings.mode == mode;
    return SizedBox(height: 48, child: selected
        ? FilledButton(onPressed: c.busy ? null : () => c.updateSettings(
            c.settings.copyWith(mode: mode)), child: Text(label, style: const TextStyle(fontSize: 10)))
        : OutlinedButton(onPressed: c.busy ? null : () => c.updateSettings(
            c.settings.copyWith(mode: mode)), child: Text(label, style: const TextStyle(fontSize: 10))));
  }

  String _speedName(int speed) => speed >= 95 ? 'Lente' : speed <= 45 ? 'Rapide' : 'Normale';

  String _iconActionLabel() => switch (pixelIcons[c.icon].label) {
    'Sourire' => 'Afficher le sourire',
    'Cœur' => 'Afficher le cœur',
    'Flèche' => 'Afficher la flèche',
    'Soleil' => 'Afficher le soleil',
    'Clin d’œil' => 'Afficher le clin d’œil',
    _ => 'Afficher la pause',
  };

  Widget _title(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: const TextStyle(color: muted, fontSize: 11, height: 1.4),
        ),
      ],
    ),
  );
  Widget _card({required Widget child, Color color = surface}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: stroke),
    ),
    child: child,
  );
}

class _IconPainter extends CustomPainter {
  final PixelIcon icon;
  final Color color;
  _IconPainter(this.icon, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = size.width / 8;
    final paint = Paint();
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        paint.color = (icon.rows[y] & (1 << (7 - x))) != 0 ? color : stroke;
        canvas.drawRect(
          Rect.fromLTWH(x * p + 1, y * p + 1, p - 2, p - 2),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IconPainter old) => old.icon != icon || old.color != color;
}
