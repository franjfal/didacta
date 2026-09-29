/// Ajustes: la cuenta de GitHub, los repositorios y lo que hay cargado.
///
/// Esta pantalla cambió de raíz cuando la identidad pasó de Firebase a
/// GitHub. Antes había tres cosas que cuadrar --quién eres para Firebase, qué
/// permisos te da un `access.json`, y un token pegado a mano para escribir--
/// y ahora hay una: **entras en GitHub**. Quien puede escribir en un
/// repositorio es quien GitHub dice que puede, que es lo que ya era cierto
/// antes de que lo dijéramos nosotros.
///
/// Y una sola pantalla para varios repositorios a la vez, porque eso es lo
/// que la aplicación hace ahora: cada uno con su carpeta, su color y su
/// estado respecto a GitHub.
library;

import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/diagnostics.dart';
import '../data/github.dart' show didactaAppSlug, githubAppInstallUrl;
import '../data/browser.dart';
import '../data/compiler.dart';
import '../data/template_store.dart';
import '../data/toolchain.dart';
import '../model/material_ci.dart';
import '../model/workspace.dart';
import '../router.dart';
import '../data/mcp_process.dart';
import '../state/appearance.dart';
import '../state/mcp_service.dart';
import '../state/session.dart';
import '../state/update_service.dart';
import 'build_folder.dart';
import 'course_admin_ui.dart';
import 'engine_version_line.dart';
import 'language_settings.dart';
import 'glossary_editor.dart';
import 'manage_blocks.dart';
import 'manage_snippets.dart';
import 'manage_templates.dart';
import 'problem.dart';
import 'publish_folder.dart';
import 'remove_repository.dart';
import 'shell.dart';
import 'shortcuts.dart';
import 'sign_in.dart';
import 'start_over.dart';
import 'add_repository.dart';
import 'theme.dart';
import 'toolchain_check.dart';
import 'tour.dart';
import 'translation_settings.dart';
import 'update_section.dart';
import 'working.dart';
import '../l10n/tr.dart';

/// Una sección de Ajustes: su dirección, su nombre, su icono y qué hay dentro.
class SettingsSection {
  const SettingsSection({
    required this.id,
    required this.label,
    required this.icon,
    required this.summary,
    this.group = 0,
    this.danger = false,
  });

  /// Lo que va en la dirección: `/settings?s=<id>`.
  final String id;
  final String label;
  final IconData icon;

  /// Una frase debajo del título de la sección.
  final String summary;

  /// Con cuáles va junta en la lista: un separador entre grupo y grupo.
  final int group;

  /// Si lo que hay dentro no se deshace --empezar de cero--.
  final bool danger;
}

/// Las secciones que tocan en esta copia, en el orden en que se buscan.
///
/// Primero lo que se toca el primer día --la cuenta, los repositorios--,
/// después lo del material, después las herramientas y al final lo que se
/// busca a propósito. Las que no pueden hacer nada aquí no salen: una sección
/// de herramientas en la web solo diría «aquí no».
///
/// Las de quien mantiene el repositorio del departamento --los bloques, las
/// plantillas y el catálogo; el servidor MCP-- solo con la interfaz Completa.
/// Salvo que se llegue a una por su dirección ([asked]), que es un enlace
/// que alguien ha seguido a propósito, o que el servidor esté encendido
/// ([mcpOn]): lo que está en marcha tiene que poder apagarse.
List<SettingsSection> settingsSections(
  Session session, {
  String? asked,
  bool mcpOn = false,
}) => [
  SettingsSection(
    id: 'repositorios',
    label: tr('Cuenta y repositorios'),
    icon: Icons.account_circle_outlined,
    summary: tr(
      'Con qué cuenta de GitHub entras, qué repositorios tienes abiertos y '
      'dónde se clonan.',
    ),
  ),
  SettingsSection(
    id: 'guardar',
    label: tr('Guardar y sincronizar'),
    icon: Icons.cloud_sync_outlined,
    summary: tr(
      'Qué pasa al guardar un cambio, y dónde viajan tus preferencias de un '
      'ordenador a otro.',
    ),
  ),
  SettingsSection(
    id: 'idiomas',
    label: tr('Idiomas'),
    icon: Icons.translate,
    group: 1,
    summary: tr('Con cuáles trabajas tú, y a cuáles traduce cada repositorio.'),
  ),
  SettingsSection(
    id: 'traduccion',
    label: tr('Traducción automática'),
    icon: Icons.auto_awesome_outlined,
    group: 1,
    summary: tr('Las cuentas con las que se traduce una lección de un clic.'),
  ),
  if (session.completeInterface || asked == 'material')
    SettingsSection(
      id: 'material',
      label: tr('Bloques y plantillas'),
      icon: Icons.category_outlined,
      group: 1,
      summary: tr(
        'En qué partes se divide una asignatura, qué PDF salen del material '
        'y qué hay cargado.',
      ),
    ),
  SettingsSection(
    id: 'snippets',
    label: tr('Snippets de LaTeX'),
    icon: Icons.data_object,
    group: 1,
    summary: tr(
      'Lo que la barra del editor envuelve: cada snippet, cómo queda y en '
      'qué repositorios se ofrece.',
    ),
  ),
  if (Toolchain.supported || session.canCompile)
    SettingsSection(
      id: 'herramientas',
      label: tr('Herramientas'),
      icon: Icons.handyman_outlined,
      group: 2,
      summary: tr(
        'Los programas que Didacta pide prestados para escribir y compilar.',
      ),
    ),
  if (session.completeInterface || mcpOn || asked == 'mcp')
    SettingsSection(
      id: 'mcp',
      label: tr('Servidor MCP'),
      icon: Icons.hub_outlined,
      group: 2,
      summary: tr(
        'Para que un asistente de IA lea tu material, y si quieres, lo escriba.',
      ),
    ),
  SettingsSection(
    id: 'apariencia',
    label: tr('Apariencia'),
    icon: Icons.palette_outlined,
    group: 3,
    summary: tr(
      'Claro, oscuro o lo que diga el sistema, y el tamaño del texto.',
    ),
  ),
  SettingsSection(
    id: 'actualizaciones',
    label: tr('Actualizaciones'),
    icon: Icons.system_update_alt,
    group: 3,
    summary: tr('Qué versión tienes y si hay una más nueva.'),
  ),
  SettingsSection(
    id: 'ayuda',
    label: tr('Ayuda'),
    icon: Icons.help_outline,
    group: 3,
    summary: tr('La presentación, el recorrido guiado y la documentación.'),
  ),
  if (session.files.supported)
    SettingsSection(
      id: 'empezar',
      label: tr('Empezar de cero'),
      icon: Icons.restart_alt,
      group: 4,
      danger: true,
      summary: tr(
        'Dejar Didacta en este ordenador como recién instalada. Los '
        'repositorios de GitHub no se tocan.',
      ),
    ),
];

