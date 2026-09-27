/// La paleta de órdenes: ⌘K (Ctrl+K), escribir, Intro.
///
/// Ir a una lección, a un curso, a un documento o a una sección de Ajustes, y
/// lanzar lo que se puede hacer en la pantalla en la que se está, sin buscar
/// el botón. No se ve hasta que se pulsa y no estorba a nadie: es la manera
/// rápida de hacer lo que ya se puede hacer con el ratón, no la única.
///
/// Lo que ofrece sale de tres sitios:
///
/// * **lo de esta pantalla**, que cada pantalla apunta mientras está abierta
///   con [PaletteCommands] --guardar, compilar, ver el PDF--;
/// * **las órdenes de siempre** --actualizar, enviar, el tamaño del texto, la
///   apariencia, el idioma que se mira--, las pantallas y las secciones de
///   Ajustes;
/// * **el material**: cada curso, cada documento y cada lección.
///
/// El orden lo decide `model/palette.dart`, con el mismo buscador que la
/// biblioteca: sin tildes, cada palabra en cualquier sitio y con una errata.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../model/catalogue.dart';
import '../model/palette.dart';
import '../router.dart';
import '../state/appearance.dart';
import '../state/session.dart';
import 'platform_menus.dart';
import 'settings_page.dart' show settingsSections;
import 'shortcuts.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Una entrada de la paleta.
class PaletteCommand implements PaletteCandidate {
  PaletteCommand({
    required this.title,
    required this.run,
    this.detail = '',
    this.keywords = '',
    this.icon = Icons.bolt_outlined,
    this.shortcut,
    this.group = PaletteGroup.here,
  });

  @override
  final String title;

  @override
  final String detail;

  @override
  final String keywords;

  @override
  final PaletteGroup group;

  final IconData icon;

  /// Su atajo, si tiene: se enseña a la derecha, para que se aprenda.
  final AppShortcut? shortcut;

  /// Lo que hace. Se llama con la paleta ya cerrada.
  final FutureOr<void> Function() run;

  PaletteCommand inGroup(PaletteGroup other) => PaletteCommand(
    title: title,
    run: run,
    detail: detail,
    keywords: keywords,
    icon: icon,
    shortcut: shortcut,
    group: other,
  );
}

/// Lo que cada pantalla abierta ofrece en la paleta.
///
/// Uno para toda la aplicación, como el registro de diagnósticos: lo apunta
/// quien está montado y lo borra al desmontarse, así que no hay nada que
/// pasar de pantalla en pantalla.
class PaletteRegistry {
  PaletteRegistry._();

  static final PaletteRegistry instance = PaletteRegistry._();

  final List<_PaletteCommandsState> _mounted = [];

  void _add(_PaletteCommandsState owner) => _mounted.add(owner);

  void _remove(_PaletteCommandsState owner) => _mounted.remove(owner);

  /// Lo de las pantallas que se están viendo, la más de dentro primero.
  ///
  /// Solo de las que están delante: go_router deja montada la pantalla de
  /// debajo --la lista de asignaturas bajo un curso--, y sus acciones no son
  /// las de esta pantalla.
  List<PaletteCommand> get here => [
    for (final owner in _mounted.reversed)
      if (owner.mounted && (ModalRoute.of(owner.context)?.isCurrent ?? true))
        ...owner.widget.commands(owner.context),
  ];
}

/// Apunta en la paleta lo que se puede hacer en [child] mientras esté
/// montado.
///
/// [commands] se pregunta al abrir la paleta, no al construir: así lo que
/// ofrece es lo de ese momento --si hay algo que guardar, si hay PDF--.
class PaletteCommands extends StatefulWidget {
  const PaletteCommands({
    super.key,
    required this.commands,
    required this.child,
  });

  final List<PaletteCommand> Function(BuildContext context) commands;
  final Widget child;

  @override
  State<PaletteCommands> createState() => _PaletteCommandsState();
}

class _PaletteCommandsState extends State<PaletteCommands> {
  @override
  void initState() {
    super.initState();
    PaletteRegistry.instance._add(this);
  }

