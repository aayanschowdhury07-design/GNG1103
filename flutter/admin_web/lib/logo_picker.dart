import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// The clinic's logo is kept on the clinic record as a small PNG (a data URL), so it needs
/// no file storage: pictures are shrunk to fit 256 px before saving, which keeps them small.
const logoMaxSide = 256;

class LogoProblem implements Exception {
  const LogoProblem(this.tooBig);
  final bool tooBig;
}

/// Asks for an image file and returns it as a PNG data URL no bigger than [logoMaxSide].
/// Null when the file can't be read as a picture. Never completes if the person cancels.
Future<String?> pickLogo() {
  final done = Completer<String?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/png,image/jpeg,image/webp,image/svg+xml';
  input.onchange = ((web.Event _) {
    final f = input.files?.item(0);
    if (f == null) return;
    if (f.size > 5 * 1024 * 1024) {
      done.completeError(const LogoProblem(true));
      return;
    }
    final reader = web.FileReader();
    reader.onload = ((web.Event _) {
      final src = (reader.result as JSString?)?.toDart;
      if (src == null) return done.complete(null);
      final img = web.HTMLImageElement();
      img.onload = ((web.Event _) {
        // an SVG without a size reports 0; draw it at the full size
        final w = img.naturalWidth == 0 ? logoMaxSide : img.naturalWidth, h = img.naturalHeight == 0 ? logoMaxSide : img.naturalHeight;
        final scale = min(1.0, logoMaxSide / max(w, h));
        final cw = max(1, (w * scale).round()), ch = max(1, (h * scale).round());
        final canvas = web.HTMLCanvasElement()
          ..width = cw
          ..height = ch;
        (canvas.getContext('2d') as web.CanvasRenderingContext2D).drawImage(img, 0, 0, cw, ch);
        done.complete(canvas.toDataURL('image/png'));
      }).toJS;
      img.onerror = ((web.Event _) => done.complete(null)).toJS;
      img.src = src;
    }).toJS;
    reader.readAsDataURL(f);
  }).toJS;
  input.click();
  return done.future;
}

/// Shows a logo saved by [pickLogo], or [fallback] when there's none.
class ClinicLogo extends StatelessWidget {
  const ClinicLogo(this.dataUrl, {super.key, required this.size, required this.fallback});
  final String? dataUrl;
  final double size;
  final Widget fallback;
  @override
  Widget build(BuildContext context) {
    final d = dataUrl ?? '';
    final comma = d.indexOf(',');
    if (!d.startsWith('data:image/') || comma < 0) return fallback;
    try {
      return Image.memory(base64Decode(d.substring(comma + 1)), width: size, height: size, fit: BoxFit.contain, gaplessPlayback: true, semanticLabel: 'Clinic logo');
    } catch (_) {
      return fallback;
    }
  }
}
