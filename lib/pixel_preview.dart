import 'package:flutter/material.dart';

import 'protocol.dart';

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
  const PixelPreview({
    super.key,
    this.text = 'MERCI',
    this.icon,
    this.settings = const PanelSettings(),
    this.paused = false,
    this.foreground = const Color(0xffd7ff7f),
    this.columns = 64,
  });
  @override
  State<PixelPreview> createState() => _PixelPreviewState();
}

class _PixelPreviewState extends State<PixelPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 120),
  )..repeat();
  @override
  void didUpdateWidget(covariant PixelPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paused && !oldWidget.paused) _clock.stop();
    if (!widget.paused && oldWidget.paused) _clock.repeat();
  }

  @override
  void dispose() {
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
          final scrolling =
              widget.icon == null &&
              (widget.settings.mode == ScrollMode.always ||
                  (widget.settings.mode == ScrollMode.auto &&
                      widget.text.length * 6 > widget.columns));
          final step = (_clock.value * 120000 / widget.settings.speedMs)
              .floor();
          return CustomPaint(
            painter: MatrixPainter(
              widget.text,
              widget.icon,
              scrolling ? step : -1,
              widget.settings,
              widget.foreground,
              widget.columns,
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
  MatrixPainter(this.text, this.icon, this.step, this.settings, this.foreground, this.columns);
  @override
  void paint(Canvas canvas, Size size) {
    final cells = List.generate(8, (_) => List.filled(columns, false));
    if (icon != null) {
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          final left = (columns - 8) ~/ 2;
          if (left + x < columns) {
            cells[y][left + x] = (icon!.rows[y] & (1 << (7 - x))) != 0;
          }
        }
      }
    } else {
      final value = text.toUpperCase();
      final width = value.length * 6;
      final offset = step < 0
          ? ((columns - width) / 2).floor()
          : (settings.right
                ? (step % (width + columns)) - width
                : columns - (step % (width + columns)));
      for (var i = 0; i < value.length; i++) {
        final rows = _font[value[i]] ?? _font['?']!;
        for (var y = 0; y < 7; y++) {
          for (var x = 0; x < 5; x++) {
            final col = offset + i * 6 + x;
            if (col >= 0 && col < columns)
              cells[y][col] = (rows[y] & (1 << (4 - x))) != 0;
          }
        }
      }
    }
    final pitch = size.width / columns;
    final paint = Paint();
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < columns; x++) {
        paint.color = cells[y][x] && settings.power
            ? Color.lerp(
                const Color(0xff829f3d),
                foreground,
                settings.brightness / 15,
              )!
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
      old.text != text || old.icon != icon || old.step != step ||
      old.settings != settings || old.foreground != foreground || old.columns != columns;
}
