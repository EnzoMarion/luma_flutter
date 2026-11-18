import 'dart:async';

import 'package:flutter/material.dart';

import 'protocol.dart';
import 'raster_font.dart';

// Police de prévisualisation 5 × 7. Le firmware MD_Parola possède sa propre police.
const _font = <String, List<int>>{
  'A': [14, 17, 17, 31, 17, 17, 17],
  'B': [30, 17, 17, 30, 17, 17, 30],
  'C': [14, 17, 16, 16, 16, 17, 14],
  'D': [30, 17, 17, 17, 17, 17, 30],
  'E': [31, 16, 16, 30, 16, 16, 31],
  'F': [31, 16, 16, 30, 16, 16, 16],
  'G': [14, 17, 16, 23, 17, 17, 15],
  'H': [17, 17, 17, 31, 17, 17, 17],
  'I': [14, 4, 4, 4, 4, 4, 14],
  'J': [7, 2, 2, 2, 18, 18, 12],
  'K': [17, 18, 20, 24, 20, 18, 17],
  'L': [16, 16, 16, 16, 16, 16, 31],
  'M': [17, 27, 21, 21, 17, 17, 17],
  'N': [17, 25, 21, 19, 17, 17, 17],
  'O': [14, 17, 17, 17, 17, 17, 14],
  'P': [30, 17, 17, 30, 16, 16, 16],
  'Q': [14, 17, 17, 17, 21, 18, 13],
  'R': [30, 17, 17, 30, 20, 18, 17],
  'S': [15, 16, 16, 14, 1, 1, 30],
  'T': [31, 4, 4, 4, 4, 4, 4],
  'U': [17, 17, 17, 17, 17, 17, 14],
  'V': [17, 17, 17, 17, 17, 10, 4],
  'W': [17, 17, 17, 21, 21, 21, 10],
  'X': [17, 17, 10, 4, 10, 17, 17],
  'Y': [17, 17, 10, 4, 4, 4, 4],
  'Z': [31, 1, 2, 4, 8, 16, 31],
  '0': [14, 17, 19, 21, 25, 17, 14],
  '1': [4, 12, 4, 4, 4, 4, 14],
  '2': [14, 17, 1, 2, 4, 8, 31],
  '3': [30, 1, 1, 14, 1, 1, 30],
  '4': [2, 6, 10, 18, 31, 2, 2],
  '5': [31, 16, 16, 30, 1, 1, 30],
  '6': [14, 16, 16, 30, 17, 17, 14],
  '7': [31, 1, 2, 4, 8, 8, 8],
  '8': [14, 17, 17, 14, 17, 17, 14],
  '9': [14, 17, 17, 15, 1, 1, 14],
  ' ': [0, 0, 0, 0, 0, 0, 0],
  '!': [4, 4, 4, 4, 4, 0, 4],
  '?': [14, 17, 1, 2, 4, 0, 4],
  '.': [0, 0, 0, 0, 0, 0, 4],
  ',': [0, 0, 0, 0, 0, 4, 8],
  ':': [0, 4, 0, 0, 4, 0, 0],
  '-': [0, 0, 0, 31, 0, 0, 0],
  '+': [0, 4, 4, 31, 4, 4, 0],
  '/': [1, 2, 2, 4, 8, 8, 16],
  "'": [4, 4, 8, 0, 0, 0, 0],
};

class PixelPreview extends StatefulWidget {
  final String text;
  final PixelIcon? icon;
  final PanelSettings settings;
  final bool paused;
  final Color foreground;
  final int columns;
  final String? drawing;
  const PixelPreview({
    super.key,
    this.text = 'MERCI',
    this.icon,
    this.settings = const PanelSettings(),
    this.paused = false,
    this.foreground = const Color(0xffd7ff7f),
    this.columns = 64,
    this.drawing,
  });
  @override
  State<PixelPreview> createState() => _PixelPreviewState();
}

