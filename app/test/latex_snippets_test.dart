/// Los snippets: qué ofrece la barra en cada repositorio, qué se escribe en
/// `snippets.yaml` y qué no coincide entre dos repositorios.
///
/// Lo que se fija aquí es lo que no puede fallar sin que nadie se entere:
///
/// * un repositorio sin fichero ofrece exactamente lo de antes;
/// * una entrada con solo el id es la de Didacta, y retocar un campo escribe
///   ese campo y nada más;
/// * escribir el fichero no se lleva por delante sus comentarios, y lo que se
///   escribe se vuelve a leer igual --los bloques `|` de LaTeX incluidos--;
/// * dos repositorios que dicen cosas distintas del mismo id salen como
///   conflicto, campo a campo;
/// * el título de una caja en varios idiomas se escribe como lo lee
///   `\DidactaTranslated` y se vuelve a leer igual.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/model/latex_snippets.dart';
import 'package:didacta_app/model/snippets_file.dart';
import 'package:didacta_app/model/tex_wrap.dart';

Catalogue withSnippets(Map<String, List<SnippetDeclaration>?> snippets) =>
    Catalogue(
      name: 't',
      languages: const ['es'],
      defaultLanguage: 'es',
      contentHash: '',
      units: const [],
      courses: const [],
      profiles: const [],
      errors: const [],
      snippets: snippets,
    );

const resumen = SnippetDeclaration(
  id: 'resumen',
  label: 'Resumen',
  group: 'Teoría',
  environment: 'resumen',
  arguments: '[Título]',
  definition: r'\DidactaNewTheorem{resumen}{Resumen}{didactaThm}',
  sample: 'Lo esencial.',
);

