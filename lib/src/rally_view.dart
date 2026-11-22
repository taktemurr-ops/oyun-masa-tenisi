import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'rally_engine.dart';

/// Table tennis / tennis seen from above; the ball's height is shown by its
/// shadow offset and size.
Paint _p(int c) => Paint()..color = Color(c);

Paint _stroke(int c, double w) => Paint()
  ..color = Color(c)
  ..style = PaintingStyle.stroke
  ..strokeWidth = w;

void _racket(Canvas c, double x, double y, int color, bool tennis, bool top) {
  final dir = top ? 1.0 : -1.0;
  // player body below / above the racket
  c.drawCircle(Offset(x - 40, y - dir * 50), 34, _p(0xFF2B2D42));
  c.drawCircle(Offset(x - 40, y - dir * 50), 22, _p(color));
  if (tennis) {
    c.drawLine(Offset(x - 10, y - dir * 40), Offset(x, y), _stroke(0xFF3D3D3D, 10));
    c.drawOval(Rect.fromCenter(center: Offset(x + 14, y + dir * 30), width: 70, height: 90), _stroke(color, 9));
    for (var i = -2; i <= 2; i++) {
      c.drawLine(Offset(x + 14 + i * 12, y + dir * 30 - 38), Offset(x + 14 + i * 12, y + dir * 30 + 38), _stroke(0x88FFFFFF, 2));
    }
  } else {
    c.drawLine(Offset(x - 6, y - dir * 34), Offset(x, y), _stroke(0xFF8D6E63, 12));
    c.drawCircle(Offset(x + 6, y + dir * 24), 36, _p(color));
    c.drawCircle(Offset(x + 6, y + dir * 24), 36, _stroke(0xFF000000, 3));
  }
}

void paintRally(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as RallySim;
  final g = s.g;
  final themes = [
    [0xFF1D3557, 0xFF0D1B2A],
    [0xFF2B2D42, 0xFF14213D],
    [0xFF283618, 0xFF1B1B1B],
    [0xFF3C096C, 0xFF10002B],
  ];
  final th = themes[s.level.theme % 4];
  c.drawRect(
    const Rect.fromLTWH(0, 0, kWorldW, kWorldH),
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(th[0]), Color(th[1])],
      ).createShader(const Rect.fromLTWH(0, 0, kWorldW, kWorldH)),
  );
  final court = Rect.fromLTRB(g.l, g.t, g.r, g.b);
  if (s.tennis) {
    c.drawRect(court.inflate(110), _p(0xFFBC6C25));
    c.drawRect(court, _p(0xFF2A9D8F));
    final line = _stroke(0xFFFFFFFF, 6);
    c.drawRect(court, line);
    c.drawLine(Offset(g.cx, g.net - 360), Offset(g.cx, g.net + 360), line);
    c.drawLine(Offset(g.l, g.net - 360), Offset(g.r, g.net - 360), line);
    c.drawLine(Offset(g.l, g.net + 360), Offset(g.r, g.net + 360), line);
  } else {
    c.drawRect(court.translate(10, 18), _p(0x66000000));
    c.drawRect(court, _p(0xFF1D4ED8));
    final line = _stroke(0xFFFFFFFF, 6);
    c.drawRect(court, line);
    c.drawLine(Offset(g.cx, g.t), Offset(g.cx, g.b), _stroke(0xAAFFFFFF, 3));
  }
  // net
  c.drawRect(Rect.fromLTRB(g.l - 30, g.net - 6, g.r + 30, g.net + 6), _p(0xFFF8F9FA));
  for (var x = g.l - 30; x < g.r + 30; x += 16) {
    c.drawLine(Offset(x, g.net - 6), Offset(x, g.net + 6), _stroke(0x55000000, 2));
  }
  // rival and player
  _racket(c, s.cx, s.cy, 0xFFE63946, s.tennis, true);
  // ball shadow and ball (height lifts the ball up the screen)
  final h = s.bz;
  c.drawOval(Rect.fromCenter(center: Offset(s.bx + h * 0.15, s.by + 6), width: 26, height: 14), _p(0x66000000));
  final r = (s.tennis ? 16.0 : 13.0) + h * 0.05;
  c.drawCircle(Offset(s.bx, s.by - h * 0.9), r, _p(s.tennis ? 0xFFD9ED92 : 0xFFFFFFFF));
  // armed power shot (swipe up / booster)
  if (s.power > 0) c.drawCircle(Offset(s.px, s.py), 80, _stroke(0xCCFFD60A, 8));
  _racket(c, s.px, s.py, 0xFF00B4D8, s.tennis, false);
  // reach hint
  c.drawCircle(Offset(s.px, s.py), g.reach, _stroke(0x22FFFFFF, 3));
  if (!s.live && s.server == 0 && s.pause == 0) {
    paintText(c, '▲', Offset(s.px, s.py - 150 - 10 * math.sin(t * 6)), 60, Colors.white70);
  }
  if (s.flashTicks > 0) {
    paintText(c, s.flash, const Offset(500, 120), 72, Colors.white.withValues(alpha: (s.flashTicks / 60).clamp(0.0, 1.0)));
  }
  if (s.rally >= 3 && s.live) paintText(c, '×${s.rally}', const Offset(880, 1560), 40, Colors.white70);
}

Sfx? rallySound(ArcadeSim sim) => switch ((sim as RallySim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.combo,
      3 => Sfx.error,
      4 => Sfx.place,
      _ => null,
    };
