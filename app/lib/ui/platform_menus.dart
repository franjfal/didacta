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

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import '../router.dart';
import '../state/session.dart';

/// Envuelve [child] con el menú del sistema donde lo haya.
class PlatformMenus extends StatelessWidget {
  const PlatformMenus({super.key, required this.child});

  final Widget child;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    if (!supported) return child;
    // El contexto de aquí está por debajo del router, así que `context.go`
    // funciona; por encima no habría a dónde navegar.
    return _MacMenus(child: child);
  }
}

class _MacMenus extends StatelessWidget {
  const _MacMenus({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);
    final clone = session.workspace.isNotEmpty;

    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'Didacta',
          menus: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Ajustes…',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.comma,
                    meta: true,
                  ),
                  onSelected: () => _go(context, Routes.settings()),
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
        PlatformMenu(
          label: 'Ver',
          menus: [
            // Atrás y adelante los primeros: son lo que se busca en un menú
            // cuando el atajo no se recuerda, y son navegación antes que
            // una vista concreta.
            PlatformMenuItem(
              label: 'Atrás',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.bracketLeft,
                meta: true,
              ),
              onSelected: () {
                final session = context.read<Session>();
                final target = session.history.back();
                if (target != null) _go(context, target);
              },
            ),
            PlatformMenuItem(
              label: 'Adelante',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.bracketRight,
                meta: true,
              ),
              onSelected: () {
                final session = context.read<Session>();
                final target = session.history.forward();
                if (target != null) _go(context, target);
              },
            ),
            // En el mismo orden que el carril, y con los mismos números: un
            // menú que dice ⌘1 para lo segundo de la lista se aprende mal.
            PlatformMenuItem(
              label: 'Asignaturas',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.digit1,
                meta: true,
              ),
              onSelected: () => _go(context, Routes.courses()),
            ),
            PlatformMenuItem(
              label: 'Biblioteca',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.digit2,
                meta: true,
              ),
              onSelected: () => _go(context, Routes.library()),
            ),
            PlatformMenuItem(
              label: 'Traducción',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.digit3,
                meta: true,
              ),
              onSelected: () => _go(context, Routes.translations()),
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
          label: 'Idioma',
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
          label: 'Repositorio',
          menus: [
            PlatformMenuItem(
              label: 'Traer cambios',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyP,
                meta: true,
                shift: true,
              ),
              // Deshabilitado en lugar de oculto: que exista y no se pueda
              // pulsar dice que hace falta un clon, y un menú que cambia de
              // contenido no se aprende.
              onSelected: clone
                  ? () => _run(context, session.pullAll, 'Traído')
                  : null,
            ),
            PlatformMenuItem(
              label: 'Enviar commits',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyU,
                meta: true,
                shift: true,
              ),
              onSelected: clone
                  ? () => _run(
                      context,
                      // Desde el menú va sin diálogo: envía lo que ya tiene
                      // commit. Lo que está sin guardar necesita un mensaje, y
                      // eso lo pide el botón de la barra.
                      () => session.pushAll('Enviar'),
                      'Enviado',
                    )
                  : null,
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Actualizar desde el disco',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyR,
                    meta: true,
                  ),
                  onSelected: () => _run(
                    context,
                    session.refreshEverything,
                    'Actualizado desde el disco',
                  ),
                ),
                PlatformMenuItem(
                  label: 'Configurar el acceso…',
                  onSelected: () => _go(context, Routes.settings()),
                ),
              ],
            ),
          ],
        ),
      ],
      child: child,
    );
  }

  void _go(BuildContext context, String route) => goTo(context, route);

  /// Lanza una acción del repositorio y cuenta el resultado.
  ///
  /// Con aviso al terminar y no en silencio: un «traer cambios» que no dice
  /// nada es indistinguible de un menú que no hace nada.
  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String done,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
      messenger?.showSnackBar(SnackBar(content: Text(done)));
    } catch (error) {
      messenger?.showSnackBar(
        SnackBar(content: Text('$error'), duration: const Duration(seconds: 6)),
      );
    }
  }
}