/// Ajustes, por secciones.
///
/// Era una sola lista de catorce apartados, y encontrar uno era bajar hasta
/// verlo pasar. Ahora las secciones van en una columna a la izquierda y se ve
/// una a la vez; cuál es lo dice la dirección --`/settings?s=idiomas`--, así
/// que un enlace de otra pantalla lleva a la que hace falta y el botón de
/// atrás vuelve a la de antes.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.section});

  /// La sección abierta, o `null` para la primera.
  final String? section;

  // Los ajustes de trabajo avisan por su cuenta, no por la sesión.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sessionOf(context).settings,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
    final session = watchSession(context);
    final mcp = context.watch<McpService?>();
    final sections = settingsSections(
      session,
      asked: section,
      mcpOn: mcp != null && mcp.state != McpState.off,
    );
    final current = sections.firstWhere(
      (each) => each.id == section,
      orElse: () => sections.first,
    );

    return Column(
      children: [
        PageHeader(
          title: tr('Ajustes'),
          subtitle: tr('Tu cuenta, tus repositorios y cómo trabaja Didacta'),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 820;
              final content = _SectionContent(
                key: ValueKey(current.id),
                section: current,
                children: _sectionBody(context, session, current.id),
              );
              if (!wide) {
                return Column(
                  children: [
                    _SectionStrip(sections: sections, current: current),
                    Expanded(child: content),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionNav(sections: sections, current: current),
                  VerticalDivider(width: 1, color: context.palette.rule),
                  Expanded(child: content),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  static List<Widget> _sectionBody(
    BuildContext context,
    Session session,
    String id,
  ) => switch (id) {
    'repositorios' => [
      SectionLabel(tr('Cuenta de GitHub')),
      _AccountSection(session: session),
      SectionLabel(tr('Repositorios')),
      _ReposSection(session: session),
      // Solo aparece mientras haya algo que poner al día, así que no es un
      // apartado permanente: es un aviso con un botón. Y solo en Completa:
      // es escribir en el `unit.yaml` de cada lección, cosa de quien
      // mantiene el repositorio.
      if (session.completeInterface) _IdentitySection(session: session),
    ],
    'guardar' => [
      SectionLabel(tr('Al guardar')),
      _SavingSection(session: session),
      SectionLabel(tr('Mis preferencias')),
      _PrefsSection(session: session),
      SectionLabel(tr('Carpeta de reparto')),
      PublishFolderSection(session: session),
    ],
    'idiomas' => [LanguageSettings(session: session)],
    'traduccion' => [
      TranslationSection(secrets: session.translationSecrets),
      SectionLabel(tr('Glosario')),
      GlossarySection(session: session),
    ],
    // Se leen en este orden: el bloque dice **qué** material es, la
    // plantilla **qué sale** de él, y el catálogo enseña el resultado.
    'material' => [
      SectionLabel(tr('Bloques')),
      _BlocksSection(session: session),
      SectionLabel(tr('Plantillas')),
      _TemplatesSection(session: session),
      SectionLabel(tr('Catálogo')),
      _CatalogueSection(session: session),
    ],
    'snippets' => [SnippetsManager(session: session)],
    'herramientas' => [
      if (Toolchain.supported) ...[
        SectionLabel(tr('Lo que hace falta en tu ordenador')),
        _ToolsSection(session: session),
      ],
      if (session.canCompile) ...[
        SectionLabel(tr('Compilar')),
        _EngineSection(session: session),
        SectionLabel(tr('La carpeta de compilación')),
        BuildFolders(session: session),
      ],
    ],
    'mcp' => [_McpSection(session: session)],
    'apariencia' => [const _AppearanceSection()],
    'actualizaciones' => [const UpdateSection()],
    'ayuda' => [_HelpSection(session: session)],
    'empezar' => [StartOverSection(session: session)],
    _ => const [],
  };
}

/// El título de la sección abierta, y lo que tiene dentro.
class _SectionContent extends StatelessWidget {
  const _SectionContent({
    super.key,
    required this.section,
    required this.children,
  });

  final SettingsSection section;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(0, 18, 0, 32),
    children: [
      Center(
        child: ConstrainedBox(
          // Una columna de lectura y no la ventana entera: en una pantalla
          // de 2560 una fila de ajustes de lado a lado es una frase que no
          // se puede seguir con la vista.
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color:
                            (section.danger
                                    ? context.palette.teacher
                                    : context.palette.accent)
                                .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(Radii.control),
                      ),
                      child: Icon(
                        section.icon,
                        size: 18,
                        color: section.danger
                            ? context.palette.teacher
                            : context.palette.accentDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.label,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            section.summary,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: context.palette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ...children,
            ],
          ),
        ),
      ),
    ],
  );
}

/// Las secciones en una columna, a la izquierda.
class _SectionNav extends StatelessWidget {
  const _SectionNav({required this.sections, required this.current});

  final List<SettingsSection> sections;
  final SettingsSection current;

  @override
  Widget build(BuildContext context) => Container(
    // Crece con el tamaño del texto, hasta un punto: con el texto al 150 %
    // la mitad de los nombres salían cortados, y son lo que se lee para
    // saber a dónde ir.
    width: MediaQuery.textScalerOf(context).scale(236).clamp(236, 330),
    color: context.palette.panel,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
      children: [
        for (final (index, section) in sections.indexed) ...[
          if (index > 0 && sections[index - 1].group != section.group)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              child: Divider(height: 1, color: context.palette.rule),
            ),
          _NavItem(section: section, selected: section.id == current.id),
        ],
      ],
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.section, required this.selected});

  final SettingsSection section;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tint = section.danger
        ? context.palette.teacher
        : (selected ? context.palette.accentDark : context.palette.ink);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? context.palette.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.control),
        child: InkWell(
          key: Key('settings-section-${section.id}'),
          borderRadius: BorderRadius.circular(Radii.control),
          onTap: () => context.go(Routes.settings(section: section.id)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(
                  section.icon,
                  size: 17,
                  color: selected || section.danger
                      ? tint
                      : context.palette.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: tint,
                    ),
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

/// Las secciones en una tira, arriba: la columna no cabe en una ventana
/// estrecha, y sin ella las secciones no tendrían dónde elegirse.
class _SectionStrip extends StatelessWidget {
  const _SectionStrip({required this.sections, required this.current});

  final List<SettingsSection> sections;
  final SettingsSection current;

  @override
  Widget build(BuildContext context) => Container(
    height: 50,
    decoration: BoxDecoration(
      color: context.palette.panel,
      border: Border(bottom: BorderSide(color: context.palette.rule)),
    ),
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      children: [
        for (final section in sections)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              key: Key('settings-section-${section.id}'),
              avatar: Icon(section.icon, size: 15),
              label: Text(section.label),
              selected: section.id == current.id,
              showCheckmark: false,
              onSelected: (_) =>
                  context.go(Routes.settings(section: section.id)),
            ),
          ),
      ],
    ),
  );
}

