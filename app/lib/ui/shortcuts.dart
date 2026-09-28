/// Los atajos de teclado, en una sola tabla.
///
/// Casi todos existían solo en la barra de menú de macOS, y los tooltips
/// decían «⌘» también en Windows y Linux, donde esa tecla no existe. Aquí
/// están todos una vez: el menú de macOS los lee de aquí, el armazón los
/// atiende en los demás sistemas, los tooltips los escriben como toca en
/// cada uno y la hoja «Atajos de teclado» los enseña.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import '../l10n/tr.dart';

/// Lo que se puede hacer con el teclado desde cualquier sitio.
enum AppShortcut {
  palette('Buscar una orden, una lección o un curso', LogicalKeyboardKey.keyK),
  courses('Ir a Asignaturas', LogicalKeyboardKey.digit1),
  library('Ir a la biblioteca', LogicalKeyboardKey.digit2),
  translations('Ir a Traducción', LogicalKeyboardKey.digit3),
  settings('Abrir Ajustes', LogicalKeyboardKey.comma),
  back('Atrás', LogicalKeyboardKey.bracketLeft),
  forward('Adelante', LogicalKeyboardKey.bracketRight),
  save('Guardar lo que se está editando', LogicalKeyboardKey.keyS),
  search(
    'Buscar: en la biblioteca, en el texto que se edita o en el PDF',
    LogicalKeyboardKey.keyF,
  ),
  findNext(
    'Siguiente al buscar en el texto (con Mayús, la anterior)',
    LogicalKeyboardKey.keyG,
  ),
  refresh('Actualizar desde el disco y GitHub', LogicalKeyboardKey.keyR),
  pull('Traer los cambios de GitHub', LogicalKeyboardKey.keyP, shift: true),
  push('Enviar los cambios guardados', LogicalKeyboardKey.keyU, shift: true),
  biggerText('Texto más grande', LogicalKeyboardKey.equal),
  smallerText('Texto más pequeño', LogicalKeyboardKey.minus),
  normalText('Texto del tamaño normal', LogicalKeyboardKey.digit0),
  help('Ver estos atajos', LogicalKeyboardKey.slash);

  const AppShortcut(this._what, this.key, {this.shift = false});

  /// Qué hace, para la hoja de atajos, en el idioma de la interfaz.
  String get what => tr(_what);
  final String _what;
  final LogicalKeyboardKey key;
  final bool shift;
}

bool get _mac => defaultTargetPlatform == TargetPlatform.macOS;

/// El atajo en este sistema: con ⌘ en macOS y con Ctrl en los demás.
SingleActivator activatorFor(AppShortcut shortcut) => SingleActivator(
  shortcut.key,
  meta: _mac,
  control: !_mac,
  shift: shortcut.shift,
);

/// Otras teclas que hacen lo mismo que [shortcut], además de la suya.
///
/// Para el tamaño del texto: en un teclado español el «+» es una tecla
/// propia y no la del «=» con Mayús, así que ⌘+ tiene que valer con las dos;
/// y el teclado numérico, que es donde se buscan el «+» y el «−».
List<SingleActivator> alsoFor(AppShortcut shortcut) => [
  if (shortcut == AppShortcut.biggerText)
    SingleActivator(
      LogicalKeyboardKey.equal,
      meta: _mac,
      control: !_mac,
      shift: true,
    ),
  for (final key in switch (shortcut) {
    AppShortcut.biggerText => const [
      LogicalKeyboardKey.add,
      LogicalKeyboardKey.numpadAdd,
    ],
    AppShortcut.smallerText => const [LogicalKeyboardKey.numpadSubtract],
    AppShortcut.normalText => const [LogicalKeyboardKey.numpad0],
    _ => const <LogicalKeyboardKey>[],
  })
    SingleActivator(key, meta: _mac, control: !_mac),
];

/// Pulsar con ⌘ (con Ctrl fuera de macOS): en un PDF, ir a la lección de
/// donde sale lo pulsado.
String get sourceClickLabel => _mac ? tr('⌘+clic') : tr('Ctrl+clic');

/// Cómo se escribe: «⌘⇧P» en macOS, «Ctrl+Mayús+P» en los demás.
String labelFor(AppShortcut shortcut) {
  final key = switch (shortcut.key) {
    LogicalKeyboardKey.comma => ',',
    LogicalKeyboardKey.bracketLeft => '[',
    LogicalKeyboardKey.bracketRight => ']',
    LogicalKeyboardKey.slash => '/',
    LogicalKeyboardKey.equal => '+',
    LogicalKeyboardKey.minus => '−',
    _ => shortcut.key.keyLabel.toUpperCase(),
  };
  if (_mac) return '⌘${shortcut.shift ? '⇧' : ''}$key';
  return 'Ctrl+${shortcut.shift ? tr('Mayús+') : ''}$key';
}

/// La hoja con todos los atajos.
Future<void> showShortcuts(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    key: const Key('shortcuts-sheet'),
    title: Text(tr('Atajos de teclado')),
    // Con desplazamiento: son dieciséis filas, y con el texto agrandado para
    // el proyector no caben en una ventana normal.
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final shortcut in AppShortcut.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        shortcut.what,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.palette.panel,
                        border: Border.all(color: context.palette.rule),
                        borderRadius: BorderRadius.circular(Radii.control),
                      ),
                      child: Text(
                        labelFor(shortcut),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              tr(
                '{0} en un PDF abre la lección en la línea de '
                'donde sale lo pulsado.',
                [sourceClickLabel],
              ),
              key: const Key('shortcuts-source-click'),
              style: TextStyle(fontSize: 12, color: context.palette.muted),
            ),
            const SizedBox(height: 4),
            Text(
              _mac
                  ? tr('Y los de siempre al escribir: ⌘Z, ⌘C, ⌘V…')
                  : tr('Y los de siempre al escribir: Ctrl+Z, Ctrl+C, Ctrl+V…'),
              style: TextStyle(fontSize: 12, color: context.palette.muted),
            ),
          ],
        ),
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(tr('Cerrar')),
      ),
    ],
  ),
);
