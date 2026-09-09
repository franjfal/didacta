/// Tests for the surgical YAML editor.
///
/// The claim being tested is narrow and important: **an edit changes the line
/// it was asked about and nothing else.** Everything else in these files --
/// the migration provenance, the TODO markers that are the work list for two
/// thousand units, the key order someone chose -- has to come out the other
/// side byte for byte.
///
/// So most of these tests compare whole documents rather than parsed values.
/// A test that parses the result and checks a field would pass while the
/// comments were being deleted.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/yaml_patch.dart';

/// A real migrated `unit.yaml`, comments and all.
const String migrated = '''
# Adfgvx
#
# Migrated from:
#   00classnotes/908Criptography/01Handouts/02-cipher_cards/00CAST-ADFGVX.tex
#
# The fields marked TODO are the ones the legacy material did not record.
# Filling them in is what makes this unit safe to reuse elsewhere.

id: criptography.cipher-cards.adfgvx
kind: handout

title:
  # TODO: no title could be extracted from the source
  es: Adfgvx

category: criptography
topic: cipher-cards
tags: [cipher-cards]

reference: es

# Only languages that exist are listed; absence is what `missing` means.
languages:
  es: {status: draft}

# TODO: what this unit assumes, and what a student can do after it.
prerequisites: []
objectives: []

duration_minutes: null
difficulty: null
''';

