/// El menú del sistema, en escritorio.
///
/// En macOS una aplicación sin barra de menú se nota: los atajos no se
/// descubren, «¿qué puedo hacer aquí?» no tiene respuesta, y la barra de
/// arriba se queda con un menú vacío que parece un error. Así que las
/// acciones que ya existen en la interfaz salen también aquí, con sus atajos.
///
/// En web y en móvil esto no envuelve nada: no hay barra de menú del sistema
/// y `PlatformMenuBar` no tiene dónde dibujarse.
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import '../data/browser.dart';
import '../router.dart';
import '../state/appearance.dart';
import '../state/session.dart';
import 'problem.dart';
import 'command_palette.dart';
import 'shortcuts.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Envuelve [child] con el menú del sistema donde lo haya.
class PlatformMenus extends StatelessWidget {
  const PlatformMenus({
    super.key,
    required this.navigate,
    this.dialogContext,
    required this.child,
  });

  /// Cómo se va a una dirección: el `go` del router.
  ///
  /// Se pasa de fuera y no se busca con `GoRouter.of` porque este widget va
  /// en el `builder` de `MaterialApp.router`, y ese contexto está **por
  /// encima** del `Router`: go_router pone lo suyo más abajo, alrededor del
  /// Navigator, así que desde aquí no hay router que encontrar.
  final void Function(String route) navigate;

  /// Dónde abrir un diálogo --la hoja de atajos--: el contexto del Navigator,
  /// por lo mismo que [navigate].
  final BuildContext Function()? dialogContext;

  final Widget child;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    if (!supported) return child;
    return _MacMenus(
      navigate: navigate,
      dialogContext: dialogContext,
      child: child,
    );
  }
}

class _MacMenus extends StatelessWidget {
  const _MacMenus({
    required this.navigate,
    required this.dialogContext,
    required this.child,
  });

