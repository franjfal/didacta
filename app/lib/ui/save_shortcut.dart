/// ⌘S en macOS y Ctrl+S en los demás: guardar lo que se está editando.
///
/// No existía en ningún editor, y es el atajo que cualquiera prueba primero.
/// Hace lo mismo que el botón de guardar de esa pantalla --pide el mensaje y
/// enseña el diff--, así que no es un camino aparte que pueda hacer otra cosa.
library;

import 'package:flutter/widgets.dart';

import 'shortcuts.dart';

/// El atajo de guardar en este sistema. De la tabla de `shortcuts.dart`.
SingleActivator get saveActivator => activatorFor(AppShortcut.save);

/// Cómo se escribe el atajo, para los tooltips: «⌘S» o «Ctrl+S».
String get saveShortcutLabel => labelFor(AppShortcut.save);

/// Guarda con el atajo mientras el foco esté dentro de [child].
///
/// [onSave] null es «ahora no hay nada que guardar» --el botón está apagado
/// por lo mismo-- y el atajo no hace nada, en lugar de abrir un diálogo para
/// no guardar nada.
class SaveShortcut extends StatelessWidget {
  const SaveShortcut({super.key, required this.onSave, required this.child});

  final VoidCallback? onSave;
  final Widget child;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {saveActivator: () => onSave?.call()},
    child: child,
  );
}
