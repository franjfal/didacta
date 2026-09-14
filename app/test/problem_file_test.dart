/// Un problema como tres campos, y como un `.tex` que no pierde nada.
///
/// Esto existe por un dato: de los 429 ficheros de `problems/` del
/// repositorio, **ninguno** usa `\begin{answer}`. El entorno está definido y
/// documentado desde el principio --«el resultado, una línea»-- y no lo usa
/// nadie, porque para usarlo hay que saber que existe. Tres campos con su
/// nombre lo convierten en algo que se rellena.
///
/// Lo que hay que demostrar es lo de siempre aquí: que editar un campo no se
/// lleva por delante lo que hay alrededor.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/problem_file.dart';

const String full = r'''
\begin{exercise}
Derivar $f(x) = x^2$.
\end{exercise}
\medskip

\begin{solution}
Por la regla de la potencia, $f'(x) = 2x$.
\end{solution}
''';

const String bare = r'''
Calcular el límite de la sucesión.
''';

/// La otra forma, y la que escribe `didacta new unit --kind problem`: todo
/// dentro del `exercise`.
const String nested = r'''
\begin{exercise}[Axiomas de norma]
Derivar $f(x) = x^2$.

\dmarks{4}

\begin{hint}
Una pista, no una respuesta.
\end{hint}

\begin{answer}
$f'(x) = 2x$
\end{answer}

\begin{solution}
Por la regla de la potencia.
\end{solution}

\begin{marking}
Un punto por apartado.
\end{marking}
\end{exercise}
''';

List<File> realProblems() {
  final directory = Directory(
    '${Directory.current.parent.parent.path}/didacta_db/problems',
  );
  if (!directory.existsSync()) return const [];
  return [
    for (final file in directory.listSync(recursive: true))
      if (file is File && file.path.endsWith('.tex')) file,
  ];
}