class _PixelPreviewState extends State<PixelPreview>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _reducedMotion = false;
  bool _appActive = true;
  List<int>? _renderedColumns;
  List<List<int>>? _renderedPages;
  int _renderGeneration = 0;
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 120),
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appActive = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    unawaited(_loadRaster());
  }

  Future<void> _loadRaster() async {
    final generation = ++_renderGeneration;
    _renderedColumns = null;
    _renderedPages = null;
    if (!requiresRasterFont(widget.text, widget.settings.alphabet) ||
        widget.icon != null ||
        widget.drawing != null ||
        widget.text.isEmpty) return;
    try {
      final full =
          await rasterTextColumns(widget.text, widget.settings.alphabet);
      final pages = await Future.wait(appearancePages(
              widget.text, widget.settings.alphabet)
          .map((page) => rasterTextColumns(page, widget.settings.alphabet)));
      if (!mounted || generation != _renderGeneration) return;
      setState(() {
        _renderedColumns = full;
        _renderedPages = pages;
      });
      _syncAnimation();
    } catch (_) {
      // Validation displays unsupported characters; the preview stays blank.
    }
  }

  void _syncAnimation() {
    final width = _renderedColumns?.length ??
        textColumns(widget.text, widget.settings.alphabet).length;
    final shouldMove = widget.settings.mode == ScrollMode.always ||
        (widget.settings.mode == ScrollMode.auto && width > widget.columns) ||
        widget.settings.mode == ScrollMode.appearance;
    final animate = !widget.paused &&
        !_reducedMotion &&
        _appActive &&
        widget.icon == null &&
        widget.drawing == null &&
        shouldMove;
    if (animate && !_clock.isAnimating) _clock.repeat();
    if (!animate && _clock.isAnimating) _clock.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _syncAnimation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant PixelPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.settings.alphabet != widget.settings.alphabet ||
        oldWidget.icon != widget.icon ||
        oldWidget.drawing != widget.drawing) {
      unawaited(_loadRaster());
    }
    _syncAnimation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: widget.icon == null
            ? 'Aperçu du message ${widget.text}'
            : 'Pictogramme ${widget.icon!.label}',
        child: AspectRatio(
          aspectRatio: widget.columns / 8,
          child: AnimatedBuilder(
            animation: _clock,
            builder: (context, child) {
              final scrolling = widget.icon == null &&
                  widget.drawing == null &&
                  (widget.settings.mode == ScrollMode.always ||
                      (widget.settings.mode == ScrollMode.auto &&
                          (_renderedColumns?.length ??
                                  textColumns(
                                          widget.text, widget.settings.alphabet)
                                      .length) >
                              widget.columns) ||
                      widget.settings.mode == ScrollMode.appearance);
              final step =
                  (_clock.value * 120000 / widget.settings.speedMs).floor();
              return CustomPaint(
                painter: MatrixPainter(
                  widget.text,
                  widget.icon,
                  scrolling && !_reducedMotion ? step : -1,
                  widget.settings,
                  widget.foreground,
                  widget.columns,
                  widget.drawing,
                  _renderedColumns,
                  _renderedPages,
                ),
              );
            },
          ),
        ),
      );
}

class MatrixPainter extends CustomPainter {
  final String text;
  final PixelIcon? icon;
  final int step;
  final PanelSettings settings;
  final Color foreground;
  final int columns;
  final String? drawing;
  final List<int>? renderedColumns;
  final List<List<int>>? renderedPages;
  MatrixPainter(this.text, this.icon, this.step, this.settings, this.foreground,
      this.columns, this.drawing, this.renderedColumns, this.renderedPages);
  @override
  void paint(Canvas canvas, Size size) {
    final cells = List.generate(8, (_) => List.filled(columns, false));
    if (drawing != null && drawing!.length == 256 && columns == 32) {
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 32; x++) {
          cells[y][x] = drawing![y * 32 + x] == '1';
        }
      }
    } else if (icon != null) {
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          final left = (columns - 8) ~/ 2;
          if (left + x < columns) {
            cells[y][left + x] = (icon!.rows[y] & (1 << (7 - x))) != 0;
          }
        }
      }
    } else {
      var shownText = text;
      var pageIndex = 0;
      if (settings.mode == ScrollMode.appearance) {
        final pages = appearancePages(text, settings.alphabet);
        if (pages.isNotEmpty) {
          final ticksPerPage = (3000 / settings.speedMs).round().clamp(1, 1000);
          pageIndex = (step < 0 ? 0 : step ~/ ticksPerPage) % pages.length;
          shownText = pages[pageIndex];
        }
      }
      final values = requiresRasterFont(text, settings.alphabet)
          ? (settings.mode == ScrollMode.appearance
              ? (renderedPages != null && pageIndex < renderedPages!.length
                  ? renderedPages![pageIndex]
                  : <int>[])
              : renderedColumns ?? <int>[])
          : textColumns(shownText, settings.alphabet);
      final width = values.length;
      final moves = settings.mode == ScrollMode.always ||
          (settings.mode == ScrollMode.auto && width > columns);
      final offset = step < 0 || !moves
          ? ((columns - width.clamp(0, columns)) / 2).floor()
          : (settings.right
              ? (step % (width + columns)) - width
              : columns - (step % (width + columns)));
      for (var i = 0; i < values.length; i++) {
        final col = offset + i;
        if (col >= 0 && col < columns) {
          for (var y = 0; y < 8; y++) {
            cells[y][col] = (values[i] & (0x80 >> y)) != 0;
          }
        }
      }
    }
    final pitch = size.width / columns;
    var reveal = 1.0;
    if (settings.mode == ScrollMode.appearance && step >= 0) {
      final duration = settings.speedMs <= 20
          ? 2400
          : settings.speedMs >= 100
              ? 4000
              : 3000;
      final elapsed = step * settings.speedMs % duration;
      reveal = elapsed < 800
          ? elapsed / 800
          : elapsed > duration - 800
              ? (duration - elapsed) / 800
              : 1;
      reveal = reveal.clamp(0.0, 1.0);
    }
    final litColor = Color.lerp(
      Colors.black,
      foreground,
      0.35 + 0.65 * settings.brightness / 15,
    )!;
    final paint = Paint();
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < columns; x++) {
        paint.color = cells[y][x] && settings.power && settings.brightness > 0
            ? litColor.withValues(alpha: reveal)
            : const Color(0xff233127);
        canvas.drawCircle(
          Offset((x + .5) * pitch, (y + .5) * pitch),
          pitch * .30,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant MatrixPainter old) =>
      old.text != text ||
      old.icon != icon ||
      old.step != step ||
      old.settings != settings ||
      old.foreground != foreground ||
      old.columns != columns ||
      old.drawing != drawing ||
      old.renderedColumns != renderedColumns ||
      old.renderedPages != renderedPages;
}
