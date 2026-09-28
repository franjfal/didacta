/// Lo que vale para todas las pruebas de esta carpeta.
///
/// `flutter test` lo busca por su nombre y pasa cada fichero por aquí.
library;

import 'dart:async';

import 'package:didacta_app/data/browser.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Ningún navegador. Con el `open` de verdad, cada prueba que pulsa «Contar
  // un problema» abría la página de incidencias de GitHub en el Mac de quien
  // las pasaba. Como en un sistema sin navegador: no se pudo.
  openLinkWith = (_) async => false;
  await testMain();
}
