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
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/compiler.dart';
import '../data/github.dart';
import '../model/workspace.dart';
import '../router.dart';
import '../state/session.dart';
import '../state/update_service.dart';
import 'shell.dart';
import 'theme.dart';
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

              if (session.canCompile) ...[
                const SectionLabel('Compilar'),
                _EngineSection(session: session),
              ],

              const SectionLabel('Catálogo'),
              _CatalogueSection(session: session),

              const SectionLabel('Actualizaciones'),
              const UpdateSection(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Entrar en GitHub, y con qué aplicación de OAuth.
class _AccountSection extends StatefulWidget {
  const _AccountSection({required this.session});

  final Session session;

  @override
  State<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<_AccountSection> {
  late final TextEditingController _clientId = TextEditingController(
    text: widget.session.githubClientId,
  );
  bool _working = false;
  Object? _problem;

  @override
  void dispose() {
    _clientId.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final clientId = _clientId.text.trim();
    if (clientId.isEmpty) {
      setState(
        () => _problem =
            'Falta el Client ID de la OAuth App. Créala en GitHub '
            '(Settings → Developer settings → OAuth Apps) con «Enable '
            'Device Flow» marcado, y pega aquí su Client ID.',
      );
      return;
    }
    await widget.session.setGithubClientId(clientId);

    setState(() {
      _working = true;
      _problem = null;
    });
    final auth = GitHubAuth(clientId: clientId);
    try {
      final code = await auth.start();
      if (!mounted) return;
      // El código, delante y con el enlace: la contraseña se teclea en
      // github.com y en ningún otro sitio, que es la única forma honesta de
      // pedirla.
      final waiting = showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _DeviceCodeDialog(code: code),
      );
      final token = await auth.waitForToken(code);
      await widget.session.signIn(token);
      if (!mounted) return;
      // Y acto seguido, la otra pregunta: si esta cuenta llega al repositorio
      // de versiones. Son dos cosas distintas y alguien puede pasar la
      // primera y no la segunda.
      unawaited(context.read<UpdateService>().checkAuthorisation());
      Navigator.of(context, rootNavigator: true).pop();
      await waiting;
    } catch (thrown) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
        setState(() => _problem = thrown);
      }
    } finally {
      auth.close();
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final user = session.user;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (user != null) ...[
                Row(
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${user.authorName} (${user.login})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      key: const Key('github-sign-out'),
                      onPressed: () {
                        // Lo que se sabía de esta cuenta deja de valer: la
                        // siguiente puede ser otra con otros permisos.
                        context.read<UpdateService>().forgetAccount();
                        session.signOut();
                      },
                      child: const Text('Salir'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Los commits se firman como ${user.authorEmail}. Los '
                  'permisos son los de GitHub: se puede escribir donde GitHub '
                  'deje escribir.',
                  style: const TextStyle(fontSize: 12, color: didactaMuted),
                ),
              ] else ...[
                const Text(
                  'Entra en GitHub para traer repositorios, y para que los '
                  'commits salgan con tu nombre.',
                  style: TextStyle(fontSize: 12.5, color: didactaMuted),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('github-client-id'),
                  controller: _clientId,
                  decoration: const InputDecoration(
                    labelText: 'Client ID de la OAuth App',
                    helperText:
                        'GitHub → Settings → Developer settings → OAuth Apps, '
                        'con «Enable Device Flow». Es público: no es un '
                        'secreto que haya que proteger.',
                    helperMaxLines: 3,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const Key('github-sign-in'),
                  onPressed: _working ? null : _signIn,
                  icon: _working
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login, size: 16),
                  label: Text(_working ? 'Esperando…' : 'Entrar en GitHub'),
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

/// El código del device flow, mientras se espera.
class _DeviceCodeDialog extends StatelessWidget {
  const _DeviceCodeDialog({required this.code});

  final DeviceCode code;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Autoriza Didacta en GitHub'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Abre ${code.verificationUri} y escribe este código:'),
        const SizedBox(height: 12),
        SelectableText(
          code.userCode,
          style: const TextStyle(
            fontSize: 26,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Esta ventana se cierra sola en cuanto lo autorices.',
          style: TextStyle(fontSize: 12, color: didactaMuted),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Clipboard.setData(ClipboardData(text: code.userCode)),
        child: const Text('Copiar el código'),
      ),
      FilledButton(
        onPressed: () =>
            Clipboard.setData(ClipboardData(text: code.verificationUri)),
        child: const Text('Copiar el enlace'),
      ),
    ],
  );
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

  Future<void> _add() async {
    final session = widget.session;
    if (!session.signedIn) {
      setState(() => _problem = 'Entra en GitHub primero.');
      return;
    }
    final chosen = await showDialog<GitHubRepo>(
      context: context,
      builder: (context) => _RepoPicker(session: session),
    );
    if (chosen == null || !mounted) return;

    setState(() {
      _working = true;
      _problem = null;
      _progress = 'Clonando ${chosen.id}…';
    });
    try {
      await session.addRepository(
        owner: chosen.owner,
        name: chosen.name,
        branch: chosen.defaultBranch,
        onProgress: (line) {
          if (mounted) setState(() => _progress = line);
        },
      );
    } catch (thrown) {
      if (mounted) setState(() => _problem = thrown);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Añadir una carpeta que ya está en el disco.
  ///
  /// Sin pasar por GitHub: de qué repositorio es lo dice su propio remoto. Es
  /// lo que hace que un clon que ya tenías siga sirviendo, y lo que deja
  /// trabajar antes de haber configurado la OAuth App.
  Future<void> _addFolder() async {
    final chosen = await getDirectoryPath();
    if (chosen == null || !mounted) return;
    setState(() {
      _working = true;
      _problem = null;
      _progress = 'Leyendo $chosen…';
    });
    try {
      await widget.session.addExistingRepository(chosen);
    } catch (thrown) {
      if (mounted) setState(() => _problem = thrown);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

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
                    onPressed: _working ? null : _add,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Añadir desde GitHub'),
                  ),
                  // Y el camino que no pasa por GitHub: una carpeta que ya
                  // está clonada en el disco.
                  OutlinedButton.icon(
                    key: const Key('add-repository-folder'),
                    onPressed: _working ? null : _addFolder,
                    icon: const Icon(Icons.folder_open_outlined, size: 16),
                    label: const Text('Añadir una carpeta del disco'),
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

/// Elegir de entre los repositorios de GitHub de esta persona.
class _RepoPicker extends StatefulWidget {
  const _RepoPicker({required this.session});

  final Session session;

  @override
  State<_RepoPicker> createState() => _RepoPickerState();
}

class _RepoPickerState extends State<_RepoPicker> {
  late final Future<List<GitHubRepo>> _repos = _load();
  String _filter = '';

  Future<List<GitHubRepo>> _load() async {
    final token = await widget.session.tokenStore.read() ?? '';
    final api = GitHubApi(token: token);
    try {
      final all = await api.repositories();
      final already = {
        for (final repo in widget.session.workspace.repos) repo.id,
      };
      return [
        for (final repo in all)
          if (!already.contains(repo.id)) repo,
      ];
    } finally {
      api.close();
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Añadir un repositorio'),
    content: SizedBox(
      width: 520,
      height: 420,
      child: Column(
        children: [
          TextField(
            key: const Key('repo-filter'),
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Buscar',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _filter = value.toLowerCase()),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: FutureBuilder<List<GitHubRepo>>(
              future: _repos,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Note('${snapshot.error}', tone: didactaTeacher);
                }
                final repos = snapshot.data;
                if (repos == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final shown = [
                  for (final repo in repos)
                    if (_filter.isEmpty ||
                        repo.id.toLowerCase().contains(_filter))
                      repo,
                ];
                if (shown.isEmpty) {
                  return const Center(
                    child: Text('Ninguno que no esté ya abierto.'),
                  );
                }
                return ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, index) {
                    final repo = shown[index];
                    return ListTile(
                      key: Key('pick-${repo.id}'),
                      dense: true,
                      title: Text(repo.id),
                      subtitle: Text(
                        [
                          repo.defaultBranch,
                          if (repo.private) 'privado',
                          if (!repo.canWrite) 'solo lectura',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      onTap: () => Navigator.of(context).pop(repo),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
    ],
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
