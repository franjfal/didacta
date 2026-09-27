/// El diálogo que enseña el diff antes de guardar.
///
/// Compartido entre los dos sitios que escriben `year.yaml` --la composición
/// de un documento y el orden de los documentos del año-- porque son el mismo
/// gesto: se va a hacer un commit, y lo que hay que ver antes es qué líneas
/// cambian, no un «¿guardar?».
///
/// El mensaje viene propuesto y se puede cambiar. Proponerlo no es un adorno:
/// un historial en el que todo se llama «editar year.yaml» no se lee, y
/// nadie escribe un mensaje bueno en un diálogo si se lo dejas en blanco.
library;

import 'package:flutter/material.dart';

import '../model/line_diff.dart';
import '../model/word_diff.dart';
import 'diff_view.dart' show wordMarked;
import 'theme.dart';
import '../l10n/tr.dart';

class CommitDialog extends StatefulWidget {
  const CommitDialog({
    super.key,
    required this.before,
    required this.after,
    required this.suggested,
  });

  final String before;
  final String after;
  final String suggested;

  @override
  State<CommitDialog> createState() => CommitDialogState();
}

class CommitDialogState extends State<CommitDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.suggested,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Guardar la composición')),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                'Esto es lo que va a cambiar en year.yaml. Los demás '
                'documentos del curso no se tocan.',
              ),
              style: TextStyle(fontSize: 12.5, color: context.palette.muted),
            ),
            const SizedBox(height: 10),
            DiffBox(before: widget.before, after: widget.after),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(labelText: tr('Mensaje')),
              onSubmitted: (value) => Navigator.of(
                context,
              ).pop(value.trim().isEmpty ? widget.suggested : value.trim()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancelar')),
        ),
        FilledButton(
          key: const Key('composition-commit'),
          onPressed: () {
            final text = _controller.text.trim();
            Navigator.of(context).pop(text.isEmpty ? widget.suggested : text);
          },
          child: Text(tr('Guardar')),
        ),
      ],
    );
  }
}

/// Las líneas que cambian entre [before] y [after], con las de alrededor.
///
/// La misma caja en los dos sitios donde se enseña un cambio: antes de
/// guardarlo, cuando se quiere revisar, y después, en «Ver cambios».
class DiffBox extends StatelessWidget {
  const DiffBox({
    super.key,
    required this.before,
    required this.after,
    this.maxHeight = 260,
  });

  final String before;
  final String after;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final hunks = diffHunks(before, after);
    final pairs = pairChangedLines([
      for (final line in hunks)
        (
          removed: line.kind == ChangeKind.removed,
          added: line.kind == ChangeKind.added,
          text: line.text,
        ),
    ]);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        key: const Key('diff-box'),
        width: double.infinity,
        decoration: BoxDecoration(
          color: context.palette.panel,
          border: Border.all(color: context.palette.rule),
        ),
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < hunks.length; i += 1)
                    _DiffRow(line: hunks[i], pair: pairs[i]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({required this.line, this.pair});

  final DiffLine line;

  /// La línea con la que se compara, para marcar las palabras que cambiaron.
  final String? pair;

  @override
  Widget build(BuildContext context) {
    final (marker, colour) = switch (line.kind) {
      ChangeKind.added => ('+', context.palette.accentDark),
      ChangeKind.removed => ('−', context.palette.teacher),
      ChangeKind.kept => (' ', context.palette.muted),
    };
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$marker '),
          wordMarked(
            line.text,
            pair,
            line.kind == ChangeKind.added
                ? context.palette.diffAddedWord
                : context.palette.diffRemovedWord,
          ),
        ],
      ),
      style: TextStyle(
        fontSize: 11.5,
        fontFamily: 'monospace',
        color: line.isChange ? colour : context.palette.muted,
        fontWeight: line.isChange ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }
}
