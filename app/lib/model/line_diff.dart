/// A line diff, for showing what a save is about to change.
///
/// The metadata editor edits `unit.yaml` surgically -- one line per field,
/// everything else untouched. That is a promise, and a promise about someone
/// else's file is worth showing rather than asserting: the commit dialog
/// displays the changed lines, so an author can see that the comment block
/// and the key order are not in the diff before agreeing to the commit.
///
/// Longest common subsequence, on lines. The files here are tens of lines, so
/// the quadratic table is a few thousand cells -- Myers' algorithm would be
/// faster and harder to read, for no gain anyone could measure.
library;

enum ChangeKind { kept, added, removed }

class DiffLine {
  const DiffLine(this.kind, this.text, {this.oldLine, this.newLine});

  final ChangeKind kind;
  final String text;

  /// 1-based line numbers, null on the side where the line does not exist.
  final int? oldLine;
  final int? newLine;

  bool get isChange => kind != ChangeKind.kept;
}

/// The full diff of [before] and [after], line by line.
List<DiffLine> diffLines(String before, String after) {
  final a = before.split('\n');
  final b = after.split('\n');

  // lengths[i][j] = length of the LCS of a[i..] and b[j..]
  final lengths = List.generate(
    a.length + 1,
    (_) => List<int>.filled(b.length + 1, 0),
    growable: false,
  );
  for (var i = a.length - 1; i >= 0; i -= 1) {
    for (var j = b.length - 1; j >= 0; j -= 1) {
      lengths[i][j] = a[i] == b[j]
          ? lengths[i + 1][j + 1] + 1
          : (lengths[i + 1][j] >= lengths[i][j + 1]
              ? lengths[i + 1][j]
              : lengths[i][j + 1]);
    }
  }

  final result = <DiffLine>[];
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      result.add(DiffLine(ChangeKind.kept, a[i], oldLine: i + 1, newLine: j + 1));
      i += 1;
      j += 1;
    } else if (lengths[i + 1][j] >= lengths[i][j + 1]) {
      result.add(DiffLine(ChangeKind.removed, a[i], oldLine: i + 1));
      i += 1;
    } else {
      result.add(DiffLine(ChangeKind.added, b[j], newLine: j + 1));
      j += 1;
    }
  }
  while (i < a.length) {
    result.add(DiffLine(ChangeKind.removed, a[i], oldLine: i + 1));
    i += 1;
  }
  while (j < b.length) {
    result.add(DiffLine(ChangeKind.added, b[j], newLine: j + 1));
    j += 1;
  }
  return result;
}

/// The diff with only the changes and [context] lines around each one.
///
/// Unabridged, a two-line change to a forty-line file is thirty-eight lines
/// of noise around the part anyone is looking at.
List<DiffLine> diffHunks(String before, String after, {int context = 2}) {
  final all = diffLines(before, after);
  final keep = List<bool>.filled(all.length, false);
  for (var i = 0; i < all.length; i += 1) {
    if (!all[i].isChange) continue;
    final from = (i - context).clamp(0, all.length - 1);
    final to = (i + context).clamp(0, all.length - 1);
    for (var j = from; j <= to; j += 1) {
      keep[j] = true;
    }
  }
  return [
    for (var i = 0; i < all.length; i += 1)
      if (keep[i]) all[i],
  ];
}

/// How many lines the change touches. Zero means nothing to commit.
({int added, int removed}) diffSize(String before, String after) {
  var added = 0;
  var removed = 0;
  for (final line in diffLines(before, after)) {
    if (line.kind == ChangeKind.added) added += 1;
    if (line.kind == ChangeKind.removed) removed += 1;
  }
  return (added: added, removed: removed);
}