/// Claro, oscuro o el del sistema, con una muestra de cada uno.
class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _modes(context),
      if (context.watch<Appearance?>() case final appearance?) ...[
        SectionLabel(tr('Tamaño del texto')),
        _TextSize(appearance: appearance),
        SectionLabel(tr('Idioma de Didacta')),
        _UiLanguageChoice(appearance: appearance),
      ],
      SectionLabel(tr('Interfaz')),
      _InterfaceChoice(session: watchSession(context)),
    ],
  );

  Widget _modes(BuildContext context) {
    final appearance = context.watch<Appearance?>();
    if (appearance == null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Note(tr('Esta copia se ha montado sin poder cambiar de modo.')),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (mode, label, detail) in [
                    (
                      AppearanceMode.system,
                      tr('Como el sistema'),
                      tr(
                        'De día claro y de noche oscuro, si el ordenador lo hace',
                      ),
                    ),
                    (AppearanceMode.light, tr('Claro'), tr('Siempre')),
                    (AppearanceMode.dark, tr('Oscuro'), tr('Siempre')),
                  ])
                    _ModeChoice(
                      key: Key('appearance-${mode.name}'),
                      mode: mode,
                      label: label,
                      detail: detail,
                      selected: appearance.mode == mode,
                      onTap: () => appearance.setMode(mode),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                tr(
                  'También se cambia con el botón del sol y la luna, abajo del '
                  'todo en la columna de la izquierda. Los PDF no cambian: un '
                  'PDF se imprime, y se compila siempre en claro.',
                ),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: context.palette.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El idioma de la interfaz: el del sistema, o uno de los tres.
///
/// No es el del material: quien trabaja la interfaz en valenciano prepara
/// igual los apuntes en castellano y en inglés. Cada idioma, con su nombre
/// en su idioma, que es como lo busca quien no entiende el que hay puesto.
class _UiLanguageChoice extends StatelessWidget {
  const _UiLanguageChoice({required this.appearance});

  final Appearance appearance;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<String>(
              key: const Key('ui-language'),
              segments: [
                ButtonSegment(
                  value: 'system',
                  label: Text(tr('El del sistema')),
                ),
                for (final language in UiLanguage.values)
                  ButtonSegment(
                    value: language.code,
                    label: Text(language.label),
                  ),
              ],
              selected: {appearance.languageChoice},
              onSelectionChanged: (value) =>
                  appearance.setUiLanguage(value.single),
            ),
            const SizedBox(height: 12),
            Text(
              tr(
                'Los menús, los botones y los avisos. No cambia el idioma del '
                'material, que se elige arriba, en cada pantalla.',
              ),
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: context.palette.muted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Más grande o más pequeño: el proyector del aula, una pantalla pequeña.
///
/// Por pasos y con el tanto por ciento a la vista, igual que con ⌘+ y ⌘−,
/// que hacen lo mismo desde cualquier pantalla.
class _TextSize extends StatelessWidget {
  const _TextSize({required this.appearance});

  final Appearance appearance;

  @override
  Widget build(BuildContext context) {
    final scale = appearance.textScale;
    final steps = Appearance.textScales;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton.outlined(
                    key: const Key('text-smaller'),
                    tooltip: tr('Más pequeño  {0}', [
                      labelFor(AppShortcut.smallerText),
                    ]),
                    onPressed: scale == steps.first
                        ? null
                        : () => unawaited(appearance.smallerText()),
                    icon: const Icon(Icons.text_decrease),
                  ),
                  // Con un ancho mínimo y no fijo: con el texto al 135 %,
                  // «135 %» no cabía en 56 puntos y se partía en dos líneas.
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 56),
                    child: Text(
                      '${(scale * 100).round()} %',
                      key: const Key('text-scale'),
                      textAlign: TextAlign.center,
                      softWrap: false,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton.outlined(
                    key: const Key('text-bigger'),
                    tooltip: tr('Más grande  {0}', [
                      labelFor(AppShortcut.biggerText),
                    ]),
                    onPressed: scale == steps.last
                        ? null
                        : () => unawaited(appearance.biggerText()),
                    icon: const Icon(Icons.text_increase),
                  ),
                  if (scale != 1)
                    TextButton(
                      key: const Key('text-normal'),
                      onPressed: () => unawaited(appearance.normalText()),
                      child: Text(tr('Tamaño normal')),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                tr(
                  'Para el proyector del aula o una pantalla pequeña, y solo en '
                  'este ordenador. Desde cualquier pantalla, '
                  '{0} y '
                  '{1}; '
                  '{2} lo deja como estaba. Los '
                  'PDF no cambian.',
                  [
                    labelFor(AppShortcut.biggerText),
                    labelFor(AppShortcut.smallerText),
                    labelFor(AppShortcut.normalText),
                  ],
                ),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: context.palette.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Esencial o Completa: cuánto enseña la interfaz.
///
/// Esencial es lo de todos los días, y es lo de salida. Completa añade lo de
/// quien mantiene el repositorio del departamento: rutas y contadores, la
/// sangría de cada fichero, copiar la referencia de una lección, reemplazar
/// en el editor, mover lecciones. Un solo interruptor y no uno por cosa: lo
/// que se pregunta es qué clase de uso se hace, no cada botón.
class _InterfaceChoice extends StatelessWidget {
  const _InterfaceChoice({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session.settings,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              key: const Key('interface-mode'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(tr('Esencial'), key: Key('interface-essential')),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(tr('Completa'), key: Key('interface-complete')),
                ),
              ],
              selected: {session.completeInterface},
              onSelectionChanged: (value) =>
                  session.setCompleteInterface(value.single),
            ),
            const SizedBox(height: 12),
            Text(
              session.completeInterface
                  ? tr(
                      'Todo a la vista, también lo de quien mantiene el '
                      'repositorio: Bloques y plantillas y el servidor MCP '
                      'aquí en Ajustes, las rutas de las herramientas y el '
                      'registro entero al compilar, reemplazar en el editor, '
                      'mover temas y gestionar su vinculación, y '
                      '«Entre repos» siempre en la columna de la izquierda.',
                    )
                  : tr(
                      'Lo de todos los días: escribir, traducir, compilar y '
                      'repartir. Lo de quien mantiene el repositorio --los '
                      'bloques y las plantillas, las rutas, reemplazar, '
                      'mover temas-- está en Completa.',
                    ),
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: context.palette.muted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Un modo, con una ventana en miniatura pintada en él.
class _ModeChoice extends StatelessWidget {
  const _ModeChoice({
    super.key,
    required this.mode,
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final AppearanceMode mode;
  final String label;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 212,
    child: Material(
      color: selected ? context.palette.selected : context.palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(
          color: selected ? context.palette.accentDark : context.palette.rule,
          width: selected ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.small),
                child: SizedBox(
                  height: 96,
                  width: double.infinity,
                  child: CustomPaint(painter: _ModePreview(mode)),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: selected
                        ? context.palette.accentDark
                        : context.palette.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 22, top: 2),
                child: Text(
                  detail,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.palette.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// La ventana de Didacta en pequeño, en claro, en oscuro o partida en dos.
class _ModePreview extends CustomPainter {
  const _ModePreview(this.mode);

  final AppearanceMode mode;

  void _window(Canvas canvas, Rect area, DidactaPalette p) {
    canvas.drawRect(area, Paint()..color = p.surface);
    final rail = Rect.fromLTWH(area.left, area.top, 26, area.height);
    canvas.drawRect(rail, Paint()..color = p.panel);
    for (var i = 0; i < 4; i += 1) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rail.left + 8, rail.top + 12 + i * 18.0, 10, 10),
          const Radius.circular(3),
        ),
        Paint()..color = i == 0 ? p.accentDark : p.faint.withValues(alpha: 0.5),
      );
    }
    final header = Rect.fromLTWH(rail.right, area.top, area.width - 26, 24);
    canvas.drawRect(header, Paint()..color = p.card);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(header.left + 10, header.top + 8, 58, 7),
        const Radius.circular(3),
      ),
      Paint()..color = p.ink,
    );
    for (var i = 0; i < 2; i += 1) {
      final card = Rect.fromLTWH(
        header.left + 10,
        header.bottom + 8 + i * 30.0,
        header.width - 20,
        24,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(card, const Radius.circular(4)),
        Paint()..color = p.card,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(card, const Radius.circular(4)),
        Paint()
          ..color = p.rule
          ..style = PaintingStyle.stroke,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(card.left + 8, card.top + 7, 46, 5),
          const Radius.circular(2),
        ),
        Paint()..color = p.muted,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(card.right - 28, card.top + 7, 20, 10),
          const Radius.circular(3),
        ),
        Paint()..color = p.accentDark.withValues(alpha: 0.3),
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    switch (mode) {
      case AppearanceMode.light:
        _window(canvas, area, DidactaPalette.light);
      case AppearanceMode.dark:
        _window(canvas, area, DidactaPalette.dark);
      case AppearanceMode.system:
        // Las dos, partidas en diagonal: es lo que hace «el del sistema».
        _window(canvas, area, DidactaPalette.light);
        canvas.save();
        canvas.clipPath(
          Path()
            ..moveTo(size.width * 0.62, 0)
            ..lineTo(size.width, 0)
            ..lineTo(size.width, size.height)
            ..lineTo(size.width * 0.38, size.height)
            ..close(),
        );
        _window(canvas, area, DidactaPalette.dark);
        canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ModePreview old) => old.mode != mode;
}

/// Volver a ver lo que se enseña la primera vez.
///
/// Al final de Ajustes y no arriba: quien lo busca ya sabe lo que busca, y lo
/// que se abre a diario es la cuenta y los repositorios. Y aquí y no en un
/// menú de ayuda, porque un menú de ayuda con dos entradas es un menú que
/// nadie abre.
class _HelpSection extends StatelessWidget {
  const _HelpSection({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      sessionOf(context).settings,
      sessionOf(context).engine,
    ]),
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                'La presentación explica qué es Didacta y deja la configuración '
                'hecha. El recorrido va de pantalla en pantalla --una '
                'asignatura, su curso, un documento, la biblioteca y una '
                'lección-- señalando cada parte, y al acabar te deja donde '
                'estabas.',
              ),
              style: TextStyle(fontSize: 12.5, color: context.palette.muted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  key: const Key('replay-welcome'),
                  icon: const Icon(Icons.slideshow_outlined, size: 16),
                  label: Text(tr('Volver a ver la presentación')),
                  onPressed: session.replayWelcome,
                ),
                OutlinedButton.icon(
                  key: const Key('replay-tour'),
                  icon: const Icon(Icons.explore_outlined, size: 16),
                  label: Text(tr('Ver el recorrido guiado')),
                  // Sin esperar a nada: el tour va él mismo a cada pantalla,
                  // espera a lo que señala y al acabar vuelve aquí.
                  onPressed: context.read<TourController>().start,
                ),
                TextButton.icon(
                  key: const Key('open-shortcuts'),
                  icon: const Icon(Icons.keyboard_outlined, size: 16),
                  label: Text(
                    tr('Atajos de teclado  {0}', [labelFor(AppShortcut.help)]),
                  ),
                  onPressed: () => showShortcuts(context),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.menu_book_outlined, size: 16),
                  label: Text(tr('La documentación')),
                  onPressed: () => openLink(didactaDocs),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              tr(
                'Si algo falla, el informe de diagnóstico cuenta lo que ha '
                'pasado por dentro --qué versión, qué contestaron el motor, git '
                'y GitHub-- sin tus claves ni tus contraseñas. Se copia para '
                'pegarlo en una incidencia.',
              ),
              style: TextStyle(fontSize: 12.5, color: context.palette.muted),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('copy-diagnostics'),
              icon: const Icon(Icons.content_paste_go_outlined, size: 16),
              label: Text(tr('Copiar informe de diagnóstico')),
              onPressed: () => _copyReport(context),
            ),
          ],
        ),
      ),
    ),
  );

  /// Lo que dice el informe de esta máquina, además del registro.
  Map<String, String> _about(BuildContext context) {
    final info = context.read<UpdateService?>()?.info;
    final engine = session.engineVersion;
    return {
      'Didacta': info?.describe ?? tr('(versión desconocida)'),
      'sistema': Diagnostics.system,
      'motor':
          engine?.engine?.toString() ?? session.enginePath ?? tr('no está'),
      'TeX': session.texPath ?? tr('el que se encuentre'),
      'repositorios': '${session.workspace.repos.length}',
      'interfaz': session.completeInterface ? 'completa' : 'esencial',
    };
  }

  Future<void> _copyReport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final report = Diagnostics.instance.report(about: _about(context));
    await Clipboard.setData(ClipboardData(text: report));
    // En la dirección si cabe, y si no, pegado a mano: una dirección de más
    // de unos ocho mil caracteres no la abre ningún navegador.
    final body = report.length < 6000
        ? report
        : tr(
            'Pega aquí el informe de diagnóstico: Didacta lo acaba de copiar.',
          );
    messenger.showSnackBar(
      SnackBar(
        key: const Key('diagnostics-copied'),
        duration: const Duration(seconds: 8),
        // Con acción, Flutter lo dejaría puesto hasta que se pulse; este se va
        // solo, a su tiempo.
        persist: false,
        content: Text(
          tr(
            'Informe copiado. Revísalo antes de enviarlo: no lleva claves, pero '
            'sí nombres de ficheros.',
          ),
        ),
        action: SnackBarAction(
          label: tr('Abrir una incidencia'),
          onPressed: () =>
              openLink('$didactaIssues/new?body=${Uri.encodeComponent(body)}'),
        ),
      ),
    );
  }
}

/// Dónde se guardan las preferencias que viajan de un ordenador a otro.
///
/// Se elige, y no se decide por la persona, porque no hay ninguna elección
/// evidente: cada uno tiene los repositorios que tiene y no coinciden con los
/// de nadie. Sin elegir ninguno, todo sigue funcionando en esta máquina; lo
/// que se gana al elegir es encontrarlo igual en la de casa.
class _PrefsSection extends StatelessWidget {
  const _PrefsSection({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sessionOf(context).libraryPrefs,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
    final repos = session.workspace.repos;
    final chosen = session.prefsRepo;
    final path = session.prefsPath;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'Lo que decides sobre el material --qué temas tienes '
                  'plegados-- puede seguirte de un ordenador a otro. Se guarda '
                  'en el repositorio que elijas, en un fichero con tu nombre de '
                  'GitHub, así que podéis compartir repositorio sin pisaros.',
                ),
                style: TextStyle(fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 10),
              if (repos.isEmpty)
                Note(
                  tr(
                    'Sin repositorios abiertos no hay dónde guardarlas. '
                    'Se quedan en esta máquina.',
                  ),
                )
              else ...[
                RadioGroup<String?>(
                  groupValue: chosen,
                  onChanged: (value) => session.setPrefsRepo(value),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RadioListTile<String?>(
                        key: const Key('prefs-repo-none'),
                        value: null,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          tr('Solo en este ordenador'),
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      for (final repo in repos)
                        RadioListTile<String?>(
                          key: Key('prefs-repo-${repo.id}'),
                          value: repo.id,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            repo.id,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                ),
                if (chosen != null) ...[
                  const SizedBox(height: 6),
                  _Fact(
                    'fichero',
                    path ?? tr('hace falta haber entrado en GitHub'),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        key: const Key('prefs-sync-now'),
                        icon: const Icon(Icons.sync, size: 15),
                        label: Text(tr('Guardarlas ahora')),
                        onPressed: session.pushSyncedPrefs,
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Quién ha entrado, y cómo salir o cambiar de cuenta.
///
/// La ficha de quien **ya** entró: sin sesión no se llega a Ajustes, porque
/// sin sesión no se llega a ninguna pantalla. El formulario es el mismo de la
/// puerta --[SignInForm]--, y está aquí para el caso de cambiar de cuenta.
class _AccountSection extends StatelessWidget {
  const _AccountSection({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final user = session.user;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (session.signedIn) ...[
                Row(
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      // Puede no saberse el nombre habiendo sesión: se entró
                      // en otra máquina que no lo apuntaba, o se abrió sin
                      // red por primera vez desde entonces. Lo que hay es lo
                      // que se dice.
                      child: Text(
                        user == null
                            ? tr('Sesión iniciada en GitHub')
                            : '${user.authorName} (${user.login})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      key: const Key('github-sign-out'),
                      onPressed: session.signOut,
                      child: Text(tr('Salir')),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  user == null
                      ? tr(
                          'Salir cierra la sesión en esta máquina. Las copias de '
                          'los repositorios se quedan: son carpetas con el '
                          'trabajo dentro.',
                        )
                      : tr(
                          'Los cambios se firman como {0}. Los '
                          'permisos son los de GitHub: se puede escribir '
                          'donde GitHub deje escribir.',
                          [user.authorEmail],
                        ),
                  style: TextStyle(fontSize: 12, color: context.palette.muted),
                ),
                // Con la GitHub App, Didacta llega a los repositorios que se
                // le den, y eso se elige en GitHub: el botón lleva allí.
                if (session.auth.credential?.fromApp ?? false) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr(
                            'Didacta entra como GitHub App: llega a los '
                            'repositorios que le des, no a todos los tuyos. '
                            'La sesión se renueva sola.',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.muted,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        key: const Key('github-app-repositories'),
                        icon: const Icon(Icons.open_in_new, size: 15),
                        label: Text(tr('Elegir repositorios en GitHub')),
                        onPressed: () =>
                            openLink(githubAppInstallUrl(didactaAppSlug)),
                      ),
                    ],
                  ),
                ],
                // Lo que no se pudo abrir, y por qué: un repositorio que esta
                // cuenta ya no alcanza, o al que la App no tiene acceso.
                if (session.accessProblem != null) ...[
                  const SizedBox(height: 10),
                  Note(
                    '${session.accessProblem}',
                    key: const Key('github-access-problem'),
                    tone: context.palette.teacher,
                  ),
                ],
              ] else
                // No se llega aquí por la puerta, pero sí saliendo desde esta
                // misma pantalla: el fotograma entre pulsar «Salir» y que la
                // aplicación vuelva a la puerta se pinta, y una ficha vacía
                // en ese fotograma sería un parpadeo raro.
                SignInForm(session: session),
            ],
          ),
        ),
      ),
    );
  }
}

/// Los repositorios abiertos: su carpeta, su color y cómo están.
class _ReposSection extends StatefulWidget {
  const _ReposSection({required this.session});

  final Session session;

  @override
  State<_ReposSection> createState() => _ReposSectionState();
}

class _ReposSectionState extends State<_ReposSection> {
  bool _working = false;
  String _doing = '';
  String _progress = '';
  Object? _problem;

  /// El camino de abrir un repositorio vive en `add_repository.dart`: es el
  /// mismo que usa el asistente de bienvenida, y tenerlo dos veces sería
  /// tener dos.
  late final RepositoryAdder _adder = RepositoryAdder(
    session: widget.session,
    onBusy: (working) {
      if (mounted) setState(() => _working = working);
    },
    onStep: (what) {
      if (mounted) {
        setState(() {
          _doing = what;
          _progress = '';
        });
      }
    },
    onProgress: (line) {
      if (mounted) setState(() => _progress = line);
    },
    onProblem: (problem) {
      if (mounted) setState(() => _problem = problem);
    },
  );

  Future<void> _chooseBase() async {
    final chosen = await getDirectoryPath();
    if (chosen == null) return;
    await widget.session.setCloneBase(chosen);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sessionOf(context).settings,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
    final session = widget.session;
    final repos = session.workspace.repos;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (repos.isEmpty)
                Text(
                  tr(
                    'Todavía no hay ninguno. Añade los repositorios de '
                    'contenido con los que trabajes: se clonan en tu disco y se '
                    'ven juntos, aunque una asignatura esté repartida entre '
                    'varios.\n\n'
                    'Si ya tienes uno clonado en el disco, añádelo como carpeta: '
                    'para eso no hace falta entrar en GitHub.',
                  ),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.palette.muted,
                  ),
                ),
              for (final repo in repos) ...[
                _RepoRow(
                  session: session,
                  repo: repo,
                  onRemove: () =>
                      removeRepositoryAsking(context, session, repo),
                ),
                const Divider(height: 18),
              ],
              // En `Wrap` y no en una fila: en una ventana estrecha los dos
              // botones no caben, y una barra que desborda esconde el suyo.
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    key: const Key('add-repository'),
                    onPressed: _working
                        ? null
                        : () => _adder.fromGitHub(context),
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(tr('Añadir desde GitHub')),
                  ),
                  // Y el otro camino hacia lo mismo: una carpeta que ya está
                  // clonada en el disco. Pasa por GitHub igual --se comprueba
                  // de qué repositorio es y si llegas a él-- porque lo que se
                  // abre tiene que poder sincronizarse.
                  OutlinedButton.icon(
                    key: const Key('add-repository-folder'),
                    onPressed: _working
                        ? null
                        : () => _adder.fromFolder(context),
                    icon: const Icon(Icons.folder_open_outlined, size: 16),
                    label: Text(tr('Añadir una carpeta que ya tengo')),
                  ),
                  // Aquí también y no solo en la bienvenida: quien se la
                  // saltó, o quiere enseñarle Didacta a otra persona, lo
                  // busca en Ajustes.
                  OutlinedButton.icon(
                    key: const Key('add-repository-example'),
                    onPressed: _working || !session.signedIn
                        ? null
                        : () => _adder.example(context),
                    icon: const Icon(Icons.auto_stories_outlined, size: 16),
                    label: Text(tr('Probar con un ejemplo')),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: TextButton.icon(
                      onPressed: _chooseBase,
                      icon: const Icon(Icons.folder_outlined, size: 16),
                      label: Text(
                        session.cloneBase.isEmpty
                            ? tr('Elegir dónde se clonan')
                            : tr('Se clonan en {0}', [session.cloneBase]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              if (_working) ...[
                const SizedBox(height: 10),
                Working(step: _doing, line: _progress),
              ],
              if (_problem != null) ...[
                const SizedBox(height: 10),
                Note('$_problem', tone: context.palette.teacher),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Un repositorio en la lista, con su color y su estado.
class _RepoRow extends StatelessWidget {
  const _RepoRow({
    required this.session,
    required this.repo,
    required this.onRemove,
  });

  final Session session;
  final ContentRepo repo;
  final VoidCallback onRemove;

  /// La carpeta en el explorador de archivos. Si no se abre --se movió, o no
  /// hay explorador--, se dice dónde debería estar.
  Future<void> _open(BuildContext context) async {
    if (await session.files.open(repo.directory)) return;
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(tr('No he podido abrir {0}.', [repo.directory]))),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session.repoSync,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
    final status = session.statusOf(repo.id);
    final problem = session.problemOf(repo.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _ColourPicker(
              colour: repo.colour,
              onPicked: (colour) =>
                  session.setRepositoryColour(repo.id, colour),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    repo.id,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    repo.directory,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: context.palette.muted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (status != null)
              Flexible(
                child: Text(
                  [
                    if (status.ahead > 0) tr('{0} sin enviar', [status.ahead]),
                    if (status.behind > 0) tr('{0} por traer', [status.behind]),
                    if (status.dirtyPaths.isNotEmpty)
                      tr('{0} sin guardar', [status.dirtyPaths.length]),
                    if (status.isClean && status.isSynced) tr('al día'),
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.palette.muted,
                  ),
                ),
              ),
            _MaterialCiButton(session: session, repo: repo),
            if (session.files.supported)
              IconButton(
                key: Key('repo-open-${repo.id}'),
                tooltip: session.files.openLabel,
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                onPressed: () => _open(context),
              ),
            IconButton(
              key: Key('repo-remove-${repo.id}'),
              tooltip: tr('Quitarlo de la lista…'),
              icon: const Icon(Icons.close, size: 16),
              onPressed: onRemove,
            ),
          ],
        ),
        if (problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Note('$problem', tone: context.palette.teacher),
          ),
      ],
    );
  }
}

/// Compilar el material en GitHub en cada envío: añadirlo, o ir a ver lo
/// compilado si ya está. Ver `model/material_ci.dart`.
///
/// Por repositorio y aquí, que es donde se decide qué se hace con cada uno.
/// Nada si todavía no se sabe --leer el fichero es un momento-- o si no se
/// puede escribir en él.
class _MaterialCiButton extends StatefulWidget {
  const _MaterialCiButton({required this.session, required this.repo});

  final Session session;
  final ContentRepo repo;

  @override
  State<_MaterialCiButton> createState() => _MaterialCiButtonState();
}

class _MaterialCiButtonState extends State<_MaterialCiButton> {
  late Future<bool?> _has = widget.session.hasMaterialCi(widget.repo.id);

  bool _adding = false;

  Future<void> _add() async {
    final session = widget.session;
    final repo = widget.repo;
    final messenger = ScaffoldMessenger.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Compilar en GitHub en cada cambio')),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'Cada vez que envíes cambios a {0}, GitHub compilará '
                  'todo el material y dejará los PDF para descargar durante '
                  'treinta días, en la pestaña Actions del repositorio.',
                  [repo.id],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                tr(
                  'En dos paquetes separados: «PDF para repartir», que como '
                  'mucho lleva los resultados, y «PDF del profesor», con las '
                  'soluciones, las notas y los exámenes con su corrección.',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                tr(
                  'Gasta minutos de GitHub Actions: los repositorios privados '
                  'tienen unos dos mil al mes sin pagar, y compilar un curso '
                  'entero puede llevar varios. Se añade como un cambio más, '
                  'y para dejar de compilar basta con borrar '
                  '{0}.',
                  [materialWorkflowPath],
                ),
                style: TextStyle(fontSize: 13, color: context.palette.muted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancelar')),
          ),
          FilledButton(
            key: const Key('material-ci-add'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Añadir')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _adding = true);
    try {
      await session.addMaterialCi(repo.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            tr(
              '{0} Compilará en GitHub desde el '
              'próximo envío.',
              [session.saveNotice(repo.id)],
            ),
          ),
        ),
      );
      if (mounted) {
        setState(() => _has = session.hasMaterialCi(repo.id));
      }
    } catch (error) {
      showProblemIn(messenger, error);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool?>(
    future: _has,
    builder: (context, snapshot) {
      final has = snapshot.data;
      final id = widget.repo.id;
      if (_adding) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      if (has == true) {
        return IconButton(
          key: Key('repo-ci-open-$id'),
          tooltip: tr('Compila en GitHub: ver lo compilado'),
          icon: const Icon(Icons.cloud_done_outlined, size: 16),
          onPressed: () => openLink('https://github.com/$id/actions'),
        );
      }
      final session = widget.session;
      if (has == false && session.canWriteIn(id) && !session.isFrozen) {
        return IconButton(
          key: Key('repo-ci-add-$id'),
          tooltip: tr('Compilar en GitHub en cada cambio…'),
          icon: const Icon(Icons.cloud_sync_outlined, size: 16),
          onPressed: _add,
        );
      }
      return const SizedBox.shrink();
    },
  );
}

/// El color de un repositorio.
class _ColourPicker extends StatelessWidget {
  const _ColourPicker({required this.colour, required this.onPicked});

  final int colour;
  final ValueChanged<int> onPicked;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    key: Key('repo-colour-$colour'),
    tooltip: tr('El color con el que se marca en toda la aplicación'),
    onSelected: onPicked,
    itemBuilder: (context) => [
      for (final each in repoColours)
        PopupMenuItem<int>(
          value: each,
          height: 34,
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Color(each),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              if (each == colour) const Icon(Icons.check, size: 14),
            ],
          ),
        ),
    ],
    child: Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: context.palette.repo(colour),
        borderRadius: BorderRadius.circular(4),
      ),
    ),
  );
}

/// Las partes en que se divide una asignatura.
///
/// Un resumen y un botón, no la lista entera: lo que hace falta saber de un
/// vistazo es cuántos hay y si alguno está sin declarar, y lo demás pide una
/// pantalla con sitio. La lleva [BlocksDialog].
class _BlocksSection extends StatelessWidget {
  const _BlocksSection({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final catalogue = session.catalogue;
    final blocks = catalogue.blocksInUse;
    final missing = catalogue.undeclaredBlocks;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'Las partes en que se divide una asignatura: la teoría, los '
                  'problemas, las prácticas. Cada lección dice a cuál '
                  'pertenece, y quien lo declara es el repositorio.',
                ),
                style: TextStyle(fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 10),
              if (blocks.isEmpty)
                Note(tr('Ninguno todavía.'))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final block in blocks)
                      _BlockPill(
                        label: block.title(session.language),
                        count: catalogue.unitsInBlock(block.id).length,
                        declared: block.declared,
                      ),
                  ],
                ),
              if (missing.isNotEmpty) ...[
                const SizedBox(height: 10),
                Note(
                  missing.length == 1
                      ? tr(
                          'Un bloque lo nombra alguna lección y no lo declara '
                          'ningún repositorio abierto. Sus lecciones se ven '
                          'igual, pero el bloque sale por su id.',
                        )
                      : tr(
                          '{0} bloques los nombra alguna lección '
                          'y no los declara ningún repositorio abierto. Sus '
                          'lecciones se ven igual, pero los bloques salen '
                          'por su id.',
                          [missing.length],
                        ),
                  tone: context.palette.teacher,
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    key: const Key('open-blocks'),
                    icon: const Icon(Icons.category_outlined, size: 15),
                    label: Text(tr('Gestionar los bloques')),
                    onPressed: () => showBlocks(context, session),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un bloque en una línea: su nombre, cuánto lleva y si alguien lo declara.
class _BlockPill extends StatelessWidget {
  const _BlockPill({
    required this.label,
    required this.count,
    required this.declared,
  });

  final String label;
  final int count;
  final bool declared;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: context.palette.surface,
      border: Border.all(
        color: declared ? context.palette.rule : context.palette.teacher,
      ),
      borderRadius: BorderRadius.circular(Radii.control),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!declared)
          Padding(
            padding: EdgeInsets.only(right: 4),
            child: Icon(
              Icons.help_outline,
              size: 13,
              color: context.palette.teacher,
            ),
          ),
        Text(label, style: const TextStyle(fontSize: 12.5)),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: TextStyle(fontSize: 11.5, color: context.palette.muted),
        ),
      ],
    ),
  );
}

