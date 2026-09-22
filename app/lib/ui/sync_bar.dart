/// La barra de arriba: en qué repositorios se trabaja, y traer y enviar.
///
/// Con varios repositorios abiertos hay dos preguntas que se hacen todo el
/// rato y que antes no existían: **en cuál estoy** y **qué falta por enviar**.
/// Las dos se contestan aquí, en el mismo sitio siempre.
///
/// Traer y enviar son dos botones y no uno porque son dos decisiones
/// distintas: un `pull` cambia los ficheros de debajo de quien está editando,
/// y un `push` saca trabajo de esta máquina. Ninguna de las dos se hace sola.
///
/// Y enviar **propone un mensaje** con lo que se tocó, y lo deja editar antes
/// de escribir nada: es lo que queda en el historial de otra gente.
///
/// Las dos abren el terminal, el mismo de compilar. Un envío de setecientos
/// ficheros son minutos de `git add`, `git commit` y `git push`, y hasta
/// ahora eso era un botón gris y nada más: quien lo pulsaba lo volvía a
/// pulsar, porque desde fuera una aplicación que no dice nada durante dos
/// minutos está colgada. git cuenta lo que hace; solo había que enseñarlo.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../model/commit_message.dart';
import '../model/workspace.dart';
import '../state/session.dart';
import 'build_console.dart';
import 'theme.dart';

class SyncBar extends StatefulWidget {
  const SyncBar({super.key, required this.session});

  final Session session;

  @override
  State<SyncBar> createState() => _SyncBarState();
}

class _SyncBarState extends State<SyncBar> {
  bool _busy = false;

