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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/browser.dart';
import '../data/compiler.dart';
import '../model/workspace.dart';
import '../router.dart';
import '../data/mcp_process.dart';
import '../state/mcp_service.dart';
import '../state/session.dart';
import 'shell.dart';
import 'sign_in.dart';
import 'add_repository.dart';
import 'theme.dart';
import 'tour.dart';
import 'translation_settings.dart';
import 'update_section.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);

    return Column(
      children: [
        const PageHeader(
          title: 'Ajustes',
          subtitle: 'Tu cuenta, tus repositorios y qué hay cargado',
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 28),
            children: [
              const SectionLabel('Cuenta de GitHub'),
              _AccountSection(session: session),

              const SectionLabel('Repositorios'),
              _ReposSection(session: session),

              const SectionLabel('Al guardar'),
              _SavingSection(session: session),

              if (session.canCompile) ...[
                const SectionLabel('Compilar'),
                _EngineSection(session: session),
              ],

              const SectionLabel('Traducción automática'),
              TranslationSection(secrets: session.translationSecrets),

              const SectionLabel('Servidor MCP'),
              _McpSection(session: session),

              const SectionLabel('Mis preferencias'),
              _PrefsSection(session: session),

              const SectionLabel('Catálogo'),
              _CatalogueSection(session: session),

              const SectionLabel('Actualizaciones'),
              const UpdateSection(),

              const SectionLabel('Ayuda'),
              _HelpSection(session: session),
            ],
          ),
        ),
      ],
    );
  }
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'La presentación explica qué es Didacta y deja la configuración '
              'hecha. El recorrido señala las partes de la ventana, sobre la '
              'aplicación y sin cambiar nada.',
              style: TextStyle(fontSize: 12.5, color: didactaMuted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  key: const Key('replay-welcome'),
                  icon: const Icon(Icons.slideshow_outlined, size: 16),
                  label: const Text('Volver a ver la presentación'),
                  onPressed: session.replayWelcome,
                ),
                OutlinedButton.icon(
                  key: const Key('replay-tour'),
                  icon: const Icon(Icons.explore_outlined, size: 16),
                  label: const Text('Ver el recorrido guiado'),
                  // Sin esperar a nada: los objetivos del tour están en el
                  // armazón, que ya está en pie porque esta pantalla vive
                  // dentro de él.
                  onPressed: context.read<TourController>().start,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.menu_book_outlined, size: 16),
                  label: const Text('La documentación'),
                  onPressed: () => openLink(didactaDocs),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
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
  Widget build(BuildContext context) {
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
              const Text(
                'Lo que decides sobre el material --qué temas tienes '
                'plegados-- puede seguirte de un ordenador a otro. Se guarda '
                'en el repositorio que elijas, en un fichero con tu nombre de '
                'GitHub, así que podéis compartir repositorio sin pisaros.',
                style: TextStyle(fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 10),
              if (repos.isEmpty)
                const Note(
                  'Sin repositorios abiertos no hay dónde guardarlas. '
                  'Se quedan en esta máquina.',
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
                        title: const Text(
                          'Solo en este ordenador',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      for (final repo in repos)
                        RadioListTile<String?>(
                          key: Key('prefs-repo-\${repo.id}'),
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
                    path ?? 'hace falta haber entrado en GitHub',
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        key: const Key('prefs-sync-now'),
                        icon: const Icon(Icons.sync, size: 15),
                        label: const Text('Guardarlas ahora'),
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
                            ? 'Sesión iniciada en GitHub'
                            : '${user.authorName} (${user.login})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      key: const Key('github-sign-out'),
                      onPressed: session.signOut,
                      child: const Text('Salir'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  user == null
                      ? 'Salir cierra la sesión en esta máquina. Los clones '
                            'se quedan: son carpetas con el trabajo dentro.'
                      : 'Los commits se firman como ${user.authorEmail}. Los '
                            'permisos son los de GitHub: se puede escribir '
                            'donde GitHub deje escribir.',
                  style: const TextStyle(fontSize: 12, color: didactaMuted),
                ),
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
  Widget build(BuildContext context) {
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
                const Text(
                  'Todavía no hay ninguno. Añade los repositorios de '
                  'contenido con los que trabajes: se clonan en tu disco y se '
                  'ven juntos, aunque una asignatura esté repartida entre '
                  'varios.\n\n'
                  'Si ya tienes uno clonado en el disco, añádelo como carpeta: '
                  'para eso no hace falta entrar en GitHub.',
                  style: TextStyle(fontSize: 12.5, color: didactaMuted),
                ),
              for (final repo in repos) ...[
                _RepoRow(
                  session: session,
                  repo: repo,
                  onRemove: () => session.removeRepository(repo.id),
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
                    label: const Text('Añadir desde GitHub'),
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
                    label: const Text('Añadir un clon del disco'),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: TextButton.icon(
                      onPressed: _chooseBase,
                      icon: const Icon(Icons.folder_outlined, size: 16),
                      label: Text(
                        session.cloneBase.isEmpty
                            ? 'Elegir dónde se clonan'
                            : 'Se clonan en ${session.cloneBase}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              if (_working) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _progress,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          color: didactaMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (_problem != null) ...[
                const SizedBox(height: 10),
                Note('$_problem', tone: didactaTeacher),
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

  @override
  Widget build(BuildContext context) {
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
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: didactaMuted,
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
                    if (status.ahead > 0) '${status.ahead} sin enviar',
                    if (status.behind > 0) '${status.behind} por traer',
                    if (status.dirtyPaths.isNotEmpty)
                      '${status.dirtyPaths.length} sin guardar',
                    if (status.isClean && status.isSynced) 'al día',
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: didactaMuted),
                ),
              ),
            IconButton(
              tooltip: 'Quitarlo de la lista (la carpeta se queda)',
              icon: const Icon(Icons.close, size: 16),
              onPressed: onRemove,
            ),
          ],
        ),
        if (problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Note('$problem', tone: didactaTeacher),
          ),
      ],
    );
  }
}

/// El color de un repositorio.
class _ColourPicker extends StatelessWidget {
  const _ColourPicker({required this.colour, required this.onPicked});

  final int colour;
  final ValueChanged<int> onPicked;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    key: Key('repo-colour-$colour'),
    tooltip: 'El color con el que se marca en toda la aplicación',
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
        color: Color(colour),
        borderRadius: BorderRadius.circular(4),
      ),
    ),
  );
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
              _Fact('nombre', catalogue.name),
              _Fact('unidades', '${catalogue.units.length}'),
              _Fact('asignaturas', '${catalogue.courses.length}'),
              _Fact('perfiles de salida', '${catalogue.profiles.length}'),
              _Fact('idiomas', catalogue.languages.join(', ')),
              // Identifies the content this catalogue describes, so a stale
              // tab can be told from a current one without comparing records.
              _Fact('hash del contenido', catalogue.contentHash),
              _Fact('origen', session.catalogueSource.describe),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 15),
                    label: const Text('Recargar el catálogo'),
                    onPressed: session.reloadCatalogue,
                  ),
                ],
              ),
              if (catalogue.errors.isNotEmpty) ...[
                const SizedBox(height: 12),
                Note(
                  '${catalogue.errors.length} problema(s) al leer el '
                  'repositorio:\n${catalogue.errors.take(4).join("\n")}',
                  tone: didactaTeacher,
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
            style: const TextStyle(fontSize: 11.5, color: didactaMuted),
          ),
        ),
        Expanded(
          child: SelectableText(value, style: const TextStyle(fontSize: 12.5)),
        ),
      ],
    ),
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
    final chosen = await getDirectoryPath(confirmButtonText: 'Usar este motor');
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
    final chosen = await getDirectoryPath(confirmButtonText: 'Usar este TeX');
    if (chosen == null) return;
    setState(() => _busy = true);
    await widget.session.setTexPath(chosen);
    if (mounted) setState(() => _busy = false);
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final path = session.enginePath;
    final status = _status;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (path == null)
                const Text(
                  'Sin motor. Compilar una unidad usa `didacta preview`, que '
                  'vive en el repositorio de la aplicación: el que tiene '
                  '`cli/didacta`.',
                  style: TextStyle(fontSize: 12.5),
                )
              else ...[
                SelectableText(
                  path,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                if (status == null)
                  const Text(
                    'Comprobando…',
                    style: TextStyle(fontSize: 12, color: didactaMuted),
                  )
                else if (status.ready)
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 15,
                        color: didactaAccentDark,
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Listo: el motor y latexmk están donde hacen falta.',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  )
                else
                  // Con el motivo, no un «no disponible»: lo que falta suele
                  // ser latexmk, y eso se arregla en un minuto sabiéndolo.
                  Note(
                    status.problem ?? 'No se puede compilar.',
                    tone: didactaTeacher,
                  ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open_outlined, size: 16),
                    label: Text(path == null ? 'Elegir el motor' : 'Cambiar'),
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
                      child: const Text('Olvidarlo'),
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
                            ? 'Decir dónde está TeX'
                            : 'Cambiar TeX',
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
                      child: const Text('Buscar TeX solo'),
                    ),
                ],
              ),
              if (session.texPath != null) ...[
                const SizedBox(height: 8),
                SelectableText(
                  'TeX: ${session.texPath}',
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ],
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
  Widget build(BuildContext context) {
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
                title: const Text(
                  'Guardar deja el cambio confirmado',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  session.commitOnSave
                      ? 'Cada guardado es un commit con su mensaje, sin '
                            'preguntar nada.'
                      : 'Lo que guardas se queda escrito y sin confirmar. El '
                            'botón de la barra de arriba lo confirma cuando '
                            'quieras, con el mensaje que le pongas.',
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
                title: const Text(
                  'Y se envía a GitHub',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  session.pushOnCommit
                      ? 'En cuanto se confirma. Nada se queda solo en esta '
                            'máquina.'
                      : 'Los commits se quedan aquí hasta que le des a '
                            'enviar. Lo que no has enviado no lo ve nadie, ni '
                            'está en otro sitio si se rompe el disco.',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              if (!session.commitOnSave && !session.pushOnCommit) ...[
                const SizedBox(height: 6),
                const Note(
                  'Con las dos apagadas, lo que escribes está solo en esta '
                  'carpeta hasta que confirmes y envíes a mano. Es una forma '
                  'legítima de trabajar, pero conviene saberlo.',
                  tone: didactaTeacher,
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
              const Text(
                'Deja que un modelo de lenguaje trabaje sobre tu material: '
                'leer las asignaturas, buscar en la biblioteca, escribir una '
                'traducción y comprobar que compila. Sirve para lo que se '
                'hace a mano y no tiene gracia.',
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
                title: const Text(
                  'Servidor MCP',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  switch (service.state) {
                    McpState.running =>
                      'En marcha en ${service.url}. Se apaga al cerrar '
                          'Didacta.',
                    McpState.starting => 'Encendiendo…',
                    McpState.failed =>
                      service.problem ?? 'No se pudo encender.',
                    McpState.off =>
                      repositories.isEmpty
                          ? 'Hace falta algún repositorio abierto.'
                          : 'Apagado. Escucha solo en esta máquina.',
                  },
                  style: TextStyle(
                    fontSize: 11.5,
                    color: service.state == McpState.failed
                        ? didactaEx
                        : didactaMuted,
                  ),
                ),
              ),
              if (service.running)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('mcp-open'),
                    icon: const Icon(Icons.hub_outlined, size: 15),
                    label: const Text('Ver qué está haciendo'),
                    onPressed: () => goTo(context, Routes.mcp()),
                  ),
                ),
              const Divider(height: 18),
              const Text(
                'Dónde puede escribir',
                style: TextStyle(fontSize: 11.5, color: didactaMuted),
              ),
              const SizedBox(height: 2),
              const Text(
                'Sin marcar ninguno solo lee, que ya es casi todo el valor y '
                'no puede estropear nada. Lo que escriba queda en disco y lo '
                'envías tú, viendo el diff: no hay ninguna herramienta que '
                'haga commit.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: didactaMuted,
                ),
              ),
              const SizedBox(height: 4),
              if (widget.session.workspace.repos.isEmpty)
                const Note('No hay repositorios abiertos.')
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
                        ? const Text(
                            'No puedes escribir en él, así que el servidor '
                            'tampoco',
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
