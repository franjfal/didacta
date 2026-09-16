/// Las titulaciones: verlas, declararlas y renombrarlas.
///
/// Un grado agrupa asignaturas, así que se gestiona desde donde están las
/// asignaturas y no desde Ajustes: es una clasificación del material, como un
/// tema, no una preferencia de la persona.
///
/// **Quién declara qué importa.** Un grado lo declara un repositorio y las
/// asignaturas de cualquier otro lo nombran; con que uno lo declare, todos lo
/// ven agrupado. Declararlo en dos no rompe nada --se juntan por id-- pero es
/// lo que hace que luego discrepen, así que al crear uno se pregunta dónde y
/// se dice quién declara cada uno de los que ya hay.
///
/// Y nada de esto puede romper nada: un grado que no declara ningún
/// repositorio abierto no agrupa, y sus asignaturas salen sueltas, exactamente
/// como salían antes de que existieran los grados.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';
import '../model/library_tree.dart' show languageName;
import '../model/slug.dart';
import '../state/session.dart';
import 'sync_bar.dart';
import 'theme.dart';

Future<void> showDegrees(BuildContext context, Session session) =>
    showDialog<void>(
      context: context,
      builder: (context) => DegreesDialog(session: session),
    );

class DegreesDialog extends StatefulWidget {
  const DegreesDialog({super.key, required this.session});

  final Session session;

  @override
  State<DegreesDialog> createState() => _DegreesDialogState();
}

class _DegreesDialogState extends State<DegreesDialog> {
  String? _busy;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final degrees = session.catalogue.degrees;
    final missing = session.catalogue.undeclaredDegrees;
    final writable = [
      for (final repo in session.workspace.repos)
        if (session.canWriteIn(repo.id)) repo.id,
    ];

    return AlertDialog(
      title: const Text('Grados'),
      content: SizedBox(
        width: 560,
        height: 480,
        child: ListView(
          children: [
            const Text(
              'Un grado lo declara un repositorio y las asignaturas de '
              'cualquier otro lo nombran. Con que uno lo declare, todos lo '
              'ven agrupado; un grado que no declara nadie no agrupa, y sus '
              'asignaturas salen sueltas.',
              style: TextStyle(fontSize: 12.5, height: 1.45),
            ),
            const SizedBox(height: 12),
            if (degrees.isEmpty)
              const Note('Todavía no hay ninguno declarado.')
            else
              for (final degree in degrees)
                _DegreeRow(
                  session: session,
                  degree: degree,
                  busy: _busy == degree.id,
                  onRename: () => _rename(degree),
                ),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Nombrados y sin declarar',
                style: TextStyle(fontSize: 11.5, color: didactaTeacher),
              ),
              const SizedBox(height: 2),
              const Text(
                'Alguna asignatura dice pertenecer a estos y ningún '
                'repositorio abierto los declara. Se ven enteras, sin '
                'agrupar. Decláralos aquí, o abre el repositorio donde estén.',
                style: TextStyle(fontSize: 11.5, color: didactaMuted),
              ),
              const SizedBox(height: 6),
              for (final id in missing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          id,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      if (writable.isNotEmpty)
                        TextButton(
                          key: Key('declare-$id'),
                          onPressed: () => _create(writable, id: id),
                          child: const Text('Declarar'),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        if (writable.isNotEmpty)
          TextButton.icon(
            key: const Key('new-degree'),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Nuevo grado'),
            onPressed: () => _create(writable),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  Future<void> _create(List<String> writable, {String? id}) async {
    final answer = await showDialog<_NewDegree>(
      context: context,
      builder: (context) => _NewDegreeDialog(
        repos: writable,
        session: widget.session,
        fixedId: id,
      ),
    );
    if (answer == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = answer.id);
    try {
      await widget.session.createDegree(
        repo: answer.repo,
        id: answer.id,
        titles: answer.titles,
        institution: answer.institution,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Grado «${answer.id}» declarado.')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _rename(Degree degree) async {
    final options = widget.session.catalogue.languageOptions;
    final answer = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _TitlesDialog(
        title: 'Título del grado',
        languages: [for (final option in options) option.code],
        names: {for (final option in options) option.code: option.name},
        titles: degree.titles,
      ),
    );
    if (answer == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = degree.id);
    try {
      final written = await widget.session.setDegreeTitles(
        id: degree.id,
        titles: answer,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            written == 0
                ? 'No ha cambiado nada.'
                : 'Título cambiado en $written repositorio(s).',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }
}

class _DegreeRow extends StatelessWidget {
  const _DegreeRow({
    required this.session,
    required this.degree,
    required this.busy,
    required this.onRename,
  });

  final Session session;
  final Degree degree;
  final bool busy;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final courses = session.catalogue.coursesIn(degree.id).length;
    final canWrite = degree.sources.keys.any(session.canWriteIn);
    return Container(
      key: Key('degree-${degree.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: didactaSurface,
        border: Border.all(color: didactaRule),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  degree.title(session.language),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${degree.id} · '
                  '${courses == 1 ? '1 asignatura' : '$courses asignaturas'}',
                  style: const TextStyle(fontSize: 11.5, color: didactaMuted),
                ),
              ],
            ),
          ),
          // Quién lo declara. Con varios repositorios abiertos importa: es lo
          // que dice a quién le llega el cambio si se renombra.
          for (final repo in degree.sources.keys)
            if (session.colourOf(repo) != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: RepoChip(
                  colour: session.colourOf(repo)!,
                  label: session.workspace.byId(repo)?.label ?? repo,
                  compact: true,
                ),
              ),
          if (busy)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              key: Key('rename-degree-${degree.id}'),
              tooltip: canWrite
                  ? 'Título en todos los idiomas'
                  : 'Solo lectura: lo declara un repositorio en el que no '
                        'puedes escribir',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 15),
              onPressed: canWrite ? onRename : null,
            ),
        ],
      ),
    );
  }
}

/// Lo que hace falta para declarar un grado.
class _NewDegree {
  const _NewDegree({
    required this.repo,
    required this.id,
    required this.titles,
    this.institution,
  });