  @override
  void dispose() {
    PaletteRegistry.instance._remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Abre la paleta. [context] tiene que estar por debajo del router: es desde
/// donde se navega al elegir.
Future<void> showCommandPalette(BuildContext context) async {
  final session = sessionOf(context);
  final everything = _everything(context, session);
  final chosen = await showDialog<PaletteCommand>(
    context: context,
    // Un velo y no un fondo: la pantalla de detrás se sigue viendo, que es
    // donde va a pasar lo que se elija.
    barrierColor: context.palette.shadow.withValues(alpha: 0.32),
    builder: (_) => _Palette(empty: everything.empty, all: everything.all),
  );
  if (chosen == null || !context.mounted) return;
  await chosen.run();
}

/// Lo que se ofrece sin escribir nada, y todo lo que se puede buscar.
({List<PaletteCommand> empty, List<PaletteCommand> all}) _everything(
  BuildContext context,
  Session session,
) {
  final here = PaletteRegistry.instance.here;
  final actions = _actions(context, session);
  final screens = _screens(context, session);
  final recent = [
    for (final unit in session.recentUnits.take(6))
      _unitEntry(context, session, unit).inGroup(PaletteGroup.recent),
  ];
  final material = _material(context, session);
  return (
    empty: [...here, ...recent, ...screens, ...actions],
    all: [...here, ...actions, ...screens, ...material],
  );
}

void _go(BuildContext context, String route) {
  if (context.mounted) goTo(context, route);
}

List<PaletteCommand> _actions(BuildContext context, Session session) {
  final appearance = context.read<Appearance?>();
  final history = session.history;
  return [
    if (history.canGoBack)
      PaletteCommand(
        title: tr('Atrás'),
        icon: Icons.arrow_back,
        shortcut: AppShortcut.back,
        group: PaletteGroup.action,
        run: () {
          final target = history.back();
          if (target != null) _go(context, target);
        },
      ),
    if (history.canGoForward)
      PaletteCommand(
        title: tr('Adelante'),
        icon: Icons.arrow_forward,
        shortcut: AppShortcut.forward,
        group: PaletteGroup.action,
        run: () {
          final target = history.forward();
          if (target != null) _go(context, target);
        },
      ),
    PaletteCommand(
      title: tr('Actualizar desde el disco y GitHub'),
      keywords: tr('recargar refrescar índice'),
      icon: Icons.refresh,
      shortcut: AppShortcut.refresh,
      group: PaletteGroup.action,
      run: () => refreshAndTell(context, session),
    ),
    if (session.workspace.isNotEmpty && !session.isFrozen) ...[
      PaletteCommand(
        title: tr('Traer los cambios de GitHub'),
        keywords: tr('pull descargar sincronizar'),
        icon: Icons.download_outlined,
        shortcut: AppShortcut.pull,
        group: PaletteGroup.action,
        run: () => pullAndTell(context, session),
      ),
      PaletteCommand(
        title: tr('Enviar los cambios guardados'),
        keywords: tr('push subir sincronizar'),
        icon: Icons.upload_outlined,
        shortcut: AppShortcut.push,
        group: PaletteGroup.action,
        run: () => pushAndTell(context, session),
      ),
    ],
    if (session.isFrozen)
      PaletteCommand(
        title: tr('Volver a la versión de hoy'),
        keywords: tr('congelada salir actual'),
        icon: Icons.history_toggle_off,
        group: PaletteGroup.action,
        run: session.leaveFreeze,
      ),
    for (final option in session.languageChoices)
      if (option.code != session.language)
        PaletteCommand(
          title: tr('Mirar el material en {0}', [option.name]),
          keywords: tr('idioma {0}', [option.code]),
          icon: Icons.translate,
          group: PaletteGroup.action,
          run: () => session.language = option.code,
        ),
    PaletteCommand(
      title: session.completeInterface
          ? tr('Interfaz esencial: lo de todos los días')
          : tr('Interfaz completa: todo a la vista'),
      keywords: tr('avanzado simple modo'),
      icon: Icons.tune,
      group: PaletteGroup.action,
      run: () => session.setCompleteInterface(!session.completeInterface),
    ),
    if (appearance != null) ...[
      for (final (mode, title, keywords) in [
        (
          AppearanceMode.light,
          tr('Apariencia clara'),
          tr('modo día blanco tema'),
        ),
        (
          AppearanceMode.dark,
          tr('Apariencia oscura'),
          tr('modo noche negro tema'),
        ),
        (
          AppearanceMode.system,
          tr('Apariencia del sistema'),
          tr('modo automático'),
        ),
      ])
        if (appearance.mode != mode)
          PaletteCommand(
            title: title,
            keywords: keywords,
            icon: switch (mode) {
              AppearanceMode.light => Icons.light_mode_outlined,
              AppearanceMode.dark => Icons.dark_mode_outlined,
              AppearanceMode.system => Icons.brightness_auto_outlined,
            },
            group: PaletteGroup.action,
            run: () => appearance.setMode(mode),
          ),
      PaletteCommand(
        title: tr('Texto más grande'),
        keywords: tr('zoom aumentar letra proyector'),
        icon: Icons.text_increase,
        shortcut: AppShortcut.biggerText,
        group: PaletteGroup.action,
        run: appearance.biggerText,
      ),
      PaletteCommand(
        title: tr('Texto más pequeño'),
        keywords: tr('zoom reducir letra'),
        icon: Icons.text_decrease,
        shortcut: AppShortcut.smallerText,
        group: PaletteGroup.action,
        run: appearance.smallerText,
      ),
      PaletteCommand(
        title: tr('Texto del tamaño normal'),
        keywords: tr('zoom letra'),
        icon: Icons.format_size,
        shortcut: AppShortcut.normalText,
        group: PaletteGroup.action,
        run: appearance.normalText,
      ),
    ],
    PaletteCommand(
      title: tr('Ver los atajos de teclado'),
      keywords: tr('teclas ayuda'),
      icon: Icons.keyboard_outlined,
      shortcut: AppShortcut.help,
      group: PaletteGroup.action,
      run: () {
        if (context.mounted) unawaited(showShortcuts(context));
      },
    ),
  ];
}

List<PaletteCommand> _screens(BuildContext context, Session session) => [
  PaletteCommand(
    title: tr('Asignaturas'),
    keywords: tr('cursos ir'),
    icon: Icons.school_outlined,
    shortcut: AppShortcut.courses,
    group: PaletteGroup.screen,
    run: () => _go(context, Routes.courses()),
  ),
  PaletteCommand(
    title: tr('Biblioteca'),
    keywords: tr('lecciones unidades ir'),
    icon: Icons.local_library_outlined,
    shortcut: AppShortcut.library,
    group: PaletteGroup.screen,
    run: () => _go(context, Routes.library()),
  ),
  PaletteCommand(
    title: tr('Traducción'),
    keywords: tr('traducir idiomas ir'),
    icon: Icons.translate,
    shortcut: AppShortcut.translations,
    group: PaletteGroup.screen,
    run: () => _go(context, Routes.translations()),
  ),
  if (session.workspace.isMultiple)
    PaletteCommand(
      title: tr('Entre repositorios'),
      keywords: tr('repos conflictos ir'),
      icon: Icons.compare_arrows,
      group: PaletteGroup.screen,
      run: () => _go(context, Routes.between()),
    ),
  PaletteCommand(
    title: tr('Ajustes'),
    keywords: tr('preferencias configuración ir'),
    icon: Icons.settings_outlined,
    shortcut: AppShortcut.settings,
    group: PaletteGroup.screen,
    run: () => _go(context, Routes.settings()),
  ),
  for (final section in settingsSections(session))
    PaletteCommand(
      title: tr('Ajustes › {0}', [section.label]),
      detail: section.summary,
      keywords: tr('preferencias configuración'),
      icon: section.icon,
      group: PaletteGroup.screen,
      run: () => _go(context, Routes.settings(section: section.id)),
    ),
];

PaletteCommand _unitEntry(BuildContext context, Session session, Unit unit) =>
    PaletteCommand(
      title: unit.title(session.language),
      detail: unit.path,
      keywords: [unit.kind, unit.topic, ...unit.tags].join(' '),
      icon: Icons.article_outlined,
      group: PaletteGroup.unit,
      run: () => _go(context, Routes.unit(unit.path)),
    );

List<PaletteCommand> _material(BuildContext context, Session session) {
  final language = session.language;
  final courses = <PaletteCommand>[];
  final documents = <PaletteCommand>[];
  for (final course in session.sortedCourses) {
    final title = course.title(language);
    for (final year in session.sortedYearsOf(course)) {
      courses.add(
        PaletteCommand(
          title: '$title · $year',
          detail: course.code ?? '',
          keywords: tr('asignatura curso {0}', [course.id]),
          icon: Icons.calendar_month_outlined,
          group: PaletteGroup.course,
          run: () => _go(context, Routes.year(course.id, year)),
        ),
      );
      for (final document in course.years[year]!.documents) {
        documents.add(
          PaletteCommand(
            title: document.title(language),
            detail: '$title · $year',
            keywords: document.kind,
            icon: Icons.description_outlined,
            group: PaletteGroup.document,
            run: () =>
                _go(context, Routes.document(course.id, year, document.id)),
          ),
        );
      }
    }
  }
  return [
    ...courses,
    ...documents,
    for (final unit in session.catalogue.units)
      _unitEntry(context, session, unit),
  ];
}

class _Palette extends StatefulWidget {
  const _Palette({required this.empty, required this.all});

  final List<PaletteCommand> empty;
  final List<PaletteCommand> all;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = ScrollController();
  late List<PaletteCommand> _shown = widget.empty;
  int _selected = 0;

  /// La altura de una fila, para llevar la elegida a la vista con las
  /// flechas sin medir nada.
  static const double _row = 44;

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _search(String text) {
    setState(() {
      _shown = text.trim().isEmpty
          ? widget.empty
          : rankPalette(widget.all, text);
      _selected = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _move(int by) {
    if (_shown.isEmpty) return;
    setState(() => _selected = (_selected + by).clamp(0, _shown.length - 1));
    if (!_scroll.hasClients) return;
    final top = _selected * _row;
    final view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + _row > _scroll.offset + view) {
      _scroll.jumpTo(top + _row - view);
    }
  }

  void _choose([int? index]) {
    final at = index ?? _selected;
    if (at < 0 || at >= _shown.length) return;
    Navigator.of(context).pop(_shown[at]);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.pageDown:
        _move(8);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.pageUp:
        _move(-8);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _choose();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final searching = _query.text.trim().isNotEmpty;
    return Align(
      alignment: const Alignment(0, -0.55),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Material(
          key: const Key('command-palette'),
          color: palette.card,
          elevation: 8,
          shadowColor: palette.shadow,
          borderRadius: BorderRadius.circular(Radii.dialog),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Focus(
                  onKeyEvent: _key,
                  child: TextField(
                    key: const Key('palette-field'),
                    controller: _query,
                    autofocus: true,
                    onChanged: _search,
                    style: const TextStyle(fontSize: 15),
                    decoration: InputDecoration(
                      hintText: tr('Busca una orden, una lección, un curso…'),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 20,
                        color: palette.muted,
                      ),
                      // Sin recuadro: el campo es la paleta entera, y un
                      // borde de foco dentro de ella es un marco en un marco.
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                  ),
                ),
                Divider(height: 1, color: palette.rule),
                Flexible(
                  child: _shown.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            tr('Nada coincide con «{0}».', [
                              _query.text.trim(),
                            ]),
                            key: const Key('palette-empty'),
                            style: TextStyle(color: palette.muted),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: _shown.length,
                          itemExtent: _row,
                          itemBuilder: (context, index) => _Row(
                            key: Key('palette-item-$index'),
                            command: _shown[index],
                            selected: index == _selected,
                            // Sin escribir, el grupo lo dice el título de
                            // la sección de la primera de cada uno; al
                            // buscar, cada fila dice el suyo.
                            group:
                                searching ||
                                    index == 0 ||
                                    _shown[index - 1].group !=
                                        _shown[index].group
                                ? _shown[index].group.label
                                : null,
                            onHover: () => setState(() => _selected = index),
                            onTap: () => _choose(index),
                          ),
                        ),
                ),
                Divider(height: 1, color: palette.rule),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr(
                            'Flechas para elegir · Intro para abrir · Esc para '
                            'cerrar',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: palette.muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        labelFor(AppShortcut.palette),
                        style: TextStyle(fontSize: 11.5, color: palette.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.command,
    required this.selected,
    required this.group,
    required this.onHover,
    required this.onTap,
  });

  final PaletteCommand command;
  final bool selected;
  final String? group;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final shortcut = command.shortcut;
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? palette.selected : null,
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          child: Row(
            children: [
              Icon(
                command.icon,
                size: 18,
                color: selected ? palette.accentDark : palette.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      command.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: palette.ink,
                      ),
                    ),
                    if (command.detail.isNotEmpty)
                      Text(
                        command.detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: palette.muted),
                      ),
                  ],
                ),
              ),
              if (shortcut != null) ...[
                const SizedBox(width: 8),
                Text(
                  labelFor(shortcut),
                  style: TextStyle(fontSize: 11.5, color: palette.muted),
                ),
              ],
              if (group != null) ...[
                const SizedBox(width: 10),
                Text(
                  group!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: palette.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
