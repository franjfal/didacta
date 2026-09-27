/// Completar al escribir: qué se ofrece, y qué queda al aceptar.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/tex_vocabulary.dart';

/// El texto con `|` donde está el cursor.
TexCompletionQuery? at(String marked) =>
    completionAt(marked.replaceFirst('|', ''), marked.indexOf('|'));

/// Acepta [name] en [marked] y devuelve el resultado con `|` en el cursor.
String accept(String marked, String name) {
  final text = marked.replaceFirst('|', '');
  final query = at(marked)!;
  final word = query.words.firstWhere((word) => word.name == name);
  final edit = acceptCompletion(text, query, word);
  return edit.text.replaceRange(edit.start, edit.start, '|');
}

void main() {
  group('qué se ofrece', () {
    test('una orden, a partir de la primera letra', () {
      expect(at(r'Hola \|'), isNull);
      expect(at(r'\didac|')!.words.first.name, 'didactatitle');
      expect(at(r'\bym|')!.words.single.name, 'bymedium');
    });

    test('las de las paletas también', () {
      expect(at(r'$\alp|')!.words.first.name, 'alpha');
      expect(at(r'$\Om|')!.words.map((w) => w.name), ['Omega', 'omega']);
    });

    test(r'\\ seguido de letras no es una orden', () {
      expect(at(r'fin\\it|'), isNull);
      expect(at(r'fin\\\it|')!.words.first.name, 'item');
    });

    test('ya escrita entera, no molesta', () {
      expect(at(r'\item|'), isNull);
      // Pero si hay otra más larga, sí: `\sen`, `\senh`, y después lo que la
      // contiene.
      expect(at(r'$\sen|')!.words.map((w) => w.name), [
        'sen',
        'senh',
        'arcsen',
      ]);
    });

    test(r'un entorno, en cuanto se abre la llave de \begin', () {
      final query = at(r'\begin{|')!;
      expect(query.kind, TexCompletionKind.begin);
      expect(query.words.first.name, 'frame');
      expect(at(r'\begin{teach|')!.words.map((w) => w.name), [
        'teaching',
        'teacheronly',
      ]);
      expect(at(r'\begin{comm|')!.words.single.name, 'commonmistake');
    });

    test(r'\end{ ofrece primero el que está abierto', () {
      expect(
        at('\\begin{frame}\n\\begin{proof}\nUno\n\\end{|')!.words.first.name,
        'proof',
      );
    });
  });

  group('qué queda al aceptar', () {
    test('una orden con argumento deja el cursor dentro', () {
      expect(
        accept(r'\didac| y más', 'didactatitle'),
        r'\didactatitle{|} y más',
      );
      expect(accept(r'\bym|', 'bymedium'), r'\bymedium{|}{}');
      expect(accept(r'$\fra|$', 'frac'), r'$\frac{|}{}$');
    });

    test('una sin argumentos, con un espacio detrás', () {
      expect(accept(r'$\alp|x$', 'alpha'), r'$\alpha |x$');
      expect(accept(r'$\alp| x$', 'alpha'), r'$\alpha| x$');
    });

    test('un entorno se abre y se cierra, con el cursor en medio', () {
      expect(
        accept(r'\begin{teach|', 'teaching'),
        '\\begin{teaching}\n|\n\\end{teaching}',
      );
      // Con la llave ya cerrada, no se escribe otra.
      expect(
        accept(r'\begin{|}', 'theorem'),
        '\\begin{theorem}\n|\n\\end{theorem}',
      );
    });

    test(r'\end{ solo cierra', () {
      expect(
        accept('\\begin{proof}\n\\end{|', 'proof'),
        '\\begin{proof}\n\\end{proof}|',
      );
    });
  });

  test('lo que enseña AUTHORING.md está en la lista', () {
    // Las dos listas se separan en cuanto alguien añade una orden al
    // documento y no aquí. Hasta «Composiciones», que es lo que va en un
    // documento y no en una lección.
    final text = File('../docs/AUTHORING.md').readAsStringSync();
    final lessons = text.substring(0, text.indexOf('## Composiciones'));
    final commands = {for (final word in texCommands) word.name};
    final environments = {for (final word in didactaEnvironments) word.name};

    // Lo que el documento nombra para decir que no se use, o que es de
    // LaTeX y aparece en un ejemplo.
    const notOffered = {
      'documentclass',
      'frametitle',
      'pause',
      'marks',
      'onlybook',
      'fbox',
      'mathbb',
      'cdot',
      'lambda',
      'max',
      'in',
      'neq',
      'sqrt',
      'import',
      'DidactaBibliography',
      'shownto',
      'ej',
      'nformula',
      'document',
      'definition*',
      'exercise*',
      'par',
      'subsection',
      'textwidth',
    };
    final missing = <String>{};
    for (final match in RegExp(r'\\([A-Za-z]+)').allMatches(lessons)) {
      final name = match.group(1)!;
      if (!commands.contains(name) && !notOffered.contains(name)) {
        missing.add('\\$name');
      }
    }
    for (final match in RegExp(
      r'\\begin\{([A-Za-z*]+)\}',
    ).allMatches(lessons)) {
      final name = match.group(1)!;
      if (!environments.contains(name) && !notOffered.contains(name)) {
        missing.add(name);
      }
    }
    expect(missing, isEmpty);
  });
}
