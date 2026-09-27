/// Los textos de Material, en castellano.
///
/// El menú contextual del editor salía en inglés --Cut, Copy, Paste-- porque
/// Material no sabía en qué idioma estaba la aplicación.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/ui/shell.dart';

import 'platform_menus_test.dart' show pumpApp;

void main() {
  testWidgets('cortar, copiar y pegar se dicen en castellano', (tester) async {
    await pumpApp(tester);
    final context = tester.element(find.byType(DidactaShell));
    final material = MaterialLocalizations.of(context);
    expect(material.cutButtonLabel, 'Cortar');
    expect(material.copyButtonLabel, 'Copiar');
    expect(material.pasteButtonLabel, 'Pegar');
    expect(Localizations.localeOf(context).languageCode, 'es');
  });
}