  final void Function(String route) navigate;
  final BuildContext Function()? dialogContext;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sessionOf(context).repoSync,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
    final session = watchSession(context);
    final clone = session.workspace.isNotEmpty;

    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: tr('Didacta'),
          menus: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: tr('Ajustes…'),
                  shortcut: activatorFor(AppShortcut.settings),
                  onSelected: () => navigate(Routes.settings()),
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hide,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.quit,
                ),
              ],
            ),
          ],
        ),
        // Edición: lo que se espera encontrar en cualquier aplicación del
        // Mac. Cada orden hace lo mismo que su atajo en el campo que tenga el
        // foco, así que no es un camino aparte.
        PlatformMenu(
          label: tr('Edición'),
          menus: [
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: tr('Deshacer'),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyZ,
                    meta: true,
                  ),
                  onSelected: () => _edit(
                    const UndoTextIntent(SelectionChangedCause.keyboard),
                  ),
                ),
                PlatformMenuItem(
                  label: tr('Rehacer'),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyZ,
                    meta: true,
                    shift: true,
                  ),
                  onSelected: () => _edit(
                    const RedoTextIntent(SelectionChangedCause.keyboard),
                  ),
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: tr('Cortar'),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyX,
                    meta: true,
                  ),
                  onSelected: () => _edit(
                    const CopySelectionTextIntent.cut(
                      SelectionChangedCause.keyboard,
                    ),
                  ),
                ),
                PlatformMenuItem(
                  label: tr('Copiar'),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyC,
                    meta: true,
                  ),
                  onSelected: () => _edit(CopySelectionTextIntent.copy),
                ),
                PlatformMenuItem(
                  label: tr('Pegar'),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyV,
                    meta: true,
                  ),
                  onSelected: () => _edit(
                    const PasteTextIntent(SelectionChangedCause.keyboard),
                  ),
                ),
                PlatformMenuItem(
                  label: tr('Seleccionar todo'),
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyA,
                    meta: true,
                  ),
                  onSelected: () => _edit(
                    const SelectAllTextIntent(SelectionChangedCause.keyboard),
                  ),
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: tr('Ver'),
          menus: [
            // La paleta, arriba del todo: es el «ir a cualquier sitio», y
            // quien no recuerda el atajo lo busca aquí.
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: tr('Ir a…'),
                  shortcut: activatorFor(AppShortcut.palette),
                  onSelected: dialogContext == null
                      ? null
                      : () => unawaited(showCommandPalette(dialogContext!())),
                ),
              ],
            ),
            // Atrás y adelante los primeros: son lo que se busca en un menú
            // cuando el atajo no se recuerda, y son navegación antes que
            // una vista concreta.
            PlatformMenuItem(
              label: tr('Atrás'),
              shortcut: activatorFor(AppShortcut.back),
              onSelected: () {
                final session = context.read<Session>();
                final target = session.history.back();
                if (target != null) navigate(target);
              },
            ),
            PlatformMenuItem(
              label: tr('Adelante'),
              shortcut: activatorFor(AppShortcut.forward),
              onSelected: () {
                final session = context.read<Session>();
                final target = session.history.forward();
                if (target != null) navigate(target);
              },
            ),
            // En el mismo orden que el carril, y con los mismos números: un
            // menú que dice ⌘1 para lo segundo de la lista se aprende mal.
            PlatformMenuItem(
              label: tr('Asignaturas'),
              shortcut: activatorFor(AppShortcut.courses),
              onSelected: () => navigate(Routes.courses()),
            ),
            PlatformMenuItem(
              label: tr('Biblioteca'),
              shortcut: activatorFor(AppShortcut.library),
              onSelected: () => navigate(Routes.library()),
            ),
            PlatformMenuItem(
              label: tr('Traducción'),
              shortcut: activatorFor(AppShortcut.translations),
              onSelected: () => navigate(Routes.translations()),
            ),
            // El tamaño del texto, donde lo pone cualquier programa del Mac.
            // Las otras teclas --el «+» de un teclado español, el numérico--
            // las atiende el armazón: un elemento de menú lleva un atajo.
            if (context.read<Appearance?>() case final appearance?)
              PlatformMenuItemGroup(
                members: [
                  PlatformMenuItem(
                    label: tr('Texto más grande'),
                    shortcut: activatorFor(AppShortcut.biggerText),
                    onSelected: () => unawaited(appearance.biggerText()),
                  ),
                  PlatformMenuItem(
                    label: tr('Texto más pequeño'),
                    shortcut: activatorFor(AppShortcut.smallerText),
                    onSelected: () => unawaited(appearance.smallerText()),
                  ),
                  PlatformMenuItem(
                    label: tr('Texto del tamaño normal'),
                    shortcut: activatorFor(AppShortcut.normalText),
                    onSelected: () => unawaited(appearance.normalText()),
                  ),
                ],
              ),
            PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.toggleFullScreen,
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: tr('Idioma'),
          menus: [
            // Los mismos que la barra de arriba, y con el nombre que se lee
            // ahí: un menú que dice `va` y una barra que dice «Valencià» son
            // dos listas que hay que aprender por separado.
            for (final option in session.languageChoices)
              PlatformMenuItem(
                label: option.code == session.language
                    ? '✓ ${option.name}'
                    : '  ${option.name}',
                onSelected: () => sessionOf(context).language = option.code,
              ),
          ],
        ),
        PlatformMenu(
          label: tr('Repositorio'),
          menus: [
            PlatformMenuItem(
              label: tr('Traer cambios'),
              shortcut: activatorFor(AppShortcut.pull),
              // Deshabilitado en lugar de oculto: que exista y no se pueda
              // pulsar dice que hace falta un clon, y un menú que cambia de
              // contenido no se aprende.
              onSelected: clone ? () => pullAndTell(context, session) : null,
            ),
            PlatformMenuItem(
              label: tr('Enviar cambios'),
              shortcut: activatorFor(AppShortcut.push),
              onSelected: clone ? () => pushAndTell(context, session) : null,
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: tr('Actualizar desde el disco'),
                  shortcut: activatorFor(AppShortcut.refresh),
                  onSelected: () => refreshAndTell(context, session),
                ),
                PlatformMenuItem(
                  label: tr('Configurar el acceso…'),
                  onSelected: () => navigate(Routes.settings()),
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: tr('Ventana'),
          menus: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
            ),
          ],
        ),
        PlatformMenu(
          label: tr('Ayuda'),
          menus: [
            PlatformMenuItem(
              label: tr('Atajos de teclado'),
              shortcut: activatorFor(AppShortcut.help),
              onSelected: dialogContext == null
                  ? null
                  : () => showShortcuts(dialogContext!()),
            ),
            PlatformMenuItem(
              label: tr('La documentación de Didacta'),
              onSelected: () => openLink(didactaDocs),
            ),
            PlatformMenuItem(
              label: tr('Contar un problema…'),
              onSelected: dialogContext == null
                  ? () => openLink(didactaIssues)
                  : () => openLink(issueLink(dialogContext!())),
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}

/// Trae o envía, y cuenta cómo fue **repositorio por repositorio**.
///
/// `pullAll` y `pushAll` no lanzan: devuelven, por repositorio, cuántos
/// commits movieron o el error que les tocó. Esperar una excepción, como
/// hacía esto, decía «Enviado» también cuando no había salido nada. Lo
/// mismo que la barra, que ya lo leía así.
Future<void> syncAndTell(
  BuildContext context,
  Future<Map<String, Object>> Function() action, {
  required String done,
  required String partly,
  String? nothing,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final result = await action();
    final errors = {
      for (final entry in result.entries)
        if (entry.value is! int) entry.key: entry.value,
    };
    if (errors.length == 1 && result.length == 1 && messenger != null) {
      showProblemIn(messenger, errors.values.single);
      return;
    }
    final failed = [
      for (final entry in errors.entries)
        '${entry.key}: ${problemOf(entry.value).title}',
    ];
    final moved = result.values.whereType<int>().fold(0, (a, b) => a + b);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          failed.isNotEmpty
              ? '$partly:\n${failed.join('\n')}'
              : moved == 0 && nothing != null
              ? nothing
              : done,
        ),
        backgroundColor: failed.isEmpty
            ? null
            : messenger.context.palette.teacher,
        duration: Duration(seconds: failed.isEmpty ? 4 : 10),
      ),
    );
  } catch (error) {
    if (messenger != null) showProblemIn(messenger, error);
  }
}

