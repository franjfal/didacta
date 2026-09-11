/// El tema, donde una decisión mala se multiplica por toda la aplicación.
///
/// Existe por un fallo que se veía en la pantalla de compilar y estaba en el
/// tema: `backgroundColor` en blanco y `selectedColor` sin poner, así que un
/// chip seleccionado se pintaba **igual** que uno sin seleccionar. Los chips
/// son el control con el que se elige el tipo de una unidad, su estado de
/// traducción y qué versiones compilar; en una fila de siete, una marca de
/// verificación no se lee.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/ui/theme.dart';

/// El contraste WCAG entre dos colores opacos.
double contrastRatio(Color a, Color b) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final one = luminance(a);
  final two = luminance(b);
  final hi = math.max(one, two);
  final lo = math.min(one, two);
  return (hi + 0.05) / (lo + 0.05);
}

/// [colour] compuesto sobre [over], que es lo que se ve cuando lleva alfa.
Color flatten(Color colour, Color over) => Color.from(
  alpha: 1,
  red: colour.r * colour.a + over.r * (1 - colour.a),
  green: colour.g * colour.a + over.g * (1 - colour.a),
  blue: colour.b * colour.a + over.b * (1 - colour.a),
);

void main() {
  final theme = didactaTheme();

  group('los chips', () {
    test('seleccionado y sin seleccionar no se pintan igual', () {
      // El fallo, exactamente.
      final chips = theme.chipTheme;
      expect(chips.selectedColor, isNotNull);
      expect(chips.selectedColor, isNot(chips.backgroundColor));
    });

    test('el relleno de seleccionado se distingue del de al lado', () {
      // Un relleno que solo se distingue midiéndolo no se distingue.
      final selected = flatten(theme.chipTheme.selectedColor!, Colors.white);
      expect(
        contrastRatio(selected, Colors.white),
        greaterThan(1.15),
        reason: 'el relleno seleccionado casi no se ve sobre blanco',
      );
    });

    test('la selección se dice de tres formas, no de una', () {
      // Relleno, borde y peso. Una sola señal es frágil: el relleno se pierde
      // en una captura, el borde a tamaño pequeño.
      final side = theme.chipTheme.side;
      expect(side, isA<WidgetStateBorderSide>());
      final stateful = side! as WidgetStateBorderSide;
      final selected = stateful.resolve({WidgetState.selected})!;
      final plain = stateful.resolve(<WidgetState>{})!;
      expect(selected.color, isNot(plain.color));
      expect(selected.width, greaterThan(plain.width));

      expect(theme.chipTheme.secondaryLabelStyle?.fontWeight, FontWeight.w700);
      expect(theme.chipTheme.labelStyle?.fontWeight, isNot(FontWeight.w700));
    });

    test('la etiqueta tiene un color puesto, no el que caiga', () {
      // Sin color explícito hereda el del contexto, y el contexto cambia:
      // un chip en un panel gris y otro en una tarjeta blanca.
      expect(theme.chipTheme.labelStyle?.color, isNotNull);
      expect(
        contrastRatio(theme.chipTheme.labelStyle!.color!, Colors.white),
        greaterThan(4.5),
      );
    });

    test(
      'la etiqueta de un ChoiceChip seleccionado se lee sobre su relleno',
      () {
        final fill = flatten(theme.chipTheme.selectedColor!, Colors.white);
        final label = theme.chipTheme.secondaryLabelStyle!.color!;
        expect(
          contrastRatio(label, fill),
          greaterThan(4.5),
          reason: 'el texto de un chip elegido no llega al contraste mínimo',
        );
      },
    );
  });

  group('los colores del sistema', () {
    test('el texto apagado llega al contraste mínimo', () {
      // `didactaMuted` está en rutas, recuentos y subtítulos de toda la
      // aplicación: si no llega, no llega en cien sitios.
      expect(contrastRatio(didactaMuted, Colors.white), greaterThan(4.5));
      expect(contrastRatio(didactaMuted, didactaPanel), greaterThan(4.0));
    });

    test('el acento se lee sobre blanco y sobre el panel', () {
      expect(contrastRatio(didactaAccentDark, Colors.white), greaterThan(4.5));
      expect(contrastRatio(didactaAccentDark, didactaPanel), greaterThan(4.0));
    });

    test('el blanco se lee sobre el acento, que es un botón lleno', () {
      expect(contrastRatio(Colors.white, didactaAccentDark), greaterThan(4.5));
    });

    test('cada color de estado de traducción se lee sobre blanco', () {
      // Son insignias con texto de dos letras: si una no contrasta, ese
      // estado es el que nadie ve.
      for (final entry in {
        'thm': didactaThm,
        'ex': didactaEx,
        'ques': didactaQues,
        'teacher': didactaTeacher,
        'defn': didactaDefn,
      }.entries) {
        expect(
          contrastRatio(entry.value, Colors.white),
          greaterThan(3.0),
          reason: entry.key,
        );
      }
    });
  });

  group('el tono de la interfaz', () {
    test('el gris del texto secundario se lee sobre las dos superficies', () {
      // Casi todo lo que va en este gris es contenido --rutas, recuentos,
      // estados-- y no adorno, así que tiene que pasar AA en la página y en
      // una tarjeta, que son los dos fondos que hay.
      for (final over in [didactaSurface, didactaCard, didactaPanel]) {
        expect(
          contrastRatio(didactaMuted, over),
          greaterThanOrEqualTo(4.5),
          reason: 'sobre $over',
        );
      }
    });

    test('una tarjeta se distingue de la página sin necesitar sombra', () {
      // La regla de la casa es que no hay sombras en las listas. Entonces lo
      // único que separa una tarjeta del fondo es el tono, y si los dos son
      // el mismo blanco no separa nada.
      expect(didactaCard, isNot(didactaSurface));
      expect(
        contrastRatio(didactaCard, didactaSurface),
        greaterThan(1.02),
        reason: 'la tarjeta y la página son el mismo color',
      );
    });

    test('el resalte del ratón se ve, y no tapa el texto', () {
      final over = flatten(didactaHover, didactaCard);
      // Que se vea...
      expect(contrastRatio(over, didactaCard), greaterThan(1.01));
      // ...y que el texto encima siga leyéndose.
      expect(contrastRatio(didactaInk, over), greaterThanOrEqualTo(7));
      expect(contrastRatio(didactaMuted, over), greaterThanOrEqualTo(4.5));
    });

    test('los radios son los del tema, no números sueltos', () {
      // Que exista un sitio donde cambiarlos: el fallo que esto evita es
      // media aplicación a 4 px y la otra media a 8.
      final theme = didactaTheme();
      final card = theme.cardTheme.shape! as RoundedRectangleBorder;
      expect(card.borderRadius, BorderRadius.circular(Radii.card));
      final dialog = theme.dialogTheme.shape! as RoundedRectangleBorder;
      expect(dialog.borderRadius, BorderRadius.circular(Radii.dialog));
    });
  });
}
