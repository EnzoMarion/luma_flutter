import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'protocol.dart';

/// Renders shaped Unicode text into the same eight pixel rows sent to MAX7219.
Future<List<int>> rasterTextColumns(String text, PanelAlphabet alphabet) async {
  if (!requiresRasterFont(text, alphabet)) return textColumns(text, alphabet);
  if (alphabet.rightToLeft) return _rasterRun(text, alphabet);

  final columns = <int>[];
  var run = StringBuffer();
  var bitmapRun = true;
  Future<void> appendRun() async {
    if (run.length == 0) return;
    if (columns.isNotEmpty) columns.add(0);
    final part = run.toString();
    columns.addAll(bitmapRun
        ? textColumns(part, alphabet)
        : await _rasterRun(part, alphabet));
    run = StringBuffer();
  }

  for (final rune in normalizeMessage(text).runes) {
    final character = String.fromCharCode(rune);
    final bitmap = usesBitmapGlyph(character);
    if (run.length > 0 && bitmap != bitmapRun) await appendRun();
    bitmapRun = bitmap;
    run.write(character);
  }
  await appendRun();
  return columns;
}

Future<List<int>> _rasterRun(String text, PanelAlphabet alphabet) async {
  final painter = TextPainter(
    text: TextSpan(
      text: normalizeMessage(text),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 8,
        height: 1,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.none,
      ),
    ),
    textDirection: alphabet.rightToLeft ? TextDirection.rtl : TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final width = painter.width.ceil().clamp(1, 2048);
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), Offset.zero);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, 8);
  picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  painter.dispose();
  if (bytes == null) throw StateError('Impossible de dessiner ce message.');
  final columns = <int>[];
  for (var x = 0; x < width; x++) {
    var bits = 0;
    for (var y = 0; y < 8; y++) {
      if (bytes.getUint8((y * width + x) * 4 + 3) >= 80) {
        bits |= 0x80 >> y;
      }
    }
    columns.add(bits);
  }
  return columns;
}