/// Lanza una acción del repositorio y cuenta el resultado.
///
/// Con aviso al terminar y no en silencio: un «traer cambios» que no dice
/// nada es indistinguible de un menú que no hace nada.
Future<void> runAndTell(
  BuildContext context,
  Future<void> Function() action,
  String done,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
    messenger?.showSnackBar(SnackBar(content: Text(done)));
  } catch (error) {
    if (messenger != null) showProblemIn(messenger, error);
  }
}

/// Trae lo de GitHub y lo cuenta. Del menú de macOS y del atajo en los demás.
Future<void> pullAndTell(BuildContext context, Session session) => syncAndTell(
  context,
  session.pullAll,
  done: tr('Traído de GitHub y actualizado.'),
  partly: tr('Traído, con problemas'),
);

/// Envía lo que ya está guardado, **y solo eso**: sin diálogo no hay mensaje
/// para lo que está sin guardar, y eso lo pide el botón de la barra.
Future<void> pushAndTell(BuildContext context, Session session) => syncAndTell(
  context,
  () => session.pushAll('', commitPending: false),
  done: tr('Enviado a GitHub.'),
  partly: tr('No se pudo enviar todo'),
  nothing: session.pendingCount > 0
      ? tr(
          'No había nada guardado que enviar. Lo que está sin guardar se envía '
          'desde la barra de arriba, que pide el mensaje.',
        )
      : tr('No había nada que enviar.'),
);

/// Relee el disco, regenera el índice y pregunta a GitHub.
Future<void> refreshAndTell(BuildContext context, Session session) =>
    runAndTell(
      context,
      session.refreshEverything,
      tr('Actualizado desde el disco'),
    );

/// Lo que hacen las órdenes de Edición: lo mismo que su atajo en el campo
/// que tenga el foco.
void _edit(Intent intent) {
  final focused = primaryFocus?.context;
  if (focused != null) Actions.maybeInvoke(focused, intent);
}
