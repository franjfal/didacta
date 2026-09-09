/// Tests for reading and rewriting a `year.yaml` composition.
///
/// The interesting case is not the tidy one. Nine hundred entries across the
/// repository are commented out -- material that exists and is deliberately
/// not being taught -- and switching one back on is a normal edit. So these
/// tests are mostly about what must survive a reorder: the disabled entries,
/// the `# nota:` lines that explain a document, the other documents in the
/// file, and everything above and below the block.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/composition_file.dart';

/// A `year.yaml` in the shape the migrator writes them.
const String yearYaml = '''
# Análisis Matemático I F-M -- 2021-2022
#
# Selection, order and structure. No content: every entry below is a reference
# into content/ or problems/.
#
# Migrated from  2021-2022/AN I - FM/00Info

course: an-i-fm
year: 2021-2022
group: Grupo A
language: es

documents:
  - id: faq
    kind: handout
    title:
      es: FAQ
      # TODO: va
    # Migrated from  2021-2022/AN I - FM/00Info/FAQ/Preguntas frecuentes.tex
    # nota: el título sale del nombre de la carpeta
    structure:
      - unit: faq/general/cal00-1tutorias
      # - unit: faq/general/cal00-1tutorias-virtuales
      - unit: faq/general/cal01-ver-calificaciones

  - id: tema-1
    kind: theory
    title:
      es: Tema 1
    structure:
      - section: Números reales
      - unit: analysis/reals/axioms
      - subsection: Supremo e ínfimo
      - unit: analysis/reals/supremum
      # - unit: analysis/reals/dedekind
      - problem: analysis/reals/exercises

  - id: notacion
    kind: handout
    title:
      es: Notación
    # nota: no importa ninguna unidad migrada
    structure:
      # - unit: analysis/sets/definition
''';