void main() {
  group('lo que ofrece un repositorio', () {
    test('sin fichero, los de serie en su orden', () {
      final catalogue = withSnippets({'a': null});
      expect(
        [for (final s in catalogue.snippetsIn('a')) s.id],
        [for (final w in didactaWrappers) w.id],
      );
      // Y un repositorio que el índice no trae, lo mismo.
      expect(catalogue.snippetsIn('otro').length, didactaWrappers.length);
      expect(catalogue.snippetsIn(null).length, didactaWrappers.length);
    });

    test('con fichero, exactamente lo que dice', () {
      final catalogue = withSnippets({
        'a': const [SnippetDeclaration(id: 'theorem'), resumen],
      });
      final list = catalogue.snippetsIn('a');
      expect([for (final s in list) s.id], ['theorem', 'resumen']);
      expect(list.first.label, 'Teorema');
      expect(list.first.environmentAliases, contains('thrm'));
      expect(list.last.fromDidacta, isFalse);
      expect(list.last.usage, r'\begin{resumen}[Título] … \end{resumen}');
    });

    test('una entrada retoca solo lo que dice', () {
      final retouched = LatexSnippet.resolve(
        const SnippetDeclaration(id: 'theorem', label: 'Teorema (grande)'),
      );
      expect(retouched.label, 'Teorema (grande)');
      expect(retouched.environment, 'theorem');
      expect(retouched.retouched, isTrue);
      final declared = retouched.toDeclaration();
      expect(declared.label, 'Teorema (grande)');
      expect(declared.environment, isNull);
      expect(declared.environmentAliases, isNull);
      expect(declared.sample, isNull);
    });

    test('uno de serie sin retocar se escribe como una referencia', () {
      final plain = LatexSnippet.fromWrapper(didactaWrapperById('onlyslides')!);
      expect(plain.retouched, isFalse);
      expect(plain.toDeclaration().isReference, isTrue);
    });

    test('uno propio se escribe entero', () {
      final own = LatexSnippet.resolve(resumen);
      final declared = own.toDeclaration();
      expect(declared.environment, 'resumen');
      expect(declared.arguments, '[Título]');
      expect(declared.definition, contains('DidactaNewTheorem'));
    });

    test('la vista previa envuelve el texto de ejemplo', () {
      final own = LatexSnippet.resolve(resumen);
      expect(
        own.previewBody,
        '\\begin{resumen}[Título]\nLo esencial.\n\\end{resumen}',
      );
    });
  });

  group('la biblioteca', () {
    test('cose el orden de los dos repositorios', () {
      final catalogue = withSnippets({
        'teoria': const [
          SnippetDeclaration(id: 'theorem'),
          resumen,
          SnippetDeclaration(id: 'proof'),
        ],
        'problemas': const [
          SnippetDeclaration(id: 'exercise'),
          SnippetDeclaration(id: 'theorem'),
          SnippetDeclaration(id: 'pista-larga', environment: 'pistalarga'),
        ],
      });
      final library = catalogue.snippetLibrary(['teoria', 'problemas']);
      final ids = [for (final e in library) e.id];
      expect(ids.take(5), [
        'exercise',
        'theorem',
        'pista-larga',
        'resumen',
        'proof',
      ]);
      // Los de serie que no tiene nadie, al final y sin repositorio.
      final slides = library.firstWhere((e) => e.id == 'onlyslides');
      expect(slides.byRepo, isEmpty);
      expect(slides.fromDidacta, isTrue);
      expect(library.firstWhere((e) => e.id == 'theorem').byRepo.keys, [
        'teoria',
        'problemas',
      ]);
    });

    test('lo que no coincide sale campo a campo', () {
      final catalogue = withSnippets({
        'teoria': const [resumen],
        'problemas': const [
          SnippetDeclaration(
            id: 'resumen',
            label: 'Resumen',
            group: 'Teoría',
            environment: 'resumen',
            arguments: '[Título]',
            definition: r'\DidactaNewTheorem{resumen}{Resumen}{didactaDefn}',
            sample: 'Lo esencial.',
          ),
          SnippetDeclaration(id: 'theorem'),
        ],
      });
      final conflicts = catalogue.snippetConflicts(['teoria', 'problemas']);
      expect(conflicts, hasLength(1));
      expect(conflicts.single.id, 'resumen');
      expect(conflicts.single.differences.keys, ['definición']);
    });

    test('dos que dicen lo mismo no discrepan', () {
      final catalogue = withSnippets({
        'teoria': const [resumen, SnippetDeclaration(id: 'theorem')],
        'problemas': const [resumen, SnippetDeclaration(id: 'theorem')],
      });
      expect(catalogue.snippetConflicts(['teoria', 'problemas']), isEmpty);
    });

    test('el índice de un repositorio se lee y se junta', () {
      final a = Catalogue.fromIndex(
        manifest: {
          'schemaVersion': supportedSchemaVersion,
          'snippets': [
            {'id': 'theorem'},
            {'id': 'resumen', 'environment': 'resumen', 'block': true},
          ],
        },
        units: {'schemaVersion': supportedSchemaVersion},
        courses: {'schemaVersion': supportedSchemaVersion},
        repo: 'a',
      );
      final b = Catalogue.fromIndex(
        manifest: {'schemaVersion': supportedSchemaVersion},
        units: {'schemaVersion': supportedSchemaVersion},
        courses: {'schemaVersion': supportedSchemaVersion},
        repo: 'b',
      );
      final merged = Catalogue.merge([a, b]);
      expect(merged.declaresSnippets('a'), isTrue);
      expect(merged.declaresSnippets('b'), isFalse);
      expect(merged.snippetsIn('a').last.block, isTrue);
      expect(merged.snippetsIn('b').length, didactaWrappers.length);
    });
  });

  group('snippets.yaml', () {
    test('uno nuevo trae los de serie escritos', () {
      final file = SnippetsFile.withDefaults();
      expect(file.ids, [for (final w in didactaWrappers) w.id]);
      expect(file.text, contains('# Los snippets de este repositorio'));
    });

    test('poner, mover y quitar conserva los comentarios', () {
      final file = SnippetsFile(
        '# Cabecera que alguien escribió\n'
        'snippets:\n'
        '  # los teoremas primero\n'
        '  - id: theorem\n'
        '  - id: proof\n'
        '\n'
        '# y una nota al final\n',
      );
      file.put(resumen, after: 'theorem');
      expect(file.ids, ['theorem', 'resumen', 'proof']);
      file.reorder(['proof', 'theorem']);
      expect(file.ids, ['proof', 'theorem', 'resumen']);
      file.remove('theorem');
      expect(file.ids, ['proof', 'resumen']);
      expect(file.text, contains('# Cabecera que alguien escribió'));
      expect(file.text, contains('# y una nota al final'));
    });

    test('cambiar una entrada la sustituye donde está', () {
      final file = SnippetsFile('snippets:\n  - id: a\n  - id: b\n');
      file.put(const SnippetDeclaration(id: 'a', label: 'A de nuevo'));
      expect(file.ids, ['a', 'b']);
      expect(file.text, contains("label: A de nuevo"));
    });

    test('quitar la última deja la lista vacía y no los de serie', () {
      final file = SnippetsFile('snippets:\n  - id: a\n');
      file.remove('a');
      expect(file.text, contains('snippets: []'));
      expect(file.ids, isEmpty);
    });

    test('el LaTeX de varias líneas va en un bloque, sin comillas', () {
      final lines = renderSnippet(
        const SnippetDeclaration(
          id: 'caja',
          environment: 'caja',
          arguments: '{Título}',
          definition:
              '\t\\newenvironment{caja}[1]{\\par\\textbf{#1}}{\\par}\n\n% fin',
          sample: '# no es un comentario',
        ),
      );
      expect(lines, [
        '  - id: caja',
        '    environment: caja',
        "    arguments: '{Título}'",
        '    definition: |',
        r'      \newenvironment{caja}[1]{\par\textbf{#1}}{\par}',
        '',
        '      % fin',
        '    sample: |',
        '      # no es un comentario',
      ]);
    });

    test('comillas solo donde hacen falta', () {
      expect(quoteSnippetScalar('Solo diapositivas'), 'Solo diapositivas');
      expect(quoteSnippetScalar('Teoría'), 'Teoría');
      expect(quoteSnippetScalar('[Título]'), "'[Título]'");
      expect(quoteSnippetScalar('no'), "'no'");
      expect(quoteSnippetScalar("l'hora"), "'l''hora'");
      expect(quoteSnippetScalar('Nota: importante'), "'Nota: importante'");
    });
  });

  group('envolver con argumentos', () {
    const rojo = TexWrapper(
      id: 'rojo',
      label: 'En rojo',
      group: TexWrapGroup.custom,
      macro: 'textcolor',
      arguments: '{red}',
    );
    const frame = TexWrapper(
      id: 'diapo',
      label: 'Diapositiva con título',
      group: TexWrapGroup.custom,
      environment: 'frame',
      arguments: '{Título}',
      block: true,
    );

    test('una orden con argumentos se escribe y se quita', () {
      const text = 'Esto es importante.';
      final wrapped = toggleWrap(text, 8, 18, rojo);
      expect(wrapped.text, r'Esto es \textcolor{red}{importante}.');
      final undone = toggleWrap(wrapped.text, wrapped.start, wrapped.end, rojo);
      expect(undone.text, text);
    });

    test('otro color no es este snippet', () {
      const text = r'Esto es \textcolor{blue}{importante}.';
      expect(wrappersAt(text, 28, among: const [rojo]), isEmpty);
    });

    test('un entorno con argumentos de llave los salta al quitarlo', () {
      const text = 'Una frase.';
      final wrapped = toggleWrap(text, 0, text.length, frame);
      expect(wrapped.text, '\\begin{frame}{Título}\nUna frase.\n\\end{frame}');
      final undone = toggleWrap(
        wrapped.text,
        wrapped.start,
        wrapped.end,
        frame,
      );
      expect(undone.text, text);
    });
  });

  group('el título en varios idiomas', () {
    test('con un idioma, el texto tal cual', () {
      expect(translatedLatex({'es': 'Resumen'}), 'Resumen');
      expect(translatedLatex({'es': 'Resumen', 'va': '  '}), 'Resumen');
      expect(translatedLatex({'es': ''}), '');
    });

    test('con varios, un DidactaTranslated en su orden', () {
      expect(
        translatedLatex({'va': 'Resum', 'es': 'Resumen', 'en': 'Summary'}),
        r'\DidactaTranslated{va=Resum, es=Resumen, en=Summary}',
      );
    });

    test('una coma o un igual van entre llaves, y se leen sin ellas', () {
      final latex = translatedLatex({'es': 'Uno, dos', 'en': 'a=b'});
      expect(latex, r'\DidactaTranslated{es={Uno, dos}, en={a=b}}');
      expect(parseTranslated(latex), {'es': 'Uno, dos', 'en': 'a=b'});
    });

    test('lo que no es un DidactaTranslated entero no se lee', () {
      expect(parseTranslated('Resumen'), isNull);
      expect(parseTranslated(r'\DidactaTranslated{es=Resumen'), isNull);
      expect(parseTranslated(r'\DidactaTranslated{Resumen}'), isNull);
    });

    test('una caja se lee de vuelta, con un título o con varios', () {
      final plain = TheoremBox.parse(
        r'\DidactaNewTheorem{resumen}{Resumen}{didactaThm}',
      )!;
      expect(plain.environment, 'resumen');
      expect(plain.titles, {'': 'Resumen'});
      expect(plain.colour, 'didactaThm');

      const box = TheoremBox(
        environment: 'resumen',
        titles: {'es': 'Resumen', 'va': 'Resum'},
        colour: 'didactaRem',
      );
      expect(
        box.definition,
        r'\DidactaNewTheorem{resumen}'
        r'{\DidactaTranslated{es=Resumen, va=Resum}}{didactaRem}',
      );
      final back = TheoremBox.parse(box.definition)!;
      expect(back.titles, box.titles);
      expect(back.colour, 'didactaRem');
    });

    test('un título con LaTeX dentro no es una caja del formulario', () {
      expect(
        TheoremBox.parse(r'\DidactaNewTheorem{x}{\textit{X}}{didactaThm}'),
        isNull,
      );
      expect(
        TheoremBox.parse(
          '\\DidactaNewTheorem{x}{X}{didactaThm}\n\\newcommand{\\y}{}',
        ),
        isNull,
      );
    });
  });
}
