/// Tests for the line diff shown before a metadata commit.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/line_diff.dart';

String rendered(List<DiffLine> lines) => lines
    .map(
      (line) => switch (line.kind) {
        ChangeKind.kept => '  ${line.text}',
        ChangeKind.added => '+ ${line.text}',
        ChangeKind.removed => '- ${line.text}',
      },
    )
    .join('\n');

void main() {
  test('identical text has no changes', () {
    expect(diffSize('a\nb\n', 'a\nb\n'), (added: 0, removed: 0));
    expect(diffLines('a\nb', 'a\nb').every((l) => !l.isChange), isTrue);
  });

  test('one changed line is one removal and one addition', () {
    final size = diffSize('kind: handout\n', 'kind: theory\n');
    expect(size, (added: 1, removed: 1));
  });

  test('shows the change with its surroundings', () {
    // The claim the metadata editor makes -- that it touches one line -- is
    // exactly what this makes visible.
    const before = '''
# Adfgvx
#
# Migrated from: x.tex

id: a.b.c
kind: handout

title:
  # TODO: no title
  es: Adfgvx
''';
    final after = before.replaceFirst('kind: handout', 'kind: theory');
    expect(rendered(diffHunks(before, after, context: 1)), '''
  id: a.b.c
- kind: handout
+ kind: theory
  ''');
  });

  test('an insertion is an addition with no removal', () {
    final size = diffSize('a\nb\n', 'a\nnuevo\nb\n');
    expect(size, (added: 1, removed: 0));
  });

  test('numbers the lines on the side each one exists', () {
    final lines = diffLines('a\nb\n', 'a\nc\n');
    final removed = lines.firstWhere((l) => l.kind == ChangeKind.removed);
    final added = lines.firstWhere((l) => l.kind == ChangeKind.added);
    expect(removed.oldLine, 2);
    expect(removed.newLine, isNull);
    expect(added.newLine, 2);
    expect(added.oldLine, isNull);
  });

  test('a block list replacing an empty one reads as one line for three', () {
    const before = 'objectives: []\n';
    const after = 'objectives:\n  - uno\n  - dos\n';
    expect(diffSize(before, after), (added: 3, removed: 1));
  });

  test('hunks leave out what is far from any change', () {
    final before = List.generate(40, (i) => 'línea $i').join('\n');
    final after = before.replaceFirst('línea 20', 'línea veinte');
    final hunks = diffHunks(before, after, context: 2);
    // Five lines of context and change, not forty.
    expect(hunks, hasLength(6));
    expect(hunks.first.text, 'línea 18');
    expect(hunks.last.text, 'línea 22');
  });
}