void main() {
  group('reading', () {
    test('lists the documents in the order the file has them', () {
      expect(
        CompositionFile(yearYaml).documentIds(),
        ['faq', 'tema-1', 'notacion'],
      );
    });

    test('reads an enabled and a disabled entry side by side', () {
      final block = CompositionFile(yearYaml).blockFor('faq')!;
      expect(block.entries.map((e) => e.value), [
        'faq/general/cal00-1tutorias',
        'faq/general/cal00-1tutorias-virtuales',
        'faq/general/cal01-ver-calificaciones',
      ]);
      expect(block.entries.map((e) => e.enabled), [true, false, true]);
    });

    test('reads all four kinds of entry', () {
      final block = CompositionFile(yearYaml).blockFor('tema-1')!;
      expect(block.entries.map((e) => e.kind), [
        EntryKind.section,
        EntryKind.unit,
        EntryKind.subsection,
        EntryKind.unit,
        EntryKind.unit,
        EntryKind.problem,
      ]);
      // A heading carries its text, not a path.
      expect(block.entries.first.value, 'Números reales');
      expect(block.entries.first.isReference, isFalse);
      expect(block.entries[1].isReference, isTrue);
    });

    test('a composition of nothing but a disabled entry is not empty', () {
      // This is what a document the migration could not fill looks like, and
      // treating it as empty would delete the one clue it has.
      final block = CompositionFile(yearYaml).blockFor('notacion')!;
      expect(block.entries, hasLength(1));
      expect(block.entries.single.enabled, isFalse);
      expect(block.entries.single.value, 'analysis/sets/definition');
    });

    test('an unknown document is null, not an error', () {
      expect(CompositionFile(yearYaml).blockFor('no-existe'), isNull);
    });

    test('keeps a note above the entry it explains', () {
      final block = CompositionFile('''
documents:
  - id: a
    structure:
      # nota: esta va primero por el calendario
      - unit: x/y/z
      - unit: x/y/w
''').blockFor('a')!;
      expect(block.entries.first.notes, ['# nota: esta va primero por el calendario']);
      expect(block.entries.last.notes, isEmpty);
    });

    test('keeps a comment on the entry line', () {
      final block = CompositionFile('''
documents:
  - id: a
    structure:
      - unit: x/y/z  # ojo, se da en la primera semana
''').blockFor('a')!;
      expect(block.entries.single.value, 'x/y/z');
      expect(block.entries.single.trailingComment,
          '# ojo, se da en la primera semana');
    });

    test('refuses an inline composition rather than rewriting it', () {
      expect(
        () => CompositionFile('''
documents:
  - id: a
    structure: [x, y]
''').blockFor('a'),
        throwsA(isA<CompositionException>()),
      );
    });
  });

  group('a heading with a title per language', () {
    // The shape 28 of the 30 real year.yaml files use, and the one that made
    // the first version of this parser refuse them all.
    const localised = '''
documents:
  - id: logica
    structure:
      - unit: history/intro/origen
      - section:
          es: "?`Qué es la matemática?"
          # TODO: va
          # TODO: en
      - unit: logica/que-son/que-son-las-matematicas
      - subsection:
          es: Los axiomas
          va: Els axiomes
          # TODO: en
''';

    test('reads its languages, and what to show for one it lacks', () {
      final entries = CompositionFile(localised).blockFor('logica')!.entries;
      final section = entries[1];
      expect(section.kind, EntryKind.section);
      expect(section.isLocalised, isTrue);
      expect(section.titles, {'es': '?`Qué es la matemática?'});
      expect(section.label('es'), '?`Qué es la matemática?');
      // No Valencian title, so the Spanish one is shown rather than nothing.
      expect(section.label('va'), '?`Qué es la matemática?');

      expect(entries[3].titles, {'es': 'Los axiomas', 'va': 'Els axiomes'});
      expect(entries[3].label('va'), 'Els axiomes');
    });

    test('round-trips untouched, TODO markers included', () {
      final file = CompositionFile(localised);
      file.setStructure('logica', file.blockFor('logica')!.entries);
      expect(file.text, localised);
    });

    test('reordering carries the whole title block with the heading', () {
      final file = CompositionFile(localised);
      final entries = file.blockFor('logica')!.entries;
      file.setStructure('logica', [entries[1], entries[0], ...entries.skip(2)]);
      expect(file.text, contains('''
      - section:
          es: "?`Qué es la matemática?"
          # TODO: va
          # TODO: en
      - unit: history/intro/origen
'''));
    });

    test('translating one language leaves the other markers alone', () {
      final file = CompositionFile(localised);
      final entries = file.blockFor('logica')!.entries;
      file.setStructure('logica', [
        for (final entry in entries)
          entry.kind == EntryKind.section
              ? entry.withTitle('va', 'Què és la matemàtica?')
              : entry,
      ]);
      expect(file.text, contains('''
      - section:
          es: "?`Qué es la matemática?"
          va: Què és la matemàtica?
          # TODO: en
'''));
    });

    test('changing a language it already has rewrites that line only', () {
      final file = CompositionFile(localised);
      final entries = file.blockFor('logica')!.entries;
      file.setStructure('logica', [
        for (final entry in entries)
          entry.kind == EntryKind.subsection
              ? entry.withTitle('va', 'Els postulats')
              : entry,
      ]);
      expect(file.text, contains('''
      - subsection:
          es: Los axiomas
          va: Els postulats
          # TODO: en
'''));
    });

    test('a disabled heading with a title block comments every line', () {
      final file = CompositionFile(localised);
      final entries = file.blockFor('logica')!.entries;
      file.setStructure('logica', [
        for (final entry in entries)
          entry.kind == EntryKind.section
              ? entry.copyWith(enabled: false)
              : entry,
      ]);
      // Every line of it, or the inner lines become siblings of the next
      // entry and the file stops parsing.
      expect(file.text, contains('''
      # - section:
          # es: "?`Qué es la matemática?"
          # # TODO: va
          # # TODO: en
'''));
      // And it comes back as one disabled entry.
      final reread = CompositionFile(file.text).blockFor('logica')!;
      expect(reread.entries[1].enabled, isFalse);
      expect(reread.entries[1].kind, EntryKind.section);
      expect(reread.entries[1].titles, {'es': '?`Qué es la matemática?'});

      // And writing it again is stable: a second pass must not add a second
      // layer of `# `, or a toggle repeated three times buries the entry.
      final again = CompositionFile(file.text);
      again.setStructure('logica', again.blockFor('logica')!.entries);
      expect(again.text, file.text);
    });
  });

  group('writing', () {
    test('an untouched round trip changes nothing', () {
      // The strongest form of "it does not damage the file".
      final file = CompositionFile(yearYaml);
      for (final id in file.documentIds()) {
        file.setStructure(id, file.blockFor(id)!.entries);
      }
      expect(file.text, yearYaml);
    });

    test('a reorder moves the entries and nothing else', () {
      final file = CompositionFile(yearYaml);
      final entries = file.blockFor('faq')!.entries;
      file.setStructure('faq', entries.reversed.toList());

      expect(file.text, contains('''
    structure:
      - unit: faq/general/cal01-ver-calificaciones
      # - unit: faq/general/cal00-1tutorias-virtuales
      - unit: faq/general/cal00-1tutorias
'''));
      // The other documents, the header and the fields are untouched.
      expect(file.text, contains('# Migrated from  2021-2022/AN I - FM/00Info'));
      expect(file.text, contains('      # TODO: va'));
      expect(file.text, contains('  - id: tema-1'));
      expect(file.text, contains('      - subsection: Supremo e ínfimo'));
    });

    test('switching a disabled entry on is a one-line change', () {
      // The most common edit there is after a migration.
      final file = CompositionFile(yearYaml);
      final entries = [
        for (final entry in file.blockFor('faq')!.entries)
          entry.value.endsWith('virtuales')
              ? entry.copyWith(enabled: true)
              : entry,
      ];
      file.setStructure('faq', entries);
      expect(
        file.text,
        yearYaml.replaceFirst(
          '      # - unit: faq/general/cal00-1tutorias-virtuales',
          '      - unit: faq/general/cal00-1tutorias-virtuales',
        ),
      );
    });

    test('switching one off keeps it in place, commented', () {
      final file = CompositionFile(yearYaml);
      final entries = [
        for (final entry in file.blockFor('tema-1')!.entries)
          entry.value == 'analysis/reals/supremum'
              ? entry.copyWith(enabled: false)
              : entry,
      ];
      file.setStructure('tema-1', entries);
      expect(file.text, contains('''
      - subsection: Supremo e ínfimo
      # - unit: analysis/reals/supremum
      # - unit: analysis/reals/dedekind
'''));
    });

    test('a note travels with the entry it belongs to', () {
      final file = CompositionFile('''
documents:
  - id: a
    structure:
      - unit: x/y/primera
      # nota: esta depende de la anterior
      - unit: x/y/segunda
''');
      final entries = file.blockFor('a')!.entries.reversed.toList();
      file.setStructure('a', entries);
      expect(file.text, '''
documents:
  - id: a
    structure:
      # nota: esta depende de la anterior
      - unit: x/y/segunda
      - unit: x/y/primera
''');
    });

    test('adding an entry writes it at the block indentation', () {
      final file = CompositionFile(yearYaml);
      final entries = [
        ...file.blockFor('tema-1')!.entries,
        const StructureEntry(kind: EntryKind.unit, value: 'analysis/reals/new'),
      ];
      file.setStructure('tema-1', entries);
      expect(file.text, contains('      - unit: analysis/reals/new'));
    });

    test('emptying a composition writes [] rather than a bare key', () {
      // A bare `structure:` reads as null, which is a different thing.
      final file = CompositionFile(yearYaml)..setStructure('faq', []);
      expect(file.text, contains('    structure: []'));
      expect(file.text, contains('  - id: tema-1'));
    });

    test('a heading with a colon in it comes back quoted', () {
      final file = CompositionFile(yearYaml);
      file.setStructure('tema-1', [
        const StructureEntry(
          kind: EntryKind.section,
          value: 'Tema 1: los reales',
        ),
      ]);
      expect(file.text, contains("- section: 'Tema 1: los reales'"));
      // And reads back as what was written.
      expect(
        CompositionFile(file.text).blockFor('tema-1')!.entries.single.value,
        'Tema 1: los reales',
      );
    });

    test('a document that does not exist is refused', () {
      expect(
        () => CompositionFile(yearYaml).setStructure('no-existe', []),
        throwsA(isA<CompositionException>()),
      );
    });

    test('editing one document does not disturb the next one', () {
      final file = CompositionFile(yearYaml);
      final before = CompositionFile(yearYaml).blockFor('notacion')!;
      file.setStructure('tema-1', []);
      final after = file.blockFor('notacion')!;
      expect(after.entries.map((e) => e.value),
          before.entries.map((e) => e.value));
      expect(after.entries.single.enabled, isFalse);
    });
  });
}
