/// Las fórmulas de una traducción, contra las del original.
///
/// Es la única parte del fichero que tiene que ser idéntica en los dos
/// idiomas, y un error ahí compila y dice otra cosa. Lo que se fija:
///
/// * lo idéntico no avisa, aunque cambien los espacios o el texto de un
///   `\text{…}`, que sí se traduce;
/// * una cambiada se dice como cambiada, con las dos versiones;
/// * una que falta o que sobra no hace que todas las de detrás salgan mal.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/formula_check.dart';

void main() {
  const original =
      r'Sea $f(x) = x^2$ y $g(x) = \sin x$. Entonces'
      '\n'
      r'\[ \int_0^1 f(x)\,dx = \frac{1}{3} \]'
      '\n'
      r'\begin{align} a &= b \text{ si } c \end{align}';

  test('la misma, con otros espacios y otro texto dentro, no avisa', () {
    const translation =
        r'Siga $f(x)=x^2$ i $g(x) = \sin x$. Aleshores'
        '\n'
        r'\[\int_0^1 f(x) dx = \frac{1}{3}\]'
        '\n'
        r'\begin{align} a &= b \text{ si és } c \end{align}';
    expect(compareFormulas(original, translation), isEmpty);
  });

  test('una cambiada se dice con las dos versiones', () {
    const translation =
        r'Siga $f(x) = x^3$ i $g(x) = \sin x$. Aleshores'
        '\n'
        r'\[ \int_0^1 f(x)\,dx = \frac{1}{3} \]'
        '\n'
        r'\begin{align} a &= b \text{ si } c \end{align}';
    final found = compareFormulas(original, translation);
    expect(found, hasLength(1));
    expect(found.single.kind, FormulaDifferenceKind.changed);
    expect(found.single.original, r'$f(x) = x^2$');
    expect(found.single.translation, r'$f(x) = x^3$');
    expect(translation.substring(found.single.offset), startsWith(r'$f(x)'));
  });

  test('una que falta no descuadra las de detrás', () {
    const translation =
        r'Siga $g(x) = \sin x$. Aleshores'
        '\n'
        r'\[ \int_0^1 f(x)\,dx = \frac{1}{3} \]'
        '\n'
        r'\begin{align} a &= b \text{ si } c \end{align}';
    final found = compareFormulas(original, translation);
    expect(found, hasLength(1));
    expect(found.single.kind, FormulaDifferenceKind.missing);
    expect(found.single.original, r'$f(x) = x^2$');
  });

  test('una que sobra, también', () {
    const translation =
        r'Siga $f(x) = x^2$, $h$ i $g(x) = \sin x$. Aleshores'
        '\n'
        r'\[ \int_0^1 f(x)\,dx = \frac{1}{3} \]'
        '\n'
        r'\begin{align} a &= b \text{ si } c \end{align}';
    final found = compareFormulas(original, translation);
    expect(found, hasLength(1));
    expect(found.single.kind, FormulaDifferenceKind.extra);
    expect(found.single.translation, r'$h$');
  });

  test('como avisos del editor, en su línea', () {
    const translation =
        'Siga \$f(x) = x^2\$ i \$g(x) = \\sin x\$.\n'
        r'\[ \int_0^2 f(x)\,dx = \frac{1}{3} \]'
        '\n'
        r'\begin{align} a &= b \text{ si } c \end{align}';
    final warnings = formulaWarnings(original, translation);
    expect(warnings, hasLength(1));
    expect(warnings.single.line, 2);
    expect(warnings.single.message, contains('no es la del original'));
  });
}
