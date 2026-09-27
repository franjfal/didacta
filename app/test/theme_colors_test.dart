/// Ningún color fijo fuera de `theme.dart`: el modo oscuro, blindado.
///
/// Un `Colors.white` o un `Color(0xFF…)` escrito en una pantalla es un color
/// que no cambia al pasar a oscuro, y eso se descubre a ojo, pantalla a
/// pantalla, cuando alguien la abre de noche. Así que se busca aquí: cada
/// color sale de la paleta (`context.palette.ink`, `palette.track`…), y lo que
/// de verdad no debe cambiar con el modo --la paleta de LaTeX, el terminal,
/// el logo-- está en la lista de abajo con su motivo.
///
/// Tampoco un `palette.isDark ? … : …` con colores: si un color depende del
/// modo, es un campo de la paleta.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lo que puede quedarse, y por qué. Por fichero y por lo que se encuentra.
const Map<String, Map<String, String>> allowed = {
  'lib/ui/manage_snippets.dart': {
    'Color(0x':
        'la paleta de didacta-colours.sty: los colores con que imprime el PDF, '
        'que son los mismos en los dos modos',
    'Colors.white': 'la marca encima de una muestra de esa paleta',
  },
  'lib/ui/build_console.dart': {
    'Color(0x': 'el terminal, oscuro en los dos modos',
  },
  'lib/ui/brand.dart': {'Colors.white': 'el logo, que no cambia con el modo'},
};

final RegExp _named = RegExp(r'\bColors\.(\w+)');
final RegExp _literal = RegExp(r'\bColor\(0x');
final RegExp _ternary = RegExp(r'(?:didactaIsDark|palette\.isDark)\s*\?');

/// Lo que se encuentra en [file], como `línea: qué`.
List<String> offences(String file, String text) {
  final found = <String>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i += 1) {
    final line = lines[i];
    final code = line.contains('//')
        ? line.substring(0, line.indexOf('//'))
        : line;
    if (code.trim().isEmpty) continue;
    final exceptions = allowed[file] ?? const {};
    for (final match in _named.allMatches(code)) {
      if (match.group(1) == 'transparent') continue;
      if (exceptions.containsKey('Colors.${match.group(1)}')) continue;
      found.add('${i + 1}: ${match.group(0)}');
    }
    if (_literal.hasMatch(code) && !exceptions.containsKey('Color(0x')) {
      found.add('${i + 1}: Color(0x…)');
    }
    if (_ternary.hasMatch(code) &&
        !exceptions.containsKey('Color(0x') &&
        (_literal.hasMatch(code) ||
            (i + 1 < lines.length && _literal.hasMatch(lines[i + 1])))) {
      found.add('${i + 1}: isDark ? color : color');
    }
  }
  return found;
}

void main() {
  test('los colores salen de la paleta', () {
    final report = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final file = entity.path.replaceAll(r'\', '/');
      if (file == 'lib/ui/theme.dart') continue;
      for (final offence in offences(file, entity.readAsStringSync())) {
        report.add('$file:$offence');
      }
    }
    expect(
      report,
      isEmpty,
      reason:
          'Colores fijos fuera de theme.dart. Cada uno, a la paleta '
          '(DidactaPalette), o a la lista `allowed` de esta prueba con su '
          'motivo:\n${report.join('\n')}',
    );
  });

  test('la prueba ve lo que tiene que ver', () {
    expect(offences('lib/ui/x.dart', 'final a = Colors.white;'), hasLength(1));
    expect(offences('lib/ui/x.dart', 'final a = Colors.transparent;'), isEmpty);
    expect(
      offences('lib/ui/x.dart', 'const a = Color(0xFF000000);'),
      hasLength(1),
    );
    expect(
      offences('lib/ui/x.dart', '// Colors.white en un comentario'),
      isEmpty,
    );
    expect(
      offences(
        'lib/ui/x.dart',
        'Color get a =>\n    didactaIsDark ? const Color(0xFF1) : const Color(0xFF2);',
      ),
      hasLength(2),
    );
    // Leída del tema, igual.
    expect(
      offences(
        'lib/ui/x.dart',
        'final a =\n    context.palette.isDark ? const Color(0xFF1) : const Color(0xFF2);',
      ),
      hasLength(2),
    );
    // Un `isDark ?` con números, no con colores, vale.
    expect(
      offences(
        'lib/ui/x.dart',
        'final a = context.palette.isDark ? 0.4 : 0.1;',
      ),
      isEmpty,
    );
  });
}