  /// Confirma lo pendiente, con el mensaje que se escriba.
  Future<void> _commit() async {
    final session = widget.session;
    final chosen = await showDialog<_Chosen>(
      context: context,
      builder: (context) => _CommitDialog(
        pending: session.pendingChanges,
        repos: session.workspace.repos,
      ),
    );
    if (chosen == null || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Igual que traer y enviar: `commitPending` arranca el registro antes
      // de su primer `await`, y confirmar setecientos ficheros tarda lo
      // suyo.
      final committing = session.commitPending(
        chosen.message,
        only: chosen.paths,
      );
      unawaited(
        showBuildConsole(context, session.syncConsole, autoClose: true),
      );
      final done = await committing;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            done == 0
                ? 'No había nada que confirmar.'
                : session.pushOnCommit
                ? 'Confirmado y enviado.'
                : 'Confirmado. Queda enviarlo.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('$error'), backgroundColor: didactaTeacher),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pull() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // El registro se abre con la operación ya lanzada: `pullAll` arranca
      // la consola antes de su primer `await`, así que para cuando esta
      // ventana se monta ya está enseñando lo de ahora y no lo de la vez
      // anterior.
      final bringing = widget.session.pullAll();
      unawaited(
        showBuildConsole(context, widget.session.syncConsole, autoClose: true),
      );
      final result = await bringing;
      final failed = [
        for (final entry in result.entries)
          if (entry.value is! int) '${entry.key}: ${entry.value}',
      ];
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failed.isEmpty
                ? 'Traído de GitHub y actualizado.'
                : 'Traído, con problemas:\n${failed.join('\n')}',
          ),
          backgroundColor: failed.isEmpty ? null : didactaTeacher,
          duration: Duration(seconds: failed.isEmpty ? 3 : 10),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('$error'), backgroundColor: didactaTeacher),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _push() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boxes = await widget.session.outbox();
      if (!mounted) return;
      if (boxes.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No hay nada que enviar.')),
        );
        return;
      }
      final message = await showDialog<String>(
        context: context,
        builder: (context) => _PushDialog(boxes: boxes),
      );
      if (message == null || !mounted) return;

      final sending = widget.session.pushAll(message);
      unawaited(
        showBuildConsole(context, widget.session.syncConsole, autoClose: true),
      );
      final result = await sending;
      final failed = [
        for (final entry in result.entries)
          if (entry.value is! int) '${entry.key}: ${entry.value}',
      ];
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failed.isEmpty
                ? 'Enviado a GitHub.'
                : 'No se pudo enviar todo:\n${failed.join('\n')}',
          ),
          backgroundColor: failed.isEmpty ? null : didactaTeacher,
          duration: Duration(seconds: failed.isEmpty ? 3 : 10),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('$error'), backgroundColor: didactaTeacher),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final repos = session.workspace.repos;
    if (repos.isEmpty) return const SizedBox.shrink();

    final behind = session.behind ?? 0;

    // Los commits que no han salido de esta máquina, **y nada más**. Antes
    // esta cuenta sumaba también los ficheros escritos y sin confirmar, y
    // eso decía «697 sin enviar» sobre un repositorio que no tenía ni un
    // commit pendiente: lo que había eran 697 ficheros que ni siquiera
    // estaban en un commit todavía. Son dos cosas distintas y se arreglan
    // con dos botones distintos, así que se cuentan por separado.
    final unsent = session.ahead;
    final pending = session.pendingCount;

    return Container(
      decoration: const BoxDecoration(
        color: didactaPanel,
        border: Border(bottom: BorderSide(color: didactaRule)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          // En qué se está trabajando, con su color. Con uno solo no hace
          // falta decirlo: no hay con qué confundirlo.
          if (session.workspace.isMultiple)
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final repo in repos)
                    _RepoFilter(session: session, repo: repo),
                ],
              ),
            )
          else
            Expanded(
              child: Text(
                repos.single.id,
                style: const TextStyle(fontSize: 11.5, color: didactaMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          // Lo que impide que un repositorio esté al día, si algo lo impide.
          //
          // Aquí y no en un diálogo: es una advertencia sobre lo que hay
          // debajo de lo que se está editando, y el sitio donde se resuelve
          // --traer y enviar-- son los dos botones de al lado.
          for (final repo in repos)
            if (session.driftOf(repo.id) != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Tooltip(
                  message: '${session.driftOf(repo.id)}',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.sync_problem_outlined,
                        size: 15,
                        color: didactaEx,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        session.workspace.isMultiple
                            ? repo.label
                            : 'sin sincronizar',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: didactaEx,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          // Antes de traer y enviar: es una preferencia de lectura, no una
          // operación sobre git, y separarla de los dos botones que sí tocan
          // el repositorio evita pulsarla queriendo pulsar otra cosa.
          _LanguagePicker(session: session),
          // Y confirmar, delante de los dos: es el paso que va antes.
          //
          // Con los commits automáticos puestos aparece **solo cuando hay
          // algo pendiente**, que se creía que no pasaba nunca y pasa: lo
          // que se escribe fuera de Didacta --otro editor, una carpeta
          // copiada, una lección traída de otro sitio-- llega al árbol de
          // trabajo sin pasar por aquí y se queda sin confirmar. Cuando no
          // hay nada, no se enseña: un botón que no hace nada se aprende a
          // ignorar justo antes del día en que sí hacía falta.
          if (!session.commitOnSave || pending > 0)
            _CommitButton(session: session, onPressed: _busy ? null : _commit),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          _SyncButton(
            id: 'pull',
            icon: Icons.download_outlined,
            tooltip: behind > 0
                ? 'Traer de GitHub ($behind por traer)'
                : 'Traer de GitHub',
            badge: behind,
            onPressed: _busy ? null : _pull,
          ),
          _SyncButton(
            id: 'push',
            icon: Icons.upload_outlined,
            tooltip: [
              'Enviar a GitHub',
              if (unsent > 0) '$unsent commit(s) sin enviar',
              // Dicho aquí también, porque enviar se los lleva: cierra en un
              // commit lo que quede suelto antes de empujar. Quien quiera
              // contarlos por separado tiene el botón de al lado.
              if (pending > 0) '$pending fichero(s) sin confirmar',
            ].join('\n'),
            badge: unsent,
            colour: didactaAccentDark,
            onPressed: _busy ? null : _push,
          ),
        ],
      ),
    );
  }
}

