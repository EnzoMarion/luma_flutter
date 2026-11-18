import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pixel_preview.dart';

const drawingColors = [Color(0xffd7ff7f), Color(0xffeef3eb), Color(0xfff7bc77), Color(0xffff7770), Color(0xff62b9e8), Color(0xffad91f5)];
String drawingBits(String entry) => entry.length == 258 && entry[1] == ':' ? entry.substring(2) : entry;
int drawingColor(String entry) => entry.length == 258 && entry[1] == ':' ? (int.tryParse(entry[0]) ?? 0).clamp(0, 5) : 0;
bool validDrawingFavorite(String entry) {
  if (entry.length == 258 && (entry[1] != ':' || int.tryParse(entry[0]) == null || int.parse(entry[0]) > 5)) return false;
  final bits = drawingBits(entry);
  return bits.length == 256 && !bits.contains(RegExp(r'[^01]'));
}

class DrawingEditor extends StatefulWidget {
  final String? initial;
  final int initialColor;
  const DrawingEditor({super.key, this.initial, this.initialColor = 0});
  @override
  State<DrawingEditor> createState() => _DrawingEditorState();
}

class _DrawingEditorState extends State<DrawingEditor> {
  late List<bool> pixels;
  List<String> favorites = [];
  int section = 0;
  bool? gestureValue;
  Offset? lastPosition;
  late int color;
  @override
  void initState() {
    super.initState();
    color = widget.initialColor.clamp(0, 5);
    final value = widget.initial;
    pixels = value != null && value.length == 256
        ? value.split('').map((c) => c == '1').toList()
        : List.filled(256, false);
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final saved = prefs.getString('drawing_draft_v2');
    setState(() {
      if (widget.initial == null && saved != null && saved.length == 256 && !saved.contains(RegExp(r'[^01]'))) {
        pixels = saved.split('').map((c) => c == '1').toList();
      }
      favorites = (prefs.getStringList('drawing_favorites_v2') ?? [])
        .where(validDrawingFavorite)
        .take(20).toList();
    });
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('drawing_draft_v2', encoded);
  }

  String get encoded => pixels.map((v) => v ? '1' : '0').join();
  String get favoriteKey => '$color:$encoded';

  Future<void> _favorite() async {
    if (!pixels.contains(true)) return;
    final value = favoriteKey;
    setState(() {
      if (favorites.any((f) => drawingBits(f) == encoded && drawingColor(f) == color)) { favorites.removeWhere((f) => drawingBits(f) == encoded && drawingColor(f) == color); }
      else if (favorites.length < 20) { favorites.add(value); }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('drawing_favorites_v2', favorites);
  }

  Future<void> _clearDrawing() async {
    final clear = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Effacer le dessin ?'),
      content: const Text('Tous les pixels du dessin seront effacés.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Effacer')),
      ],
    ));
    if (clear == true && mounted) {
      setState(() => pixels = List.filled(256, false));
      await _saveDraft();
    }
  }

  void _paint(Offset position, double width, {bool start = false}) {
    final x = (position.dx / width * 8).floor();
    final y = (position.dy / width * 8).floor();
    if (x < 0 || x >= 8 || y < 0 || y >= 8) { lastPosition = null; return; }
    final index = y * 32 + section * 8 + x;
    if (start) { gestureValue = !pixels[index]; lastPosition = position; }
    if (gestureValue == null) return;
    final previous = lastPosition ?? position;
    final distance = (position - previous).distance;
    final steps = (distance / (width / 16)).ceil().clamp(1, 100);
    setState(() {
      for (var i = 0; i <= steps; i++) {
        final point = Offset.lerp(previous, position, i / steps)!;
        final px = (point.dx / width * 8).floor();
        final py = (point.dy / width * 8).floor();
        if (px >= 0 && px < 8 && py >= 0 && py < 8) pixels[py * 32 + section * 8 + px] = gestureValue!;
      }
    });
    lastPosition = position;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ton dessin')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(24), children: [
      const Text('Dessine sur les quatre parties du panneau.'),
      const SizedBox(height: 12),
      PixelPreview(columns: 32, drawing: encoded, paused: true, foreground: drawingColors[color]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [for (var i = 0; i < 4; i++) ChoiceChip(
        label: Text('${i + 1}'), selected: section == i,
        onSelected: (_) => setState(() => section = i),
      )]),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _paint(d.localPosition, width, start: true),
          onPanUpdate: (d) => _paint(d.localPosition, width),
          onPanEnd: (_) { gestureValue = null; lastPosition = null; _saveDraft(); },
          onPanCancel: () { gestureValue = null; lastPosition = null; _saveDraft(); },
          onTapUp: (d) { _paint(d.localPosition, width, start: true); gestureValue = null; lastPosition = null; _saveDraft(); },
          child: AspectRatio(aspectRatio: 1, child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
            itemCount: 64,
            itemBuilder: (_, index) => Semantics(
              label: 'Ligne ${index ~/ 8 + 1}, colonne ${section * 8 + index % 8 + 1}',
              value: pixels[(index ~/ 8) * 32 + section * 8 + index % 8] ? 'Allumé' : 'Éteint',
              button: true,
              onTap: () {
                final pixel = (index ~/ 8) * 32 + section * 8 + index % 8;
                setState(() => pixels[pixel] = !pixels[pixel]);
                _saveDraft();
              },
              child: Container(margin: const EdgeInsets.all(2), decoration: BoxDecoration(
                color: pixels[(index ~/ 8) * 32 + section * 8 + index % 8]
                    ? drawingColors[color] : const Color(0xff35453b),
                borderRadius: BorderRadius.circular(5),
              )),
            ),
          )),
        );
      }),
      Wrap(spacing: 8, children: [
        TextButton(onPressed: _clearDrawing, child: const Text('Effacer')),
        TextButton(onPressed: _favorite, child: Text(favorites.any((f) => drawingBits(f) == encoded && drawingColor(f) == color) ? 'Retirer des favoris' : 'Ajouter aux favoris')),
      ]),
      Wrap(spacing: 8, children: [for (var i = 0; i < drawingColors.length; i++)
        IconButton(onPressed: () => setState(() => color = i),
          tooltip: 'Couleur ${i + 1}',
          icon: Icon(color == i ? Icons.check_circle : Icons.circle, color: drawingColors[i]))]),
      if (favorites.length >= 20 && !favorites.any((f) => drawingBits(f) == encoded && drawingColor(f) == color))
        const Text('20 dessins favoris maximum. Retire-en un pour en ajouter un autre.'),
      if (favorites.isNotEmpty) ...[
        const Text('Dessins favoris'),
        Wrap(spacing: 8, children: [for (var i = 0; i < favorites.length; i++) ActionChip(
          label: Text('Dessin ${i + 1}'),
          onPressed: () => setState(() { pixels = drawingBits(favorites[i]).split('').map((c) => c == '1').toList(); color = drawingColor(favorites[i]); }),
        )]),
      ],
      const SizedBox(height: 12),
      FilledButton(onPressed: pixels.contains(true) ? () => Navigator.pop(context, favoriteKey) : null,
          child: const Text('Valider le dessin')),
    ])),
  );
}
