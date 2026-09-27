/// Preguntar antes de dejar atrás lo que no se ha guardado.
library;

import 'package:flutter/material.dart';

import 'theme.dart';
import '../l10n/tr.dart';

/// True si se puede seguir: no había nada, o se ha dicho que se deje.
///
/// «Seguir editando» es lo que viene marcado: salir sin guardar es lo que se
/// hace a propósito, y un Intro por reflejo no puede tirar un párrafo.
Future<bool> confirmLeaving(
  BuildContext context,
  List<String> what, {
  String? leave,
}) async {
  if (what.isEmpty) return true;
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Hay cambios sin guardar')),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in what)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('· $item', style: const TextStyle(fontSize: 13)),
              ),
            const SizedBox(height: 8),
            Text(
              tr(
                'Si sales ahora, se pierden. «Seguir editando» te deja donde '
                'estabas, con todo lo escrito, para guardarlo.',
              ),
              style: TextStyle(fontSize: 12.5, color: context.palette.muted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('unsaved-leave'),
          style: TextButton.styleFrom(foregroundColor: context.palette.teacher),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(leave ?? tr('Salir sin guardar')),
        ),
        FilledButton(
          key: const Key('unsaved-stay'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(tr('Seguir editando')),
        ),
      ],
    ),
  );
  return answer ?? false;
}