void main() {
  group('reading', () {
    test('finds scalars, nested and not', () {
      final patch = YamlPatch(migrated);
      expect(patch.scalar(['kind']), 'handout');
      expect(patch.scalar(['title', 'es']), 'Adfgvx');
      expect(patch.scalar(['category']), 'criptography');
      // `null` is absent, not the string "null".
      expect(patch.scalar(['difficulty']), isNull);
      expect(patch.scalar(['duration_minutes']), isNull);
      expect(patch.scalar(['no', 'such', 'key']), isNull);
    });

    test('reads a flow list and an empty one', () {
      final patch = YamlPatch(migrated);
      expect(patch.list(['tags']), ['cipher-cards']);
      expect(patch.list(['objectives']), isEmpty);
    });

    test('reads a block list', () {
      final patch = YamlPatch('''
objectives:
  - Reconocer una norma
  - 'Distinguir: norma de métrica'
''');
      expect(patch.list(['objectives']),
          ['Reconocer una norma', 'Distinguir: norma de métrica']);
    });

    test('lists the keys of a mapping without descending into it', () {
      final patch = YamlPatch('''
languages:
  es: {status: source}
  va:
    status: draft
    note: a medias
  en: {status: draft}
''');
      // `note` is a grandchild and must not appear.
      expect(patch.keysUnder(['languages']), ['es', 'va', 'en']);
    });
  });

  group('a scalar edit', () {
    test('changes its line and leaves the file alone', () {
      final patch = YamlPatch(migrated)..setScalar(['kind'], 'theory');
      expect(patch.result, migrated.replaceFirst('kind: handout', 'kind: theory'));
    });

    test('keeps the TODO comment sitting inside the title block', () {
      final patch = YamlPatch(migrated)
        ..setScalar(['title', 'es'], 'ADFGVX, la cifra alemana');
      // The comment above `es:` is the whole reason this class exists.
      expect(patch.result, contains('# TODO: no title could be extracted'));
      expect(patch.result, contains('  es: ADFGVX, la cifra alemana'));
      expect(patch.result, contains('# Migrated from:'));
    });

    test('adds a language to the title block, indented like its siblings', () {
      final patch = YamlPatch(migrated)
        ..setScalar(['title', 'va'], 'ADFGVX, la xifra alemanya');
      expect(
        patch.result,
        contains('  es: Adfgvx\n  va: ADFGVX, la xifra alemanya'),
      );
    });

    test('adds a top-level key at the end, not in the trailing blank line', () {
      final patch = YamlPatch(migrated)..setScalar(['marks'], '10');
      expect(patch.result, endsWith("marks: '10'\n"));
    });

    test('writes null rather than deleting the key', () {
      // The key existing and being null says "we know this is unanswered";
      // deleting it says nothing at all.
      final patch = YamlPatch(migrated)..setScalar(['difficulty'], null);
      expect(patch.result, contains('difficulty: null'));
    });

    test('keeps a trailing comment on the line it edits', () {
      final patch = YamlPatch('kind: handout  # puesto a mano\n')
        ..setScalar(['kind'], 'theory');
      expect(patch.result, 'kind: theory # puesto a mano\n');
    });
  });

  group('quoting', () {
    test('quotes what YAML would read as something else', () {
      final patch = YamlPatch('a: 1\nb: 1\nc: 1\nd: 1\ne: 1\n')
        ..setScalar(['a'], '2025')
        ..setScalar(['b'], 'true')
        ..setScalar(['c'], 'null')
        ..setScalar(['d'], '- no es una lista')
        ..setScalar(['e'], 'Tema: introducción');
      expect(patch.result, '''
a: '2025'
b: 'true'
c: 'null'
d: '- no es una lista'
e: 'Tema: introducción'
''');
    });

    test('leaves LaTeX intact, backslashes included', () {
      // Single quotes, not double: in double quotes YAML eats the backslash,
      // and a title with maths in it is the normal case here.
      final patch = YamlPatch('title:\n  es: x\n')
        ..setScalar(['title', 'es'], r'Espacios $\ell^p$ y $L^p$');
      expect(patch.result, 'title:\n  es: Espacios \$\\ell^p\$ y \$L^p\$\n');
      expect(YamlPatch(patch.result).scalar(['title', 'es']),
          r'Espacios $\ell^p$ y $L^p$');
    });

    test('leaves an apostrophe inside a value unquoted, as YAML allows', () {
      // `a: L'Hôpital` is a valid plain scalar, and quoting it would add
      // noise to a diff for nothing.
      final patch = YamlPatch('a: x\n')..setScalar(['a'], "L'Hôpital");
      expect(patch.result, "a: L'Hôpital\n");
      expect(YamlPatch(patch.result).scalar(['a']), "L'Hôpital");
    });

    test('doubles the quotes when a value has to be quoted', () {
      // A leading quote does force quoting, and then every quote inside has
      // to be doubled or the value ends early.
      final patch = YamlPatch('a: x\n')
        ..setScalar(['a'], "'ojo' es una palabra");
      expect(patch.result, "a: '''ojo'' es una palabra'\n");
      expect(YamlPatch(patch.result).scalar(['a']), "'ojo' es una palabra");
    });

    test('a hash inside a value is not a comment', () {
      final patch = YamlPatch('a: x\n')..setScalar(['a'], 'C# para músicos');
      expect(YamlPatch(patch.result).scalar(['a']), 'C# para músicos');
    });

    test('does not quote what does not need it', () {
      // Gratuitous quoting makes a diff of a hand-written file unreadable.
      final patch = YamlPatch('a: x\n')..setScalar(['a'], 'Espacios normados');
      expect(patch.result, 'a: Espacios normados\n');
    });
  });

  group('numbers', () {
    test('a numeric field is written unquoted', () {
      // `duration_minutes: '50'` is a string, and the schema wants a number.
      final patch = YamlPatch(migrated)..setNumber(['duration_minutes'], 50);
      expect(patch.result, contains('duration_minutes: 50\n'));
    });

    test('null clears it without removing the key', () {
      final patch = YamlPatch('duration_minutes: 50\n')
        ..setNumber(['duration_minutes'], null);
      expect(patch.result, 'duration_minutes: null\n');
    });

    test('but a tag that looks like a year stays a string', () {
      // The distinction is the field, not the text: which is exactly why
      // this is a separate method rather than a guess.
      final patch = YamlPatch(migrated)..setFlowList(['tags'], ['2025']);
      expect(patch.result, contains("tags: ['2025']"));
    });
  });

  group('lists', () {
    test('replaces a flow list in place', () {
      final patch = YamlPatch(migrated)
        ..setFlowList(['tags'], ['cifra', 'histórica', 'adfgvx']);
      expect(patch.result,
          contains('tags: [cifra, histórica, adfgvx]'));
      expect(patch.result, contains('# Migrated from:'));
    });

    test('turns an empty block list into items', () {
      final patch = YamlPatch(migrated)..setBlockList(
        ['objectives'],
        ['Cifrar un mensaje con ADFGVX', 'Explicar por qué se rompió'],
      );
      expect(patch.result, contains('''
objectives:
  - Cifrar un mensaje con ADFGVX
  - Explicar por qué se rompió
'''));
      // And the TODO above it, which now applies to prerequisites only, stays.
      expect(patch.result, contains('# TODO: what this unit assumes'));
    });

    test('emptying a block list writes [] rather than nothing', () {
      final patch = YamlPatch('''
objectives:
  - uno
  - dos

difficulty: null
''')
        ..setBlockList(['objectives'], []);
      expect(patch.result, '''
objectives: []

difficulty: null
''');
    });

    test('replacing a block list does not leave the old items behind', () {
      final patch = YamlPatch('''
prerequisites:
  - analysis/normed/definition
  - analysis/normed/banach
objectives: []
''')
        ..setBlockList(['prerequisites'], ['analysis/metric/definition']);
      expect(patch.result, '''
prerequisites:
  - analysis/metric/definition
objectives: []
''');
    });

    test('a flow list replacing a block list drops the block', () {
      final patch = YamlPatch('''
tags:
  - uno
  - dos
reference: es
''')
        ..setFlowList(['tags'], ['tres']);
      expect(patch.result, '''
tags: [tres]
reference: es
''');
    });
  });

  group('flow maps', () {
    test('changes a language status without touching the others', () {
      final patch = YamlPatch('''
languages:
  es: {status: source}
  va: {status: draft}
''')
        ..setInFlowMap(['languages', 'va'], 'status', 'reviewed');
      expect(patch.result, '''
languages:
  es: {status: source}
  va: {status: reviewed}
''');
    });

    test('adds a language to the mapping', () {
      final patch = YamlPatch(migrated)
        ..setInFlowMap(['languages', 'va'], 'status', 'draft');
      expect(patch.result, contains('  es: {status: draft}\n  va: {status: draft}'));
      expect(patch.result, contains('# Only languages that exist are listed'));
    });

    test('works when the mapping is written as a block instead', () {
      // Both forms appear in the repository, and an editor that only handles
      // one of them corrupts the other.
      final patch = YamlPatch('''
languages:
  es:
    status: source
''')
        ..setInFlowMap(['languages', 'es'], 'status', 'reviewed');
      expect(patch.result, '''
languages:
  es:
    status: reviewed
''');
    });

    test('refuses a shape it does not understand rather than guessing', () {
      final patch = YamlPatch('languages: es\n');
      expect(
        () => patch.setInFlowMap(['languages'], 'status', 'draft'),
        throwsA(isA<YamlPatchException>()),
      );
    });
  });

  group('removal', () {
    test('takes the key and its block with it', () {
      final patch = YamlPatch('''
id: a
prerequisites:
  - uno
  - dos
objectives: []
''')
        ..remove(['prerequisites']);
      expect(patch.result, '''
id: a
objectives: []
''');
    });
  });

  group('refusals', () {
    test('a scalar cannot be given children', () {
      final patch = YamlPatch('kind: handout\n');
      expect(
        () => patch.setScalar(['kind', 'es'], 'x'),
        throwsA(isA<YamlPatchException>()),
      );
    });

    test('a missing parent is reported, not invented', () {
      final patch = YamlPatch('id: a\n');
      expect(
        () => patch.setScalar(['title', 'es'], 'x'),
        throwsA(isA<YamlPatchException>()),
      );
    });
  });

  group('a whole edit session', () {
    test('every field the interface offers, and the comments survive', () {
      final patch = YamlPatch(migrated)
        ..setScalar(['title', 'es'], 'ADFGVX')
        ..setScalar(['title', 'va'], 'ADFGVX')
        ..setScalar(['kind'], 'theory')
        ..setScalar(['topic'], 'cifras-de-campo')
        ..setFlowList(['tags'], ['cifra', 'adfgvx'])
        ..setBlockList(['objectives'], ['Cifrar y descifrar'])
        ..setBlockList(['prerequisites'], ['criptography/basics/intro'])
        ..setNumber(['duration_minutes'], 50)
        ..setScalar(['difficulty'], 'medium')
        ..setInFlowMap(['languages', 'es'], 'status', 'reviewed');

      final result = patch.result;
      expect(result, contains('# Adfgvx'));
      expect(result, contains('#   00classnotes/908Criptography'));
      expect(result, contains('# TODO: no title could be extracted'));
      expect(result, contains('# Only languages that exist are listed'));
      expect(result, contains('id: criptography.cipher-cards.adfgvx'));

      // And it reads back as what was written.
      final reread = YamlPatch(result);
      expect(reread.scalar(['kind']), 'theory');
      expect(reread.scalar(['title', 'va']), 'ADFGVX');
      expect(reread.list(['tags']), ['cifra', 'adfgvx']);
      expect(reread.list(['objectives']), ['Cifrar y descifrar']);
      expect(reread.scalar(['duration_minutes']), '50');
    });
  });
}
