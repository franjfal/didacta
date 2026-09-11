/// Encontrar TeX cuando el PATH no lo lleva.
///
/// Este test existe por un fallo que ya ocurrió, y del tipo que no se ve
/// venir: **una aplicación de escritorio no hereda el PATH del terminal**. A
/// una app lanzada desde el Finder launchd le da `/usr/bin:/bin:/usr/sbin:
/// /sbin` y nada más, y en macOS `latexmk` vive en `/Library/TeX/texbin`,
/// que entra en el PATH por `/etc/paths.d/TeX` --que solo lee un shell de
/// login--. Didacta decía «necesita una distribución de TeX» con TeX Live
/// 2026 instalada y compilando en el terminal.
///
/// Lo que se comprueba es lo que se puede comprobar en cualquier máquina: que
/// la lista de sitios sale, que lo configurado va primero, que no se cuelan
/// carpetas que no existen, y que la herramienta se encuentra por ahí y no
/// por el PATH del proceso.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/compiler_io.dart';

void main() {
  test('el PATH lleva los sitios de TeX además de lo heredado', () {
    final path = texAwarePath();
    final inherited = Platform.environment['PATH'] ?? '';
    // Lo heredado, delante: quien haya puesto una versión suya en el PATH la
    // quiere usar, y esto no es quién para adelantarle otra.
    expect(path, startsWith(inherited));
    for (final directory in texDirectories()) {
      expect(path, contains(directory));
    }
  });

  test('solo carpetas que existen', () {
    // La lista va a un PATH: con carpetas que no están, cada búsqueda mira
    // en sitios inventados.
    for (final directory in texDirectories()) {
      expect(Directory(directory).existsSync(), isTrue, reason: directory);
    }
  });

  test('lo configurado va primero, y sin repetir', () {
    final configured = Directory.systemTemp.createTempSync('didacta-tex-');
    addTearDown(() => configured.deleteSync());

    final found = texDirectories(configured: configured.path);
    expect(found.first, configured.path);
    expect(
      found.where((d) => d == configured.path),
      hasLength(1),
      reason: 'repetido',
    );
  });

  test('una carpeta configurada que no existe no entra', () {
    expect(
      texDirectories(configured: '/no/existe/tex'),
      isNot(contains('/no/existe/tex')),
    );
  });

  test('encuentra una herramienta en la carpeta configurada', () async {
    // Sin depender de que la máquina tenga TeX: se finge una herramienta en
    // una carpeta que no está en ningún PATH.
    final directory = Directory.systemTemp.createTempSync('didacta-tex-bin-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final tool = File('${directory.path}/didacta-falso-latexmk')
      ..writeAsStringSync('#!/bin/sh\n');

    expect(
      await findTool('didacta-falso-latexmk', configured: directory.path),
      tool.path,
    );
    // Y no la encuentra si no se dice dónde está, que es la mitad que
    // importa: significa que la búsqueda es la que la encuentra.
    expect(await findTool('didacta-falso-latexmk'), isNull);
  });

  test('lo que no está no se inventa', () async {
    expect(await findTool('esto-no-existe-en-ninguna-parte'), isNull);
  });

  // En esta máquina hay TeX Live. Donde no haya, estos se saltan en lugar de
  // fallar: no son tests del sistema, son tests de la búsqueda.

  test('los sitios de TeX salen sin mirar el PATH', () async {
    // **Esta es la propiedad que arregla el fallo.** La app tenía TeX
    // instalado y no lo encontraba porque preguntaba al PATH, y el PATH de
    // una app de escritorio no lo lleva. Que `/Library/TeX/texbin` esté en
    // esta lista no depende de ningún PATH.
    if (!Platform.isMacOS) return;
    if (!Directory('/Library/TeX/texbin').existsSync()) return;
    expect(texDirectories(), contains('/Library/TeX/texbin'));
  });

  test('en una máquina con TeX, latexmk aparece', () async {
    if (!Platform.isMacOS) return;
    if (!File('/Library/TeX/texbin/latexmk').existsSync()) return;
    expect(await findTool('latexmk'), '/Library/TeX/texbin/latexmk');
  });
}
