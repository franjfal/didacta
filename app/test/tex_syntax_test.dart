/// Trocear LaTeX: lo que decide de qué color se ve cada cosa.
///
/// Se prueba aquí porque los fallos que importan no se ven: un `\%` tomado por
/// comentario apaga media línea, y un `$` sin cerrar tiñe el resto del
/// fichero.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/tex_syntax.dart';

/// Los trozos de un tipo, tal como se leen en el texto.
List<String> of(String text, TexTokenKind kind) => [
  for (final token in scanLatex(text))
    if (token.kind == kind) text.substring(token.start, token.end),
];

void main() {
  test('el texto sale entero y en orden, sin huecos', () {
    const text = r'Una \norma{x} con $a+b$ y % nota';
    final tokens = scanLatex(text);
    var at = 0;
    for (final token in tokens) {
      expect(token.start, at);
      at = token.end;
    }
    expect(at, text.length);
  });

  test('las órdenes se separan de sus argumentos', () {
    expect(of(r'\section{Normas}', TexTokenKind.command), [r'\section']);
    expect(of(r'\section{Normas}', TexTokenKind.delimiter), ['{', '}']);
    // La estrella es parte de la orden: `\section*` no es `\section`.
    expect(of(r'\section*{x}', TexTokenKind.command), [r'\section*']);
  });

  test('el nombre del entorno va aparte de la orden', () {
    // Es lo que dice **qué** entorno es, y va de su color.
    expect(of(r'\begin{exercise}', TexTokenKind.environment), ['exercise']);
    expect(of(r'\end{exercise}', TexTokenKind.environment), ['exercise']);
    expect(of(r'\begin{exercise}', TexTokenKind.command), [r'\begin']);
    // Un `\beginner` no abre nada.
    expect(of(r'\beginner{x}', TexTokenKind.environment), isEmpty);
  });

  test('un comentario llega hasta el final de la línea', () {
    expect(of('a % nota\nb\n', TexTokenKind.comment), ['% nota']);
  });

  test('un porcentaje escapado no es un comentario', () {
    // `\%` es un carácter. Tomarlo por comentario apaga el resto de la línea.
    expect(of(r'100\% de acierto', TexTokenKind.comment), isEmpty);
    expect(of(r'100\% de acierto', TexTokenKind.command), [r'\%']);
  });

  test('las matemáticas se marcan enteras, con sus delimitadores', () {
    expect(of(r'x $a+b$ y', TexTokenKind.math), [r'$', 'a+b', r'$']);
    expect(of(r'x \[ a \] y', TexTokenKind.math), [r'\[', ' a ', r'\]']);
    expect(of(r'x $$a$$ y', TexTokenKind.math), [r'$$', 'a', r'$$']);
  });

  test('una orden dentro de las matemáticas sigue siendo una orden', () {
    // Es lo que hace que se lean: `\frac` no puede ser del mismo color que la
    // fórmula entera.
    expect(of(r'$\frac{a}{b}$', TexTokenKind.command), [r'\frac']);
    // Y lo de alrededor sigue siendo fórmula.
    expect(of(r'$\frac{a}{b}$', TexTokenKind.math), [r'$', 'a', 'b', r'$']);
  });

  test('los caracteres reservados se marcan', () {
    expect(of(r'a & b \\ c_1 ^2 ~ #1', TexTokenKind.special), [
      '&',
      '_',
      '^',
      '~',
      '#',
    ]);
    expect(of(r'a \\ b', TexTokenKind.command), [r'\\']);
  });

  test('una llave escapada no es un delimitador', () {
    expect(of(r'\{a\}', TexTokenKind.delimiter), isEmpty);
    expect(of(r'\{a\}', TexTokenKind.command), [r'\{', r'\}']);
  });
}