void main() {
  group('leer', () {
    test('separa enunciado y solución', () {
      final problem = ProblemFile(full);
      expect(problem.shape.fits, isTrue);
      expect(problem.part(ProblemPart.statement), r'Derivar $f(x) = x^2$.');
      expect(
        problem.part(ProblemPart.solution),
        r"Por la regla de la potencia, $f'(x) = 2x$.",
      );
      expect(problem.part(ProblemPart.answer), isEmpty);
      expect(problem.has(ProblemPart.answer), isFalse);
    });

    test('con los campos dentro del exercise, el enunciado es el enunciado', () {
      // La forma que escribe `didacta new`, y la del material migrado. El
      // enunciado acaba donde empieza lo que lleva dentro: si llegara hasta
      // el `\end{exercise}` se comería la pista, el resultado, la solución y
      // la corrección --y escribir en el campo los borraría--.
      final problem = ProblemFile(nested);
      expect(problem.shape.fits, isTrue);
      expect(problem.part(ProblemPart.statement), contains('Derivar'));
      expect(problem.part(ProblemPart.statement), isNot(contains('pista')));
      expect(problem.part(ProblemPart.statement), isNot(contains('potencia')));
      expect(problem.part(ProblemPart.answer), r"$f'(x) = 2x$");
      expect(problem.part(ProblemPart.solution), 'Por la regla de la potencia.');
      // El corte está en el primer entorno de dentro, así que lo que haya
      // suelto antes --un `\dmarks`, un `\includegraphics`-- es enunciado y
      // se edita con él. Es donde tiene que estar: se escribió ahí.
      expect(problem.part(ProblemPart.statement), contains(r'\dmarks{4}'));
    });

    test('un fichero sin entornos es todo enunciado', () {
      // 72 de los 429 están así: enunciados que la migración no envolvió.
      final problem = ProblemFile(bare);
      expect(problem.bare, isTrue);
      expect(problem.shape.fits, isTrue);
      expect(
        problem.part(ProblemPart.statement),
        'Calcular el límite de la sucesión.',
      );
    });

    test('con dos problemas dentro, se dice y no se toca', () {
      // Una hoja entera en un fichero: los campos son de un problema, y
      // partirla por las buenas sería decidir por quien la escribió.
      final problem = ProblemFile('$full\n$full');
      expect(problem.shape.fits, isFalse);
      expect(problem.shape.reason, contains('2 problemas'));
    });
  });

  group('escribir', () {
    test('cambiar el enunciado no toca la solución', () {
      final text = ProblemFile(
        full,
      ).withPart(ProblemPart.statement, r'Derivar $f(x) = x^3$.');
      final again = ProblemFile(text);
      expect(again.part(ProblemPart.statement), r'Derivar $f(x) = x^3$.');
      expect(
        again.part(ProblemPart.solution),
        r"Por la regla de la potencia, $f'(x) = 2x$.",
      );
      // Y lo que hay entre medias sigue ahí.
      expect(text, contains(r'\medskip'));
    });

    test('poner un resultado lo crea entre el enunciado y la solución', () {
      // El orden en que se lee, y el que escribe el paquete de LaTeX.
      final text = ProblemFile(
        full,
      ).withPart(ProblemPart.answer, r"$f'(x) = 2x$");
      expect(
        text.indexOf(r'\begin{answer}'),
        greaterThan(text.indexOf(r'\end{exercise}')),
      );
      expect(
        text.indexOf(r'\begin{answer}'),
        lessThan(text.indexOf(r'\begin{solution}')),
      );
      final again = ProblemFile(text);
      expect(again.shape.fits, isTrue);
      expect(again.part(ProblemPart.answer), r"$f'(x) = 2x$");
      expect(again.part(ProblemPart.statement), r'Derivar $f(x) = x^2$.');
    });

    test('editar el enunciado de un fichero anidado no borra lo demás', () {
      // Era el fallo: `withPart` sustituía desde el `\begin{exercise}` hasta
      // el `\end`, así que cambiar una coma del enunciado se llevaba por
      // delante el resultado y la solución de un fichero recién creado.
      final text = ProblemFile(
        nested,
      ).withPart(ProblemPart.statement, r'Derivar $f(x) = x^3$.');
      final again = ProblemFile(text);
      expect(again.part(ProblemPart.statement), r'Derivar $f(x) = x^3$.');
      expect(again.part(ProblemPart.answer), r"$f'(x) = 2x$");
      expect(again.part(ProblemPart.solution), 'Por la regla de la potencia.');
      expect(text, contains(r'\begin{hint}'));
      expect(text, contains(r'\begin{marking}'));
    });

    test('en un fichero anidado el resultado entra dentro', () {
      // Se respeta la forma del fichero: un `answer` detrás del
      // `\end{exercise}` en un fichero que lo lleva todo dentro se lee raro
      // y se edita peor.
      final without = nested.replaceFirst(
        RegExp(r'\\begin\{answer\}[\s\S]*?\\end\{answer\}\n\n'),
        '',
      );
      expect(ProblemFile(without).has(ProblemPart.answer), isFalse);
      final text = ProblemFile(without).withPart(ProblemPart.answer, '42');
      expect(
        text.indexOf(r'\begin{answer}'),
        lessThan(text.indexOf(r'\end{exercise}')),
      );
      expect(ProblemFile(text).part(ProblemPart.answer), '42');
      expect(ProblemFile(text).part(ProblemPart.statement), contains('Derivar'));
    });

    test('vaciar el enunciado no se lleva el entorno', () {
      // Hay ficheros con material fuera del `exercise`, y quitarlo por haber
      // borrado un campo cambiaría cómo se imprime todo lo demás.
      final text = ProblemFile(full).withPart(ProblemPart.statement, '');
      expect(text, contains(r'\begin{exercise}'));
      expect(ProblemFile(text).shape.fits, isTrue);
    });

    test('vaciar un campo se lleva el entorno', () {
      // Un `\begin{answer}\end{answer}` vacío pinta un recuadro vacío en la
      // hoja con resultados.
      final text = ProblemFile(full).withPart(ProblemPart.solution, '');
      expect(text, isNot(contains(r'\begin{solution}')));
      expect(text, isNot(contains(r'\end{solution}')));
      expect(text, contains(r'\begin{exercise}'));
      expect(ProblemFile(text).part(ProblemPart.statement), isNotEmpty);
    });

    test('una solución en un fichero suelto envuelve el enunciado', () {
      // `answer` fuera de un `exercise` no se numera ni se encuadra, así que
      // ponerle una solución a un fichero pelado obliga a envolverlo.
      final text = ProblemFile(bare).withPart(ProblemPart.solution, 'Es 0.');
      final again = ProblemFile(text);
      expect(again.bare, isFalse);
      expect(
        again.part(ProblemPart.statement),
        'Calcular el límite de la sucesión.',
      );
      expect(again.part(ProblemPart.solution), 'Es 0.');
    });

    test('editar el enunciado de un fichero pelado lo deja pelado', () {
      // Envolverlo sin que nadie lo pida cambiaría cómo sale impreso.
      final text = ProblemFile(bare).withPart(ProblemPart.statement, 'Otra.');
      expect(text, isNot(contains(r'\begin{exercise}')));
      expect(text.trim(), 'Otra.');
    });

    test('un cambio de varias líneas entra entero', () {
      final text = ProblemFile(
        full,
      ).withPart(ProblemPart.solution, 'Primero.\n\nDespués:\n\\[ 2x \\]');
      final again = ProblemFile(text);
      expect(again.part(ProblemPart.solution), contains('Después:'));
      expect(again.part(ProblemPart.solution), contains(r'\[ 2x \]'));
    });
  });

  group('contra los problemas de verdad', () {
    test('el que encaja se lee y se vuelve a escribir igual', () {
      final files = realProblems();
      if (files.isEmpty) {
        markTestSkipped('sin didacta_db al lado');
        return;
      }
      var fits = 0;
      for (final file in files) {
        final text = file.readAsStringSync();
        final problem = ProblemFile(text);
        if (!problem.shape.fits) continue;
        fits += 1;
        // Escribir lo que ya había no puede cambiar el fichero.
        for (final part in ProblemPart.values) {
          if (!problem.has(part)) continue;
          final again = problem.withPart(part, problem.part(part));
          expect(
            ProblemFile(again).part(part),
            problem.part(part),
            reason: '${file.path} ($part)',
          );
        }
      }
      // La mayoría tienen que encajar, o los campos no sirven de nada.
      expect(
        fits,
        greaterThan(files.length * 0.8),
        reason: '$fits de ${files.length}',
      );
    });

    test('ninguno usa todavía el resultado, que es el punto', () {
      final files = realProblems();
      if (files.isEmpty) {
        markTestSkipped('sin didacta_db al lado');
        return;
      }
      final withAnswer = files
          .where(
            (f) => ProblemFile(f.readAsStringSync()).has(ProblemPart.answer),
          )
          .length;
      // Si algún día esto falla será porque alguien empezó a rellenarlo, que
      // es exactamente lo que este editor viene a conseguir.
      expect(withAnswer, 0);
    });
  });
}