  final String repo;
  final String id;
  final Map<String, String> titles;
  final String? institution;
}

class _NewDegreeDialog extends StatefulWidget {
  const _NewDegreeDialog({
    required this.repos,
    required this.session,
    this.fixedId,
  });

  final List<String> repos;
  final Session session;

  /// Cuando se declara uno que ya se nombra: el id no se elige, es el que las
  /// asignaturas ya escribieron.
  final String? fixedId;

  @override
  State<_NewDegreeDialog> createState() => _NewDegreeDialogState();
}

class _NewDegreeDialogState extends State<_NewDegreeDialog> {
  final _name = TextEditingController();
  final _id = TextEditingController();
  final _institution = TextEditingController();
  late String _repo = widget.repos.first;
  bool _touchedId = false;

  @override
  void initState() {
    super.initState();
    if (widget.fixedId != null) {
      _id.text = widget.fixedId!;
      _touchedId = true;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _id.dispose();
    _institution.dispose();
    super.dispose();
  }

  String get _identifier =>
      _touchedId ? _id.text.trim() : slugify(_name.text.trim());

  @override
  Widget build(BuildContext context) {
    final language = widget.session.language;
    return AlertDialog(
      title: const Text('Nuevo grado'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('degree-name'),
              controller: _name,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Nombre en ${languageName(language)}',
                hintText: 'Grado en Matemáticas',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('degree-id'),
              controller: _id,
              onChanged: (value) => setState(() => _touchedId = true),
              decoration: InputDecoration(
                labelText: 'Identificador',
                hintText: _identifier.isEmpty ? 'matematicas' : _identifier,
                isDense: true,
                helperText:
                    'Es lo que escriben las asignaturas y lo que junta los '
                    'repositorios. No se traduce.',
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('degree-institution'),
              controller: _institution,
              decoration: const InputDecoration(
                labelText: 'Institución (opcional)',
                isDense: true,
              ),
            ),
            if (widget.repos.length > 1) ...[
              const SizedBox(height: 12),
              const Text(
                'En qué repositorio se declara',
                style: TextStyle(fontSize: 11.5, color: didactaMuted),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                key: const Key('degree-repo'),
                initialValue: _repo,
                isExpanded: true,
                decoration: const InputDecoration(isDense: true),
                items: [
                  for (final repo in widget.repos)
                    DropdownMenuItem(
                      value: repo,
                      child: Text(
                        widget.session.workspace.byId(repo)?.label ?? repo,
                      ),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _repo = value ?? widget.repos.first),
              ),
              const SizedBox(height: 4),
              const Note(
                'En uno solo. Declararlo en dos no rompe nada --se juntan por '
                'id-- pero es lo que hace que luego discrepen.',
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('degree-create'),
          onPressed: _name.text.trim().isEmpty || _identifier.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  _NewDegree(
                    repo: _repo,
                    id: _identifier,
                    titles: {language: _name.text.trim()},
                    institution: _institution.text.trim().isEmpty
                        ? null
                        : _institution.text.trim(),
                  ),
                ),
          child: const Text('Declarar'),
        ),
      ],
    );
  }
}

/// Un título en todos los idiomas. Como el de los apartados, con sus nombres.
class _TitlesDialog extends StatefulWidget {
  const _TitlesDialog({
    required this.title,
    required this.languages,
    required this.names,
    required this.titles,
  });

  final String title;
  final List<String> languages;
  final Map<String, String> names;
  final Map<String, String> titles;

  @override
  State<_TitlesDialog> createState() => _TitlesDialogState();
}

class _TitlesDialogState extends State<_TitlesDialog> {
  late final Map<String, TextEditingController> _fields = {
    for (final code in widget.languages)
      code: TextEditingController(text: widget.titles[code] ?? ''),
  };

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 460,
      height: 400,
      child: ListView(
        children: [
          for (final code in widget.languages)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                key: Key('degree-title-$code'),
                controller: _fields[code],
                decoration: InputDecoration(
                  labelText: widget.names[code] ?? code,
                  isDense: true,
                  helperText: (widget.titles[code] ?? '').isEmpty
                      ? 'sin traducir'
                      : null,
                  helperStyle: const TextStyle(
                    fontSize: 11.5,
                    color: didactaTeacher,
                  ),
                ),
              ),
            ),
          const Note(
            'Un idioma en blanco se queda marcado como pendiente en el '
            'fichero, no se borra el grado.',
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
        key: const Key('degree-titles-save'),
        onPressed: () => Navigator.of(context).pop({
          for (final entry in _fields.entries) entry.key: entry.value.text.trim(),
        }),
        child: const Text('Aceptar'),
      ),
    ],
  );
}