/// Confirmar a mano lo que está escrito y sin commit.
///
/// **Solo aparece con los commits automáticos apagados.** Con ellos puestos
/// no queda nunca nada pendiente, así que el botón no tendría nada que hacer
/// la mitad del tiempo --y un botón que no hace nada se aprende a ignorar
/// justo antes del día en que sí hacía falta--.
class _CommitButton extends StatelessWidget {
  const _CommitButton({required this.session, required this.onPressed});

  final Session session;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final pending = session.pendingCount;
    return Tooltip(
      message: pending == 0
          ? 'No hay nada escrito sin confirmar'
          : 'Confirmar $pending fichero(s) escritos y sin confirmar, '
                'eligiendo cuáles entran',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            key: const Key('sync-commit'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.check_circle_outline, size: 18),
            color: pending > 0 ? didactaAccentDark : didactaMuted,
            onPressed: pending == 0 ? null : onPressed,
          ),
          if (pending > 0)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: didactaAccentDark,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  key: const Key('sync-commit-badge'),
                  pending > 99 ? '99+' : '$pending',
                  style: const TextStyle(
                    fontSize: 9,
                    height: 1,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Lo elegido en el diálogo de confirmar: el mensaje y las rutas que entran.
typedef _Chosen = ({String message, Map<String, List<String>> paths});

/// Qué se confirma, y con qué mensaje.
///
/// El mismo trato que el de guardar una unidad: un mensaje se escribe, no se
/// genera. «Cambios» en cuarenta commits seguidos es un historial que no
/// sirve para nada, y el que lo va a leer eres tú dentro de seis meses.
///
/// **Y se elige qué entra.** Lo pendiente puede ser un fichero o pueden ser
/// setecientos --una carpeta de lecciones traída de otro sitio, una tarde de
/// trabajo en otro editor-- y meter setecientos en un commit que dice una
/// sola cosa es tirar el historial de esos ficheros antes de tenerlo. Todo
/// viene marcado, que es lo corriente; desmarcar es para quien quiera
/// contarlo en varios commits, y entonces se vuelve a abrir con lo que
/// quedó.
///
/// Con un filtro por ruta, porque a setecientas líneas elegir a mano no es
/// elegir. Escribir `taylor` deja lo de Taylor, y la casilla del repositorio
/// pasa a marcar y desmarcar **lo que se ve**: ese es el gesto que convierte
/// una tarde de trabajo en cinco commits que se leen.
///
/// Agrupado por repositorio porque un commit **es de un repositorio**: lo
/// que se firma aquí son dos commits cuando hay dos repositorios tocados, y
/// una lista plana de rutas no deja ver cuál va a dónde.
class _CommitDialog extends StatefulWidget {
  const _CommitDialog({required this.pending, required this.repos});

  final Map<String, List<String>> pending;

  /// Los repositorios abiertos, para el color y la etiqueta de cada grupo.
  final List<ContentRepo> repos;

  @override
  State<_CommitDialog> createState() => _CommitDialogState();
}

class _CommitDialogState extends State<_CommitDialog> {
  final _message = TextEditingController();

  /// Suyo y no el primario: dentro de un diálogo no hay ninguno que adoptar,
  /// y la barra de desplazamiento tiene que agarrarse a esta lista.
  final _scroll = ScrollController();

  final _filter = TextEditingController();

  String get _needle => _filter.text.trim().toLowerCase();

  /// Lo marcado, por repositorio. Todo, de salida.
  late final Map<String, Set<String>> _chosen = {
    for (final entry in widget.pending.entries)
      if (entry.value.isNotEmpty) entry.key: {...entry.value},
  };

  /// Los ficheros de un repositorio que pasan el filtro, en el orden en que
  /// los dio git.
  List<String> _shownOf(String repo) {
    final all = widget.pending[repo] ?? const <String>[];
    if (_needle.isEmpty) return all;
    return [
      for (final path in all)
        if (path.toLowerCase().contains(_needle)) path,
    ];
  }

  int _pickedOf(String repo) {
    final chosen = _chosen[repo];
    if (chosen == null) return 0;
    return _shownOf(repo).where(chosen.contains).length;
  }

  /// Los repositorios con algo pendiente, en el orden del espacio de trabajo
  /// para que sean los mismos colores en el mismo orden que arriba.
  late final List<String> _order = [
    for (final repo in widget.repos)
      if (widget.pending[repo.id]?.isNotEmpty ?? false) repo.id,
    // Y los que no estén en el espacio de trabajo, detrás: no debería
    // pasar, y perderlos de vista sería peor que enseñarlos sin color.
    for (final id in widget.pending.keys)
      if (widget.pending[id]!.isNotEmpty &&
          !widget.repos.any((repo) => repo.id == id))
        id,
  ];

  int get _picked =>
      _chosen.values.fold<int>(0, (sum, files) => sum + files.length);

  /// Cuántos deja ver el filtro, sumando los repositorios.
  int get _shown => _order.fold<int>(0, (sum, id) => sum + _shownOf(id).length);

  int get _total =>
      widget.pending.values.fold<int>(0, (sum, files) => sum + files.length);

  ContentRepo? _repoOf(String id) =>
      widget.repos.where((repo) => repo.id == id).firstOrNull;

  /// Las filas de la lista: una cabecera por repositorio y una por fichero.
  ///
  /// Una lista plana y no una columna de columnas porque puede haber
  /// ochocientas filas, y `ListView.builder` solo construye las que se ven.
  List<({String repo, String? path})> get _rows => [
    for (final id in _order)
      if (_shownOf(id).isNotEmpty) ...[
        (repo: id, path: null),
        for (final path in _shownOf(id)) (repo: id, path: path),
      ],
  ];

  void _toggle(String repo, String path) {
    setState(() {
      final files = _chosen[repo] ??= <String>{};
      if (!files.remove(path)) files.add(path);
    });
  }

  /// Marca o desmarca **lo que se ve** de ese repositorio.
  ///
  /// Lo que se ve y no todo lo suyo: con un filtro puesto, lo que se está
  /// mirando es lo que se quiere meter en este commit, y que la casilla de
  /// la cabecera marcase además las seiscientas que el filtro dejó fuera
  /// sería exactamente lo contrario de lo que se pidió.
  void _toggleRepo(String repo) {
    setState(() {
      final shown = _shownOf(repo);
      final files = _chosen[repo] ??= <String>{};
      if (shown.every(files.contains)) {
        files.removeAll(shown);
      } else {
        files.addAll(shown);
      }
    });
  }

  @override
  void dispose() {
    _message.dispose();
    _filter.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;

    return AlertDialog(
      title: const Text('Confirmar los cambios'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('commit-pending-message'),
              controller: _message,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Qué has cambiado',
                hintText: 'Corregir la errata del Teorema 2.1',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            // El filtro solo cuando hay bastante que filtrar. Con cuatro
            // ficheros delante, un campo de búsqueda es una casilla más que
            // leer antes de llegar al botón.
            if (_total > 12) ...[
              TextField(
                key: const Key('commit-pending-filter'),
                controller: _filter,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Filtrar por ruta: taylor, va.tex, series/…',
                  prefixIcon: const Icon(Icons.search, size: 17),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  suffixIcon: _needle.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('commit-pending-filter-clear'),
                          tooltip: 'Quitar el filtro',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 15),
                          onPressed: () {
                            _filter.clear();
                            setState(() {});
                          },
                        ),
                ),
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              [
                if (_picked == _total)
                  _total == 1 ? 'Un fichero' : '$_total ficheros'
                else
                  '$_picked de $_total ficheros',
                if (_needle.isNotEmpty) '$_shown se ven',
              ].join(' · '),
              key: const Key('commit-pending-count'),
              style: const TextStyle(fontSize: 11.5, color: didactaMuted),
            ),
            const SizedBox(height: 4),
            // Lo que va dentro, a la vista y marcable. Un commit que se firma
            // sin ver qué lleva es como se envía por error media traducción.
            SizedBox(
              height: 280,
              child: rows.isEmpty
                  ? Center(
                      child: Text(
                        'Nada encaja con «${_filter.text.trim()}».',
                        style: const TextStyle(
                          fontSize: 12,
                          color: didactaMuted,
                        ),
                      ),
                    )
                  : Scrollbar(
                      controller: _scroll,
                      // Siempre a la vista: con setecientas rutas dentro, un
                      // pulgar que solo sale al pasar el ratón esconde que
                      // hay setecientas.
                      thumbVisibility: true,
                      child: ListView.builder(
                        key: const Key('commit-pending-files'),
                        controller: _scroll,
                        itemCount: rows.length,
                        itemExtent: 22,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          if (row.path == null) {
                            return _RepoHeader(
                              repo: _repoOf(row.repo),
                              id: row.repo,
                              picked: _pickedOf(row.repo),
                              total: _shownOf(row.repo).length,
                              onToggle: () => _toggleRepo(row.repo),
                            );
                          }
                          return _FileRow(
                            path: row.path!,
                            chosen:
                                _chosen[row.repo]?.contains(row.path!) ?? false,
                            onToggle: () => _toggle(row.repo, row.path!),
                          );
                        },
                      ),
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
        FilledButton(
          key: const Key('commit-pending-confirm'),
          // Sin mensaje no, y sin nada marcado tampoco: un commit vacío no
          // es un commit, y el botón tiene que decirlo antes de pulsarlo.
          onPressed: _message.text.trim().isEmpty || _picked == 0
              ? null
              : () => Navigator.of(context).pop((
                  message: _message.text.trim(),
                  paths: <String, List<String>>{
                    for (final entry in _chosen.entries)
                      if (entry.value.isNotEmpty)
                        // En el orden en que los dio git, no en el del
                        // conjunto: un commit cuyas rutas salen barajadas
                        // se lee peor en `git show`.
                        entry.key: [
                          for (final path in widget.pending[entry.key]!)
                            if (entry.value.contains(path)) path,
                        ],
                  },
                )),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

/// La cabecera de un repositorio en la lista, que marca y desmarca el suyo.
class _RepoHeader extends StatelessWidget {
  const _RepoHeader({
    required this.repo,
    required this.id,
    required this.picked,
    required this.total,
    required this.onToggle,
  });

  final ContentRepo? repo;
  final String id;
  final int picked;
  final int total;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => InkWell(
    key: Key('commit-repo-$id'),
    onTap: onToggle,
    child: Row(
      children: [
        SizedBox(
          width: 26,
          child: Icon(
            picked == total
                ? Icons.check_box_outlined
                : picked == 0
                ? Icons.check_box_outline_blank
                : Icons.indeterminate_check_box_outlined,
            size: 15,
            color: didactaMuted,
          ),
        ),
        if (repo != null)
          RepoChip(colour: repo!.colour, label: repo!.label, compact: true)
        else
          Text(id, style: const TextStyle(fontSize: 10.5)),
        const SizedBox(width: 7),
        Text(
          picked == total ? '$total' : '$picked de $total',
          style: const TextStyle(fontSize: 11, color: didactaMuted),
        ),
      ],
    ),
  );
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.path,
    required this.chosen,
    required this.onToggle,
  });

  final String path;
  final bool chosen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => InkWell(
    key: Key('commit-file-$path'),
    onTap: onToggle,
    child: Row(
      children: [
        const SizedBox(width: 12),
        SizedBox(
          width: 26,
          child: Icon(
            chosen ? Icons.check_box_outlined : Icons.check_box_outline_blank,
            size: 14,
            color: chosen ? didactaAccentDark : didactaMuted,
          ),
        ),
        Expanded(
          child: Text(
            path,
            style: TextStyle(
              fontSize: 11.5,
              fontFamily: 'monospace',
              color: chosen ? null : didactaMuted,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

/// El idioma en el que se está trabajando, arriba y siempre a la vista.
///
/// No es el idioma de la aplicación --sus textos están en castellano-- sino el
/// del **contenido**: con cuál de las traducciones se está. Manda sobre casi
/// todo lo que se lee en pantalla, así que estaba mal escondido en la
/// biblioteca: desde la lista de asignaturas no había forma de cambiarlo, y
/// los títulos salían siempre en el idioma propio de cada asignatura aunque se
/// estuviera preparando la versión en valenciano.
///
/// Un menú y no una fila de pestañas porque una asignatura puede declarar
/// diez idiomas, y diez pestañas en la barra superior no caben ni se leen.
/// Con uno solo no aparece: no hay nada que elegir.
///
/// Lo que ofrece son los idiomas **del material abierto**, filtrados por los
/// que se hayan encendido en Ajustes. Antes ofrecía los diez a los que Didacta
/// sabe imprimir, que es otra lista: elegir uno al que ningún repositorio
/// traduce deja toda la pantalla enseñando el texto de reserva, y no hay nada
/// que hacer desde ahí.
class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final options = session.languageChoices;
    if (options.length < 2) return const SizedBox.shrink();
    final current = options
        .where((option) => option.code == session.language)
        .firstOrNull;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: PopupMenuButton<String>(
        key: const Key('language-picker'),
        tooltip: 'En qué idioma se ve el contenido',
        position: PopupMenuPosition.under,
        itemBuilder: (context) => [
          for (final option in options)
            PopupMenuItem<String>(
              key: Key('pick-language-${option.code}'),
              value: option.code,
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: option.code == session.language
                        ? const Icon(Icons.check, size: 15)
                        : null,
                  ),
                  Text('${option.name}  ·  ${option.code}'),
                ],
              ),
            ),
        ],
        onSelected: (code) => session.language = code,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
          decoration: BoxDecoration(
            border: Border.all(color: didactaRule),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.translate, size: 14, color: didactaMuted),
              const SizedBox(width: 5),
              Text(
                current?.name ?? session.language,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 16, color: didactaMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// La etiqueta de color de un repositorio.
///
/// La misma en toda la aplicación: en la barra de arriba, en la fila de un
/// tema y al lado de una unidad. Un color que solo significa algo en una
/// pantalla no se aprende.
/// Un repositorio de la barra, que se enciende y se apaga.
///
/// Es un botón y no una etiqueta porque con dos repositorios abiertos la
/// pregunta que se hace todo el rato no es «¿de cuál es esto?» --el color ya
/// lo dice-- sino «déjame ver solo lo mío». Antes eso obligaba a quitar el
/// repositorio de Ajustes, que además de ser tres pantallas es otra cosa:
/// quitarlo lo cierra.
///
/// Apagado, el repositorio sigue abierto, sigue trayendo y sigue guardando lo
/// que ya tenía; lo único que pasa es que su material no se enseña. Y enseña
/// exactamente lo mismo que vería quien no lo tuviera, que es la razón por la
/// que este botón sirve para comprobar qué ve un alumno o un compañero.
class _RepoFilter extends StatelessWidget {
  const _RepoFilter({required this.session, required this.repo});

  final Session session;
  final ContentRepo repo;

  @override
  Widget build(BuildContext context) {
    final visible = session.isRepoVisible(repo.id);
    return Tooltip(
      message: visible
          ? 'Ocultar ${repo.id} de la biblioteca y las asignaturas'
          : 'Volver a enseñar ${repo.id}',
      child: InkWell(
        key: Key('repo-filter-${repo.id}'),
        borderRadius: BorderRadius.circular(3),
        onTap: () => session.setRepoVisible(repo.id, !visible),
        child: Opacity(
          opacity: visible ? 1 : 0.4,
          child: RepoChip(
            colour: repo.colour,
            label: repo.label,
            muted: !visible,
          ),
        ),
      ),
    );
  }
}

class RepoChip extends StatelessWidget {
  const RepoChip({
    super.key,
    required this.colour,
    required this.label,
    this.compact = false,
    this.muted = false,
  });

  final int colour;
  final String label;
  final bool compact;

  /// Apagado: sin relleno y tachado, para que se vea de un vistazo que ese
  /// repositorio está ahí y no se está enseñando.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final tint = Color(colour);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 7, vertical: 2),
      decoration: BoxDecoration(
        color: muted ? Colors.transparent : tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: tint.withValues(alpha: muted ? 0.5 : 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 9.5 : 10.5,
          fontWeight: FontWeight.w700,
          color: tint,
          letterSpacing: 0.2,
          decoration: muted ? TextDecoration.lineThrough : null,
          decorationColor: tint,
        ),
      ),
    );
  }
}

class _SyncButton extends StatelessWidget {
  const _SyncButton({
    required this.id,
    required this.icon,
    required this.tooltip,
    required this.badge,
    required this.onPressed,
    this.colour = didactaMuted,
  });

  final String id;
  final IconData icon;
  final String tooltip;
  final int badge;
  final VoidCallback? onPressed;
  final Color colour;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          key: Key('sync-$id'),
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 17, color: badge > 0 ? colour : didactaMuted),
          onPressed: onPressed,
        ),
        if (badge > 0)
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                key: Key('sync-$id-badge'),
                '$badge',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Qué se va a enviar, y con qué mensaje.
class _PushDialog extends StatefulWidget {
  const _PushDialog({required this.boxes});

  final List<RepoOutbox> boxes;

  @override
  State<_PushDialog> createState() => _PushDialogState();
}

class _PushDialogState extends State<_PushDialog> {
  late final List<String> _pending = [
    for (final box in widget.boxes) ...box.pending,
  ];

  late final TextEditingController _message = TextEditingController(
    text: proposedCommitMessage(_pending),
  );

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enviar a GitHub'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final box in widget.boxes) ...[
              Row(
                children: [
                  RepoChip(colour: box.repo.colour, label: box.repo.label),
                  const SizedBox(width: 8),
                  Text(
                    [
                      if (box.ahead > 0) '${box.ahead} commits sin enviar',
                      if (box.pending.isNotEmpty)
                        '${box.pending.length} ficheros sin confirmar',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12, color: didactaMuted),
                  ),
                ],
              ),
              for (final path in box.pending.take(6))
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 2),
                  child: Text(
                    path,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: didactaMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (box.pending.length > 6)
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 2),
                  child: Text(
                    'y ${box.pending.length - 6} más',
                    style: const TextStyle(fontSize: 11, color: didactaMuted),
                  ),
                ),
              const SizedBox(height: 10),
            ],
            if (_pending.isEmpty)
              const Text(
                'No hay nada escrito sin confirmar: solo se envían los '
                'commits que ya están hechos.',
                style: TextStyle(fontSize: 12, color: didactaMuted),
              )
            else
              // El mensaje del commit que cierra lo que queda suelto. Un
              // mensaje solo, y no uno por repositorio, porque el gesto es
              // uno: se estaba trabajando en algo, y ese algo tocó ficheros
              // de varios sitios. Para contarlo en varios commits está el
              // botón de confirmar, que deja elegir qué entra en cada uno.
              TextField(
                key: const Key('push-message'),
                controller: _message,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Mensaje del commit que cierra lo que falta',
                  border: OutlineInputBorder(),
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
        FilledButton(
          key: const Key('push-confirm'),
          onPressed: () {
            final message = _message.text.trim();
            if (_pending.isNotEmpty && message.isEmpty) return;
            Navigator.of(context).pop(message.isEmpty ? 'Enviar' : message);
          },
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}