/// Con qué se compila: las salidas que hay y cuáles están encendidas.
///
/// Un resumen y un botón, como los bloques. Lo que hace falta ver de un
/// vistazo es cuántas se sacan de verdad, porque ese número multiplica cada
/// compilación: un curso de treinta temas con siete versiones encendidas son
/// doscientos diez PDF.
class _TemplatesSection extends StatefulWidget {
  const _TemplatesSection({required this.session});

  final Session session;

  @override
  State<_TemplatesSection> createState() => _TemplatesSectionState();
}

class _TemplatesSectionState extends State<_TemplatesSection> {
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final catalogue = session.catalogue;
    final store = session.templateStore;
    final inProgram = catalogue.templatesInUse
        .where(
          (template) => template.sources.containsKey(Session.programTemplates),
        )
        .length;
    final all = catalogue.templatesInUse;
    final active = catalogue.activeTemplates;
    final declared = all.where((template) => template.declared).length;
    final missing = catalogue.undeclaredTemplates;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'Una plantilla es una salida: qué PDF sale de una lección o '
                  'de un tema. Trae la clase de documento, sus opciones y --si '
                  'quieres-- tu propia cabecera de LaTeX.',
                ),
                style: TextStyle(fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 10),
              _Fact(tr('salidas'), '${all.length}'),
              _Fact(tr('encendidas'), '${active.length}'),
              _Fact(
                tr('declaradas por tus repositorios'),
                declared == 0
                    ? tr('ninguna: se compila con las que trae Didacta')
                    : '$declared',
              ),
              if (missing.isNotEmpty) ...[
                const SizedBox(height: 8),
                Note(
                  tr(
                    'Algo se compila con {0} plantilla(s) que no '
                    'declara ningún repositorio abierto: {1}. '
                    'No se sacan, para no pedirle a LaTeX una salida que no '
                    'existe.',
                    [missing.length, missing.join(', ')],
                  ),
                  tone: context.palette.teacher,
                ),
              ],
              if (inProgram > 0) ...[
                const SizedBox(height: 8),
                Note(
                  tr(
                    '{0} plantilla(s) están guardadas en el programa y '
                    'no en ningún repositorio: no las protege git, no se '
                    'sincronizan y se van con este ordenador. Sácate una copia '
                    'y guárdala donde guardes lo demás.',
                    [inProgram],
                  ),
                  tone: context.palette.teacher,
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    key: const Key('open-templates'),
                    icon: const Icon(Icons.description_outlined, size: 15),
                    label: Text(tr('Gestionar las plantillas')),
                    onPressed: _working
                        ? null
                        : () => showTemplates(context, session),
                  ),
                  if (store != null) ...[
                    OutlinedButton.icon(
                      key: const Key('export-templates'),
                      icon: const Icon(Icons.save_alt, size: 15),
                      label: Text(tr('Copiar a una carpeta')),
                      onPressed: _working ? null : () => _export(store),
                    ),
                    OutlinedButton.icon(
                      key: const Key('import-templates'),
                      icon: const Icon(Icons.file_download_outlined, size: 15),
                      label: Text(tr('Traer de una carpeta')),
                      onPressed: _working ? null : () => _import(store),
                    ),
                  ],
                ],
              ),
              if (store != null) ...[
                const SizedBox(height: 8),
                _Fact(tr('carpeta del programa'), store.directory),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Sacar una copia de las plantillas del programa.
  ///
  /// La carpeta entera y no un fichero comprimido: lo que sale son un
  /// `templates.yaml` y unos `.tex` que se leen y se meten en cualquier
  /// repositorio sin abrir nada.
  Future<void> _export(TemplateStore store) async {
    final messenger = ScaffoldMessenger.of(context);
    final destination = await getDirectoryPath(
      confirmButtonText: tr('Copiar aquí'),
    );
    if (destination == null) return;
    setState(() => _working = true);
    try {
      final copied = await store.exportTo(destination);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            copied == 0
                ? tr('No había nada guardado en el programa.')
                : tr('{0} fichero(s) copiados a {1}.', [copied, destination]),
          ),
        ),
      );
    } catch (error) {
      showProblemIn(messenger, error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Traerlas de una carpeta.
  ///
  /// Lo que ya haya con el mismo nombre se conserva: recuperar una copia
  /// encima de lo que se ha escrito después es la forma más rápida de perder
  /// el trabajo de una tarde.
  Future<void> _import(TemplateStore store) async {
    final messenger = ScaffoldMessenger.of(context);
    final source = await getDirectoryPath(
      confirmButtonText: tr('Traer de aquí'),
    );
    if (source == null) return;
    setState(() => _working = true);
    try {
      final result = await store.importFrom(source);
      await widget.session.loadStoredTemplates();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.copied.isEmpty
                ? tr('Ya estaba todo: no se ha traído nada.')
                : tr(
                    '{0} fichero(s) traídos'
                    '{1}.',
                    [
                      result.copied.length,
                      result.kept.isEmpty
                          ? ''
                          : tr(
                              ', '
                              '{0} ya estaban y se han dejado',
                              [result.kept.length],
                            ),
                    ],
                  ),
          ),
        ),
      );
    } catch (error) {
      showProblemIn(messenger, error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

class _CatalogueSection extends StatelessWidget {
  const _CatalogueSection({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final catalogue = session.catalogue;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Fact(tr('nombre'), catalogue.name),
              _Fact(tr('unidades'), '${catalogue.units.length}'),
              _Fact(tr('asignaturas'), '${catalogue.courses.length}'),
              _Fact(tr('perfiles de salida'), '${catalogue.profiles.length}'),
              _Fact(tr('idiomas'), catalogue.languages.join(', ')),
              // Identifies the content this catalogue describes, so a stale
              // tab can be told from a current one without comparing records.
              _Fact(tr('hash del contenido'), catalogue.contentHash),
              _Fact(tr('origen'), session.catalogueSource.describe),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 15),
                    label: Text(tr('Recargar el catálogo')),
                    onPressed: session.reloadCatalogue,
                  ),
                ],
              ),
              if (catalogue.errors.isNotEmpty) ...[
                const SizedBox(height: 12),
                Note(
                  tr(
                    '{0} problema(s) al leer el '
                    'repositorio:\n{1}',
                    [
                      catalogue.errors.length,
                      catalogue.errors.take(4).join("\n"),
                    ],
                  ),
                  tone: context.palette.teacher,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Poner al día un repositorio escrito antes de que las lecciones tuvieran
/// identidad propia.
///
/// Es una operación **explícita** y no algo que pase al abrir. Escribe una
/// línea en cada `unit.yaml`, y aunque no mueva nada ni cambie contenido, es
/// un cambio en ficheros de alguien: verlo antes y decidirlo es la diferencia
/// entre una migración y una sorpresa.
///
/// Sin nada que poner al día, esta sección no dice «0 pendientes»: no aparece.
/// Un ajuste que solo sirve una vez y se queda ahí para siempre es ruido en
/// una pantalla que se abre a diario.
class _IdentitySection extends StatefulWidget {
  const _IdentitySection({required this.session});

  final Session session;

  @override
  State<_IdentitySection> createState() => _IdentitySectionState();
}

class _IdentitySectionState extends State<_IdentitySection> {
  /// Cuántas lecciones no declaran id, por repositorio. Null mientras se
  /// mira, vacío cuando no falta ninguna.
  Map<String, int>? _pending;
  Object? _problem;

  @override
  void initState() {
    super.initState();
    unawaited(_look());
  }

  Future<void> _look() async {
    final found = <String, int>{};
    try {
      for (final repo in widget.session.workspace.repos) {
        final admin = widget.session.admin(repo: repo.id);
        if (admin == null) continue;
        final output = await admin.previewUnitIds();
        // El número lo dice el motor, y se lee de ahí en lugar de contar las
        // líneas otra vez: el motor es el que sabe escanear el repositorio, y
        // dos recuentos que pueden discrepar son peores que uno.
        final match = RegExp(r'(\d+)\s+lección\(es\)').firstMatch(output);
        final count = int.tryParse(match?.group(1) ?? '') ?? 0;
        if (count > 0) found[repo.id] = count;
      }
    } catch (thrown) {
      if (!mounted) return;
      setState(() => _problem = thrown);
      return;
    }
    if (!mounted) return;
    setState(() => _pending = found);
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    if (_problem == null && (pending == null || pending.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_problem != null)
                Note('$_problem', tone: context.palette.teacher)
              else ...[
                Note(
                  tr(
                    'Estas lecciones se identifican todavía por su ruta. Con un '
                    'id propio, mover una de carpeta deja de romper quién la '
                    'usa, y «este material, ¿dónde más está?» tiene respuesta '
                    'aunque se reorganice `content/`.\n\n'
                    'Poner los ids escribe una línea `id:` en cada `unit.yaml` '
                    'que no la tenga. No mueve nada, no renombra nada y no toca '
                    'el contenido. El id se deriva de la ruta con un hash, así '
                    'que sale el mismo lo haga quien lo haga: quien lo ponga al '
                    'día en otro ordenador escribe exactamente esto.',
                  ),
                ),
                const SizedBox(height: 10),
                for (final entry in (pending ?? const <String, int>{}).entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr('{0}: {1} lección(es) sin id', [
                              entry.key,
                              entry.value,
                            ]),
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        OutlinedButton.icon(
                          key: Key('write-ids-${entry.key}'),
                          icon: const Icon(Icons.tag, size: 15),
                          label: Text(tr('Ponerlos')),
                          onPressed: () => _write(entry.key, entry.value),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _write(String repo, int count) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('¿Poner los ids?')),
        content: SizedBox(
          width: 480,
          child: Note(
            tr(
              'Se escribirá una línea `id:` en {0} `unit.yaml` de {1}, y '
              'nada más: ni se mueve una carpeta, ni se renombra un fichero, ni '
              'se toca una línea de LaTeX.\n\n'
              'Queda como un cambio aparte en el historial, así que se puede '
              'leer y deshacer de una pieza.',
              [count, repo],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancelar')),
          ),
          FilledButton(
            key: const Key('confirm-write-ids'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Ponerlos')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final ok = await runAdmin(
      context,
      widget.session,
      (admin) => admin.writeUnitIds(),
      done: tr('Ids puestos en {0} lección(es).', [count]),
      repo: repo,
    );
    if (!ok || !mounted) return;
    await widget.session.reloadCatalogue();
    if (!mounted) return;
    setState(() => _pending = null);
    await _look();
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 132,
          child: Text(
            label,
            style: TextStyle(fontSize: 11.5, color: context.palette.muted),
          ),
        ),
        Expanded(
          child: SelectableText(value, style: const TextStyle(fontSize: 12.5)),
        ),
      ],
    ),
  );
}

/// Qué hay instalado en la máquina, y el botón para lo que falte.
///
/// La misma lista que la bienvenida, y a propósito: aquí se vuelve el día que
/// algo deja de funcionar --se ha cambiado de ordenador, alguien ha borrado
/// TeX, el motor estaba en una carpeta que ya no existe-- y lo que hace falta
/// entonces es exactamente lo mismo que la primera vez.
///
/// Encima de «Compilar» porque es lo que se mira primero: si falta LaTeX, la
/// ruta del motor no es el problema de nadie.
class _ToolsSection extends StatelessWidget {
  const _ToolsSection({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: ToolchainCheck(session: session, foldWhenReady: true),
  );
}

class _EngineSection extends StatefulWidget {
  const _EngineSection({required this.session});

  final Session session;

  @override
  State<_EngineSection> createState() => _EngineSectionState();
}

class _EngineSectionState extends State<_EngineSection> {
  bool _busy = false;
  CompilerStatus? _status;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_check);
  }

  Future<void> _check() async {
    final compiler = widget.session.compiler();
    if (compiler == null) {
      if (mounted) setState(() => _status = null);
      return;
    }
    final status = await compiler.status();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _choose() async {
    final chosen = await getDirectoryPath(
      confirmButtonText: tr('Usar este motor'),
    );
    if (chosen == null) return;
    setState(() => _busy = true);
    await widget.session.setEnginePath(chosen);
    if (mounted) setState(() => _busy = false);
    await _check();
  }

  /// Decir dónde está TeX, para una instalación en un sitio raro.
  ///
  /// Casi nunca hace falta: se busca en los sitios de siempre. Está porque
  /// el caso que no se puede adivinar --TinyTeX en una carpeta cualquiera,
  /// un MiKTeX portátil-- deja la aplicación sin compilar y sin salida.
  Future<void> _chooseTex() async {
    final chosen = await getDirectoryPath(
      confirmButtonText: tr('Usar este TeX'),
    );
    if (chosen == null) return;
    setState(() => _busy = true);
    await widget.session.setTexPath(chosen);
    if (mounted) setState(() => _busy = false);
    await _check();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      sessionOf(context).settings,
      sessionOf(context).engine,
    ]),
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
    final session = widget.session;
    final path = session.enginePath;
    final status = _status;
    // En Esencial, con todo en su sitio, sobran la ruta y los botones de
    // cambiarla: son para quien tiene más de un motor. Si algo falla, sale
    // todo, que es lo que hace falta para arreglarlo.
    final plain =
        !session.completeInterface &&
        path != null &&
        (status?.ready ?? false) &&
        session.texPath == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (path == null)
                Text(
                  tr(
                    'Sin motor. Compilar una unidad usa `didacta preview`, que '
                    'vive en el repositorio de la aplicación: el que tiene '
                    '`cli/didacta`.',
                  ),
                  style: TextStyle(fontSize: 12.5),
                )
              else ...[
                if (!plain) ...[
                  SelectableText(
                    path,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (status == null)
                  Text(
                    tr('Comprobando…'),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
                    ),
                  )
                else if (status.ready)
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 15,
                        color: context.palette.accentDark,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          tr(
                            'Listo: el motor y latexmk están donde hacen falta.',
                          ),
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  )
                else
                  // Con el motivo, no un «no disponible»: lo que falta suele
                  // ser latexmk, y eso se arregla en un minuto sabiéndolo.
                  Note(
                    status.problem ?? tr('No se puede compilar.'),
                    tone: context.palette.teacher,
                  ),
                if (session.engineVersion case final version?) ...[
                  const SizedBox(height: 6),
                  EngineVersionLine(
                    version: version,
                    onPin: session.pinEngineNow,
                  ),
                ],
              ],
              if (!plain) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open_outlined, size: 16),
                      label: Text(
                        path == null ? tr('Elegir el motor') : tr('Cambiar'),
                      ),
                      onPressed: _busy ? null : _choose,
                    ),
                    if (path != null)
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                await session.setEnginePath(null);
                                await _check();
                              },
                        child: Text(tr('Olvidarlo')),
                      ),
                    // Solo cuando hace falta: mientras TeX se encuentre, este
                    // botón sería una decisión que nadie tiene que tomar.
                    if (status != null && !status.ready ||
                        session.texPath != null)
                      OutlinedButton.icon(
                        key: const Key('choose-tex'),
                        icon: const Icon(Icons.functions, size: 16),
                        label: Text(
                          session.texPath == null
                              ? tr('Decir dónde está TeX')
                              : tr('Cambiar TeX'),
                        ),
                        onPressed: _busy ? null : _chooseTex,
                      ),
                    if (session.texPath != null)
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                await session.setTexPath(null);
                                await _check();
                              },
                        child: Text(tr('Buscar TeX solo')),
                      ),
                  ],
                ),
                if (session.texPath != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    'TeX: ${session.texPath}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 14),
              // Cuántas versiones de un documento se compilan a la vez. Lo de
              // salida vale casi siempre; se toca en un portátil que se
              // calienta, o en uno con muchos núcleos que va sobrado.
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Compilaciones a la vez'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          tr(
                            'Cuántas versiones de un documento se compilan al '
                            'mismo tiempo. Más es más rápido y deja el ordenador '
                            'más ocupado mientras dura.',
                          ),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: context.palette.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    key: const Key('build-jobs'),
                    value: session.buildJobs,
                    items: [
                      DropdownMenuItem(
                        value: 0,
                        child: Text(tr('Automático (la mitad de los núcleos)')),
                      ),
                      for (final jobs in const [1, 2, 3, 4])
                        DropdownMenuItem(
                          value: jobs,
                          child: Text(jobs == 1 ? tr('Una') : '$jobs'),
                        ),
                    ],
                    onChanged: (value) => session.setBuildJobs(value ?? 0),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Solo el panel de un documento: los lotes compilan siempre
              // enteros, que son lo que se reparte.
              SwitchListTile(
                key: const Key('quick-build'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: session.quickBuild,
                onChanged: session.setQuickBuild,
                title: Text(
                  tr('Vista rápida'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  tr(
                    'Compilar un documento desde su pantalla en una sola '
                    'pasada, para ver cómo queda: tarda la mitad, y el índice y '
                    'las referencias pueden no estar al día. Al lado queda '
                    '«Compilar entero», y compilar un tema o un curso es '
                    'siempre entero.',
                  ),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.palette.muted,
                  ),
                ),
              ),
              // De las diapositivas que se salen se avisa siempre; de las
              // líneas de los apuntes, si se pide: muchas se salen a
              // propósito --una figura más ancha que el texto--.
              SwitchListTile(
                key: const Key('overfull-lines'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: session.overfullLines,
                onChanged: session.setOverfullLines,
                title: Text(
                  tr('Avisar de las líneas que se salen en los apuntes'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  tr(
                    'Las que pasan del margen derecho más de 5 pt, con su '
                    'lección y su línea. De las diapositivas que se salen por '
                    'abajo se avisa siempre.',
                  ),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.palette.muted,
                  ),
                ),
              ),
              // Para quien reparte a alguien que lee con un lector de
              // pantalla. Apagado de salida: compila con LuaLaTeX y tarda
              // el doble.
              SwitchListTile(
                key: const Key('accessible-pdf'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: session.accessiblePdf,
                onChanged: session.setAccessiblePdf,
                title: Text(
                  tr('PDF accesibles'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  tr(
                    'Los apuntes, las hojas y los exámenes, etiquetados: con su '
                    'estructura, su idioma y el texto alternativo de las '
                    'figuras, para leerlos con un lector de pantalla (PDF/UA). '
                    'Compila con LuaLaTeX y tarda el doble. Las diapositivas '
                    'salen como siempre: LaTeX todavía no sabe etiquetarlas.',
                  ),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.palette.muted,
                  ),
                ),
              ),
              // Para irse a otra ventana mientras compila un curso entero.
              // Con Didacta delante no sale nada: el resultado ya está ahí.
              if (session.notifier.supported)
                SwitchListTile(
                  key: const Key('notify-when-built'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: session.notifyWhenBuilt,
                  onChanged: session.setNotifyWhenBuilt,
                  title: Text(
                    tr('Avisar al terminar de compilar'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    tr(
                      'Con una notificación del sistema, si mientras tanto te '
                      'has ido a otra ventana: si ha salido bien o cuántos '
                      'documentos tienen errores. Con Didacta delante no avisa, '
                      'porque ya se ve.',
                    ),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.palette.muted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Los campos en los que dos repositorios no dicen lo mismo.
///
/// En Ajustes y no en un aviso flotante: no es urgente --el material se sigue
/// pudiendo dar-- pero tampoco se arregla solo, y dejarlo en un mensaje que
/// se cierra significa no arreglarlo nunca. Aquí está cuando se busca.
/// Qué pasa al guardar un fichero.
///
/// Dos decisiones, y son distintas. **Confirmar** es dejar el cambio anotado
/// en el historial con un mensaje; **enviar** es que lo vea el resto. Se
/// pueden querer por separado: hay quien confirma cada guardado y envía una
/// vez al terminar la tarde, y quien quiere que todo llegue solo.
///
/// Las dos puestas de salida, que es lo que quiere quien no se ha parado a
/// pensar en esto: escribes, se guarda, está en GitHub. El paso de «ahora
/// escribe un mensaje de commit» se salta treinta veces al día, y eso es lo
/// que lo hace transparente.
class _SavingSection extends StatefulWidget {
  const _SavingSection({required this.session});

  final Session session;

  @override
  State<_SavingSection> createState() => _SavingSectionState();
}

class _SavingSectionState extends State<_SavingSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sessionOf(context).settings,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
    final session = widget.session;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                key: const Key('commit-on-save'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: session.commitOnSave,
                onChanged: _busy
                    ? null
                    : (on) => _set(() => session.setCommitOnSave(on)),
                title: Text(
                  tr('Guardar lo deja en el historial'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  session.commitOnSave
                      ? tr(
                          'Cada guardado queda en el historial con su mensaje, '
                          'sin preguntar nada.',
                        )
                      : tr(
                          'Lo que guardas se queda escrito, fuera del historial. '
                          'El botón de la barra de arriba lo guarda en él '
                          'cuando quieras, con el mensaje que le pongas.',
                        ),
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              SwitchListTile(
                key: const Key('review-before-save'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: session.reviewBeforeSave,
                onChanged: _busy
                    ? null
                    : (on) => _set(() => session.setReviewBeforeSave(on)),
                title: Text(
                  tr('Revisar los cambios antes de guardar'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  session.reviewBeforeSave
                      ? tr(
                          'Cada guardado enseña lo que cambia y pide el mensaje '
                          'antes de dejarlo en el historial.',
                        )
                      : tr(
                          'Se guarda con el mensaje que propone Didacta, que '
                          'dice qué se cambió. Lo que cambió se ve en «Ver '
                          'cambios», en el aviso, y en el historial.',
                        ),
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              SwitchListTile(
                key: const Key('push-on-commit'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: session.pushOnCommit,
                onChanged: _busy
                    ? null
                    : (on) => _set(() => session.setPushOnCommit(on)),
                title: Text(
                  tr('Y se envía a GitHub'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  session.pushOnCommit
                      ? tr(
                          'En cuanto se guarda. Nada se queda solo en esta '
                          'máquina.',
                        )
                      : tr(
                          'Los cambios se quedan aquí hasta que le des a '
                          'enviar. Lo que no has enviado no lo ve nadie, ni '
                          'está en otro sitio si se rompe el disco.',
                        ),
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              if (!session.commitOnSave && !session.pushOnCommit) ...[
                const SizedBox(height: 6),
                Note(
                  tr(
                    'Con las dos apagadas, lo que escribes está solo en esta '
                    'carpeta hasta que lo guardes y lo envíes a mano. Es una forma '
                    'legítima de trabajar, pero conviene saberlo.',
                  ),
                  tone: context.palette.teacher,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _set(Future<void> Function() change) async {
    setState(() => _busy = true);
    try {
      await change();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// El interruptor del servidor MCP, y en qué puede escribir.
///
/// Dos decisiones y no una, porque son distintas. Encenderlo es dejar que un
/// modelo **lea** tu material, que es inocuo y es casi todo el valor: preguntar
/// qué unidades hay sin traducir, buscar dónde se define algo. Dejarle
/// **escribir** es otra cosa, y por eso se marca repositorio a repositorio y
/// empieza sin ninguno marcado.
///
/// Nada de esto se enciende solo al abrir Didacta salvo que ya estuviera
/// encendido: es una decisión de la persona, no algo que se herede de una
/// instalación.
class _McpSection extends StatefulWidget {
  const _McpSection({required this.session});

  final Session session;

  @override
  State<_McpSection> createState() => _McpSectionState();
}

class _McpSectionState extends State<_McpSection> {
  Set<String> _writable = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_load);
  }

  Future<void> _load() async {
    final stored = await widget.session.preferences.mcpWritable();
    if (!mounted) return;
    setState(() {
      _writable = stored.toSet();
      _loaded = true;
    });
  }

  List<McpRepository> get _repositories => [
    for (final repo in widget.session.workspace.repos)
      if ((widget.session.pathOf(repo.id) ?? '').isNotEmpty)
        McpRepository(
          id: repo.id,
          directory: widget.session.pathOf(repo.id)!,
          writable: _writable.contains(repo.id),
        ),
  ];

  @override
  Widget build(BuildContext context) {
    final service = context.watch<McpService>();
    final repositories = _repositories;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'Deja que un modelo de lenguaje trabaje sobre tu material: '
                  'leer las asignaturas, buscar en la biblioteca, escribir una '
                  'traducción y comprobar que compila. Sirve para lo que se '
                  'hace a mano y no tiene gracia.',
                ),
                style: TextStyle(fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('mcp-switch'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: service.running || service.state == McpState.starting,
                onChanged: repositories.isEmpty || !_loaded
                    ? null
                    : (on) => _toggle(service, on),
                title: Text(
                  tr('Servidor MCP'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  switch (service.state) {
                    McpState.running => tr(
                      'En marcha en {0}. Se apaga al cerrar '
                      'Didacta.',
                      [service.url],
                    ),
                    McpState.starting => tr('Encendiendo…'),
                    McpState.failed =>
                      service.problem ?? tr('No se pudo encender.'),
                    McpState.off =>
                      repositories.isEmpty
                          ? tr('Hace falta algún repositorio abierto.')
                          : tr('Apagado. Escucha solo en esta máquina.'),
                  },
                  style: TextStyle(
                    fontSize: 11.5,
                    color: service.state == McpState.failed
                        ? context.palette.ex
                        : context.palette.muted,
                  ),
                ),
              ),
              if (service.running)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('mcp-open'),
                    icon: const Icon(Icons.hub_outlined, size: 15),
                    label: Text(tr('Ver qué está haciendo')),
                    onPressed: () => goTo(context, Routes.mcp()),
                  ),
                ),
              const Divider(height: 18),
              Text(
                tr('Dónde puede escribir'),
                style: TextStyle(fontSize: 11.5, color: context.palette.muted),
              ),
              const SizedBox(height: 2),
              Text(
                tr(
                  'Sin marcar ninguno solo lee, que ya es casi todo el valor y '
                  'no puede estropear nada. Lo que escriba queda en disco y lo '
                  'envías tú, viendo qué cambia: no hay ninguna herramienta que '
                  'guarde en el historial.',
                ),
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: context.palette.muted,
                ),
              ),
              const SizedBox(height: 4),
              if (widget.session.workspace.repos.isEmpty)
                Note(tr('No hay repositorios abiertos.'))
              else
                for (final repo in widget.session.workspace.repos)
                  CheckboxListTile(
                    key: Key('mcp-writable-${repo.id}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _writable.contains(repo.id),
                    // Con el servidor en marcha no: los repositorios se le
                    // dan al arrancar, así que marcar aquí no cambiaría nada
                    // y la casilla estaría mintiendo.
                    onChanged:
                        service.running || !widget.session.canWriteIn(repo.id)
                        ? null
                        : (on) => _setWritable(repo.id, on ?? false),
                    title: Text(
                      repo.label,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    subtitle: !widget.session.canWriteIn(repo.id)
                        ? Text(
                            tr(
                              'No puedes escribir en él, así que el servidor '
                              'tampoco',
                            ),
                            style: TextStyle(fontSize: 11),
                          )
                        : null,
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setWritable(String repo, bool on) async {
    setState(() {
      if (on) {
        _writable.add(repo);
      } else {
        _writable.remove(repo);
      }
    });
    await widget.session.preferences.setMcpWritable(_writable.toList()..sort());
  }

  Future<void> _toggle(McpService service, bool on) async {
    await widget.session.preferences.setMcpEnabled(on);
    if (on) {
      await service.start(repositories: _repositories);
    } else {
      await service.stop();
    }
  }
}
