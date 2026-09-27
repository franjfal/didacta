/// Guardar con el mensaje propuesto, y ver después lo que cambió.
///
/// Cada guardado abría un diálogo con el mensaje y, a veces, el diff. Para
/// corregir una errata eso es un diálogo que se acepta sin leer treinta veces
/// al día, y un diálogo que se acepta sin leer no revisa nada. Así que, de
/// salida, se guarda con el mensaje que propone Didacta --que dice qué se
/// cambió y dónde-- y lo que cambió queda a un clic, en «Ver cambios» del
/// aviso y en el historial. Quien sí quiere mirarlo cada vez antes lo
/// enciende en Ajustes → Guardar y sincronizar.
library;

import 'package:flutter/material.dart';

import '../state/session.dart';
import 'commit_dialog.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// El mensaje con el que se guarda: [suggested], o el que se escriba en
/// [dialog] si se revisa cada cambio. Null si se cancela.
Future<String?> askSaveMessage(
  BuildContext context,
  Session session, {
  required String suggested,
  required WidgetBuilder dialog,
}) async {
  if (!session.reviewBeforeSave) return suggested;
  return showDialog<String>(context: context, builder: dialog);
}

/// El aviso de que se guardó, con el mensaje y «Ver cambios».
///
/// [navigator] se pide al llamar y no al pulsar: el aviso dura unos
/// segundos, y la pantalla que guardó puede haberse ido para entonces.
SnackBar savedNotice({
  required String notice,
  required String message,
  required String before,
  required String after,
  required String what,
  required NavigatorState navigator,

  /// Lo que se suele querer hacer justo después --«Compilar ahora»--, como un
  /// botón debajo del mensaje. La acción del aviso ya es «Ver cambios».
  ({String label, IconData icon, VoidCallback onPressed})? followUp,
}) => SnackBar(
  key: const Key('saved-notice'),
  duration: Duration(seconds: followUp == null ? 6 : 10),
  content: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(notice),
      const SizedBox(height: 2),
      // En cursiva y no entre comillas: el mensaje propuesto ya las lleva
      // para lo que nombra.
      Text(
        message,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
      ),
      if (followUp != null)
        Builder(
          builder: (context) {
            // Con el color de la acción del aviso, que está pensado para su
            // fondo: los del tema son para la página, y sobre el aviso --que
            // va invertido-- no se ven.
            final theme = Theme.of(context);
            final colour =
                theme.snackBarTheme.actionTextColor ??
                theme.colorScheme.inversePrimary;
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: OutlinedButton.icon(
                key: const Key('saved-follow-up'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colour,
                  side: BorderSide(color: colour.withValues(alpha: 0.6)),
                  visualDensity: VisualDensity.compact,
                ),
                icon: Icon(followUp.icon, size: 15),
                label: Text(followUp.label),
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  followUp.onPressed();
                },
              ),
            );
          },
        ),
    ],
  ),
  action: before == after
      ? null
      : SnackBarAction(
          key: const Key('saved-show-changes'),
          label: tr('Ver cambios'),
          onPressed: () => showDialog<void>(
            context: navigator.context,
            builder: (context) => SavedChangesDialog(
              before: before,
              after: after,
              what: what,
              message: message,
            ),
          ),
        ),
);

/// Lo que se acaba de guardar: el fichero, el mensaje y las líneas.
class SavedChangesDialog extends StatelessWidget {
  const SavedChangesDialog({
    super.key,
    required this.before,
    required this.after,
    required this.what,
    required this.message,
  });

  final String before;
  final String after;

  /// El fichero, como se lee en el historial.
  final String what;
  final String message;

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('saved-changes'),
    title: Text(tr('Lo que se ha guardado')),
    content: SizedBox(
      width: 600,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            what,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: context.palette.muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 10),
          DiffBox(before: before, after: after, maxHeight: 360),
          const SizedBox(height: 10),
          Text(
            tr(
              'Está en el historial: desde allí se puede ver otra vez o '
              'deshacer.',
            ),
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
        ],
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(tr('Cerrar')),
      ),
    ],
  );
}
