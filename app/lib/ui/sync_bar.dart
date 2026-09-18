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
library;

import 'package:flutter/material.dart';

import '../model/commit_message.dart';
import '../model/workspace.dart';
import '../state/session.dart';
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
    final pending = widget.session.pendingChanges;
    final message = await showDialog<String>(
      context: context,
      builder: (context) => _CommitDialog(pending: pending),
    );
    if (message == null || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final done = await widget.session.commitPending(message);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            done == 0
                ? 'No había nada que confirmar.'
                : widget.session.pushOnCommit
                ? 'Confirmado y enviado.'
                : 'Confirmado. Queda enviarlo.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pull() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await widget.session.pullAll();
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

      final result = await widget.session.pushAll(message);
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
    var waiting = session.ahead;
    for (final files in session.pendingChanges.values) {
      waiting += files.length;
    }

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
          if (!session.commitOnSave)
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
            tooltip: waiting > 0
                ? 'Enviar a GitHub ($waiting sin enviar)'
                : 'Enviar a GitHub',
            badge: waiting,
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
          : 'Confirmar $pending fichero(s) como un commit',
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

/// Pide el mensaje del commit manual.
///
/// El mismo trato que el de guardar una unidad: un mensaje se escribe, no se
/// genera. «Cambios» en cuarenta commits seguidos es un historial que no
/// sirve para nada, y el que lo va a leer eres tú dentro de seis meses.
class _CommitDialog extends StatefulWidget {
  const _CommitDialog({required this.pending});

  final Map<String, List<String>> pending;

  @override
  State<_CommitDialog> createState() => _CommitDialogState();
}

class _CommitDialogState extends State<_CommitDialog> {
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final files = [
      for (final entry in widget.pending.entries)
        for (final path in entry.value) (repo: entry.key, path: path),
    ];

    return AlertDialog(
      title: const Text('Confirmar los cambios'),
      content: SizedBox(
        width: 520,
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
            const SizedBox(height: 12),
            Text(
              files.length == 1 ? 'Un fichero:' : '${files.length} ficheros:',
              style: const TextStyle(fontSize: 11.5, color: didactaMuted),
            ),
            const SizedBox(height: 4),
            // Lo que va dentro, a la vista. Un commit que se firma sin ver
            // qué lleva es como se envía por error media traducción.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final file in files)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          file.path,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                  ],
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
          onPressed: _message.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_message.text.trim()),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
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
                        '${box.pending.length} ficheros sin guardar',
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
                'No hay nada escrito sin guardar: solo se envían los commits '
                'que ya están hechos.',
                style: TextStyle(fontSize: 12, color: didactaMuted),
              )
            else
              TextField(
                key: const Key('push-message'),
                controller: _message,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Mensaje del commit',
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
