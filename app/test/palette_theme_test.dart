/// La paleta va en el tema, y quien la lee de ahí se entera solo del cambio.
///
/// Antes los colores se leían de una variable global, y cambiar de modo
/// obligaba a recorrer el árbol entero marcándolo todo para reconstruir: un
/// widget que no se reconstruía seguía con los colores del otro modo.
library;

import 'package:didacta_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un widget constante, que su padre no reconstruye nunca por su cuenta.
class _Swatch extends StatelessWidget {
  const _Swatch();

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const Key('swatch'),
    color: context.palette.card,
    child: const SizedBox(width: 10, height: 10),
  );
}

void main() {
  test('cada tema lleva su paleta', () {
    expect(
      didactaTheme(DidactaPalette.dark).extension<DidactaPalette>(),
      same(DidactaPalette.dark),
    );
    expect(
      didactaTheme(DidactaPalette.light).extension<DidactaPalette>(),
      same(DidactaPalette.light),
    );
    // Uno por paleta: el mismo objeto cada vez.
    expect(
      didactaTheme(DidactaPalette.dark),
      same(didactaTheme(DidactaPalette.dark)),
    );
  });

  testWidgets('cambiar el tema repinta lo que lee la paleta, sin más', (
    tester,
  ) async {
    final mode = ValueNotifier(DidactaPalette.light);
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<DidactaPalette>(
        valueListenable: mode,
        builder: (context, palette, child) =>
            MaterialApp(theme: didactaTheme(palette), home: child),
        child: const _Swatch(),
      ),
    );
    Color shown() =>
        tester.widget<ColoredBox>(find.byKey(const Key('swatch'))).color;
    expect(shown(), DidactaPalette.light.card);

    mode.value = DidactaPalette.dark;
    await tester.pumpAndSettle();
    expect(shown(), DidactaPalette.dark.card);
  });

  test('a mitad del cambio, un color de en medio', () {
    final half = DidactaPalette.light.lerp(DidactaPalette.dark, 0.5);
    expect(
      half.card,
      Color.lerp(DidactaPalette.light.card, DidactaPalette.dark.card, 0.5),
    );
    expect(
      DidactaPalette.light.lerp(DidactaPalette.dark, 1),
      isA<DidactaPalette>(),
    );
    expect(DidactaPalette.light.lerp(DidactaPalette.dark, 1).isDark, isTrue);
  });

  testWidgets('fuera de un tema de Didacta, la clara', (tester) async {
    late DidactaPalette found;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            found = context.palette;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(found, same(DidactaPalette.light));
  });
}
