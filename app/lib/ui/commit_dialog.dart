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
import 'theme.dart';

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
    final hunks = diffHunks(widget.before, widget.after);
    return AlertDialog(
      title: const Text('Guardar la composición'),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Esto es lo que va a cambiar en year.yaml. Los demás '
              'documentos del curso no se tocan.',
              style: TextStyle(fontSize: 12.5, color: didactaMuted),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: didactaPanel,
                  border: Border.all(color: didactaRule),
                ),
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final line in hunks) _DiffRow(line: line),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Mensaje'),
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
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('composition-commit'),
          onPressed: () {
            final text = _controller.text.trim();
            Navigator.of(context).pop(text.isEmpty ? widget.suggested : text);
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({required this.line});

  final DiffLine line;

  @override
  Widget build(BuildContext context) {
    final (marker, colour) = switch (line.kind) {
      ChangeKind.added => ('+', didactaAccentDark),
      ChangeKind.removed => ('−', didactaTeacher),
      ChangeKind.kept => (' ', didactaMuted),
    };
    return Text(
      '$marker ${line.text}',
      style: TextStyle(
        fontSize: 11.5,
        fontFamily: 'monospace',
        color: line.isChange ? colour : didactaMuted,
        fontWeight: line.isChange ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }
}
