/// Lo que se dice cuando la carpeta donde iría un clon ya tiene otra cosa.
///
/// Remitía a un botón «Abrir una carpeta» que no existía. Aquí se fija que
/// lo que nombra es una sección de Ajustes de verdad.
library;

import 'package:didacta_app/ui/add_repository.dart';
import 'package:didacta_app/ui/settings_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';

void main() {
  test('remite a la sección donde se elige dónde se clonan', () {
    final said = occupiedFolderMessage(
      directory: '/Users/ana/Didacta/curso',
      repo: 'dep/curso',
    );
    final labels = [
      for (final section in settingsSections(
        FakeSession(
          gatewayOverride: FakeGateway(),
          catalogue: catalogueWith(defaultUnits()),
        ),
      ))
        section.label,
    ];
    final named = RegExp(r'Ajustes → ([^.]+)\.').firstMatch(said)?.group(1);
    expect(named, isNotNull, reason: said);
    expect(labels, contains(named));
    expect(said, isNot(contains('Abrir una carpeta')));
    expect(said, contains('/Users/ana/Didacta/curso'));
    expect(said, contains('dep/curso'));
  });
}
