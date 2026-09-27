/// Lo que se lee tiene que poder leerse, en claro y en oscuro.
///
/// Tres sitios que no pasaban: los colores de repositorio, que eran los de la
/// paleta clara y se usan como texto; la acción de los avisos en oscuro; y el
/// número blanco sobre ámbar del carril en claro.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/workspace.dart';
import 'package:didacta_app/ui/theme.dart';

double contrast(Color a, Color b) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final one = luminance(a);
  final two = luminance(b);
  return (math.max(one, two) + 0.05) / (math.min(one, two) + 0.05);
}

void main() {
  for (final palette in [DidactaPalette.light, DidactaPalette.dark]) {
    final name = palette.isDark ? 'oscuro' : 'claro';
    group('en $name', () {
      test('los colores de repositorio, como texto', () {
        for (final colour in repoColours) {
          expect(
            contrast(palette.repo(colour), palette.surface),
            greaterThanOrEqualTo(4.5),
            reason: '#${colour.toRadixString(16)} sobre la página',
          );
        }
      });

      test('la acción de un aviso', () {
        final theme = didactaTheme(palette).snackBarTheme;
        expect(
          contrast(theme.actionTextColor!, theme.backgroundColor!),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('el número del carril', () {
        expect(
          contrast(palette.onPending, palette.pending),
          greaterThanOrEqualTo(4.5),
        );
      });
    });
  }
}
