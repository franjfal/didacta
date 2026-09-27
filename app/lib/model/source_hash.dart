/// La huella de un original, para saber si una traducción se ha quedado atrás.
///
/// Una traducción guarda en `unit.yaml` la huella que tenía el original
/// cuando se tradujo o se revisó; el motor calcula la del original de ahora y,
/// si no coinciden, la da por desactualizada. Las dos cuentas tienen que dar lo
/// mismo byte a byte, así que esta es la misma que `content_hash` en
/// `engine/didacta/repo.py`, y un test a cada lado comprueba el mismo ejemplo.
///
/// Del texto con el espacio en blanco reducido a un espacio: re-sangrar el
/// original, o que git lo traiga con otros finales de línea, no cambia lo que
/// dice y no puede dejar desactualizadas todas sus traducciones. Solo el
/// espacio en blanco ASCII, para que Dart y Python no puedan discrepar en qué
/// es un espacio.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

final RegExp _whitespace = RegExp(r'[ \t\n\r\f\v]+');

String contentHash(String text) {
  final normalized = text
      .split(_whitespace)
      .where((piece) => piece.isNotEmpty)
      .join(' ');
  final digest = sha256.convert(utf8.encode(normalized)).toString();
  return 'sha256:${digest.substring(0, 16)}';
}
