/// Las plantillas de compilación: verlas, escribirlas y apagarlas.
///
/// Una plantilla es una **salida**: qué PDF se produce: la clase de documento,
/// sus opciones, los cinco ejes y --lo que la hace una plantilla y no un
/// perfil-- su propia cabecera de LaTeX.
///
/// Las quince de siempre vienen con el programa y **no se editan donde
/// están**: editar una es declararla en un repositorio con su mismo id, y
/// entonces manda la del repositorio. La de serie se queda intacta, que es lo
/// que mantiene vivo un `pdflatex master.tex` a mano. Por eso el botón dice
/// dónde va a escribir en lugar de fingir que se edita un fichero del
/// programa.
///
/// Apagar una no la borra. Lo que se quiere guardar de una versión que este
/// curso no se da es justamente su cabecera, y borrarla la perdería.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';
import '../model/slug.dart';
import '../state/session.dart';
import 'sync_bar.dart';
import 'theme.dart';

Future<void> showTemplates(BuildContext context, Session session) =>
    showDialog<void>(
      context: context,
      builder: (context) => TemplatesDialog(session: session),
    );

/// Los ejes que se pueden tocar, con su nombre y sus valores.
///
/// Los mismos cinco que documenta `didacta-profiles.tex`, más la maqueta. Lo
/// que una plantilla declare fuera de esta lista **se conserva**: la versión
/// del profesor de las diapositivas lleva un `notes=show` que no sale aquí, y
/// editarle el margen no puede quitárselo por el camino.
const List<(String, String, List<(String, String)>)> templateAxes = [
  ('medium', 'Medio', [('slides', 'Diapositivas'), ('document', 'Documento')]),
  ('detail', 'Detalle', [('brief', 'Lo que cabe'), ('full', 'Todo')]),
  ('audience', 'Audiencia', [('student', 'Alumno'), ('teacher', 'Profesor')]),
  (
    'solutions',
    'Soluciones',
    [
      ('hidden', 'Ninguna'),
      ('answers', 'Los resultados'),
      ('full', 'La solución entera'),
    ],
  ),
  ('pauses', 'Pausas', [('on', 'Se respetan'), ('off', 'Se colapsan')]),
  (
    'layout',
    'Maqueta',
    [('normal', 'Normal'), ('compact', 'Compacta'), ('exam', 'Examen')],
  ),
];

/// Elegir con qué plantillas se compila algo: un bloque, un tema, una lección.
///
/// Devuelve la lista elegida, o null si se cancela. **Lista vacía es «lo que
/// toque»**, no «nada»: las del bloque para un tema o una lección, y todas
/// las activas para un bloque. Por eso lo primero que hay en el diálogo es
/// esa opción y no una lista con todo desmarcado, que es la forma de acabar
/// sin compilar nada sin haberlo pedido.
///
/// Se ofrecen **todas las activas**, también las que hoy no toquen: el mismo
/// tema se quiere en libro un día y en diapositivas otro.
Future<List<String>?> chooseTemplates(
  BuildContext context,
  Session session, {
  required String title,
  required String inherited,
  required List<String> chosen,
  required List<String> byDefault,
}) => showDialog<List<String>>(
  context: context,
  builder: (context) => _ChooseTemplatesDialog(
    session: session,
    title: title,
    inherited: inherited,
    chosen: chosen,
    byDefault: byDefault,
  ),
);

class _ChooseTemplatesDialog extends StatefulWidget {
  const _ChooseTemplatesDialog({
    required this.session,
    required this.title,
    required this.inherited,
    required this.chosen,
    required this.byDefault,
  });

  final Session session;
  final String title;

  /// Qué pasa si no se elige nada, con todas las letras.
  final String inherited;

  /// Lo elegido ahora mismo. Vacío quiere decir que no se ha elegido.
  final List<String> chosen;

  /// Lo que se hereda si no se elige, para poder verlo antes de decidir.
  final List<String> byDefault;

  @override
  State<_ChooseTemplatesDialog> createState() => _ChooseTemplatesDialogState();
}

class _ChooseTemplatesDialogState extends State<_ChooseTemplatesDialog> {
  late bool _inherit = widget.chosen.isEmpty;
  late final Set<String> _picked = {
    ...(widget.chosen.isEmpty ? widget.byDefault : widget.chosen),
  };

  /// Lo elegido que **no se puede enseñar ahora**: plantillas que no declara
  /// ningún repositorio abierto, o que están apagadas.
  ///
  /// Se conservan al guardar. Si no, abrir esta lista con un repositorio
  /// cerrado y pulsar «Aceptar» borraría referencias correctas sin que nadie
  /// las haya visto siquiera -- la misma regla que hace que apagar un
  /// repositorio no borre nada.
  List<String> get _invisible {
    final known = {
      for (final template in widget.session.catalogue.activeTemplates)
        template.id,
    };
    return [
      for (final id in widget.chosen)
        if (!known.contains(id)) id,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final available = session.catalogue.activeTemplates;
    final inheritedIds = widget.byDefault.toSet();

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        height: 480,
        child: ListView(
          children: [
            RadioGroup<bool>(
              groupValue: _inherit,
              onChanged: (value) => setState(() => _inherit = value ?? true),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioListTile<bool>(
                    key: const Key('templates-inherit'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: true,
                    title: const Text(
                      'Lo que toque',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    subtitle: Text(
                      widget.inherited,
                      style: const TextStyle(fontSize: 11, color: didactaMuted),
                    ),
                  ),
                  const RadioListTile<bool>(
                    key: Key('templates-pick'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: false,
                    title: Text('Estas', style: TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
            ),
            const Divider(height: 12),
            if (_invisible.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Note(
                  'Esto se compila además en ${_invisible.join(', ')}, que no '
                  'se pueden enseñar aquí --están apagadas, o las declara un '
                  'repositorio que no está abierto--. Se quedan como están.',
                  tone: didactaTeacher,
                ),
              ),
            if (available.isEmpty)
              const Note('No hay ninguna plantilla encendida.')
            else
              for (final template in available)
                CheckboxListTile(
                  key: Key('pick-template-${template.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _inherit
                      ? inheritedIds.contains(template.id)
                      : _picked.contains(template.id),
                  enabled: !_inherit,
                  title: Text(
                    template.title(session.language),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  subtitle: Text(
                    template.id,
                    style: const TextStyle(
                      fontSize: 11,
                      color: didactaMuted,
                      fontFamily: 'monospace',
                    ),
                  ),
                  onChanged: (on) => setState(() {
                    if (on ?? false) {
                      _picked.add(template.id);
                    } else {
                      _picked.remove(template.id);
                    }
                  }),
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
          key: const Key('templates-choose-save'),
          // Sin ninguna marcada no se puede guardar «estas»: sería no
          // compilar nada, y para eso está «lo que toque».
          onPressed: !_inherit && _picked.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  _inherit
                      ? const <String>[]
                      : [
                          for (final template in available)
                            if (_picked.contains(template.id)) template.id,
                          // Y lo que no se podía enseñar, intacto.
                          ..._invisible,
                        ],
                ),
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}

class TemplatesDialog extends StatefulWidget {
  const TemplatesDialog({super.key, required this.session});

  final Session session;

  @override
  State<TemplatesDialog> createState() => _TemplatesDialogState();
}

class _TemplatesDialogState extends State<TemplatesDialog> {
  String? _busy;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final catalogue = session.catalogue;
    final templates = catalogue.templatesInUse;
    final missing = catalogue.undeclaredTemplates;
    final writable = [
      for (final repo in session.workspace.repos)
        if (session.canWriteIn(repo.id)) repo.id,
    ];

    return AlertDialog(
      title: const Text('Plantillas'),
      content: SizedBox(
        width: 720,
        height: 560,
        child: ListView(
          children: [
            const Text(
              'Una plantilla es una salida: qué PDF sale de una lección o de '
              'un tema. Las que trae Didacta se pueden editar, y editar una '
              'es escribirla en un repositorio: a partir de ahí manda la '
              'tuya, y la de serie se queda intacta.',
              style: TextStyle(fontSize: 12.5, height: 1.45),
            ),
            const SizedBox(height: 12),
            for (final template in templates)
              _TemplateRow(
                session: session,
                template: template,
                writable: writable,
                busy: _busy == template.id,
                onActive: (active) => _setActive(template, active),
                onEdit: () => _edit(template, writable),
                onCopy: () => _copy(template, writable),
                onPreamble: () => _preamble(template),
                onRemove: () => _remove(template),
              ),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Nombradas y sin declarar',
                style: TextStyle(fontSize: 11.5, color: didactaTeacher),
              ),
              const SizedBox(height: 2),
              Text(
                'Algún bloque, tema o lección se compila con estas y no las '
                'declara ningún repositorio abierto: ${missing.join(', ')}. '
                'No se compilan --pedirle a LaTeX una salida que no existe es '
                'un error, no un PDF raro-- así que falta abrir el '
                'repositorio donde estén, o declararlas aquí.',
                style: const TextStyle(fontSize: 11.5, color: didactaMuted),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (writable.isNotEmpty)
          TextButton.icon(
            key: const Key('new-template'),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Nueva plantilla'),
            onPressed: () => _create(writable),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  Future<void> _run(String id, Future<void> Function() work) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = id);
    try {
      await work();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _setActive(OutputTemplate template, bool active) {
    if (!template.declared) return Future.value();
    return _run(
      template.id,
      () => widget.session.setTemplateActive(id: template.id, active: active),
    );
  }

  /// Editar una plantilla.
  ///
  /// Si no la declara nadie --es una de las que trae el programa-- editarla
  /// es **escribirla** en un repositorio, con su mismo id. Se dice antes de
  /// abrir el formulario: quien la edita tiene que saber que a partir de ahí
  /// manda la suya.
  Future<void> _edit(OutputTemplate template, List<String> writable) async {
    if (!template.declared) return _copy(template, writable, sameId: true);

    final answer = await showDialog<_TemplateForm>(
      context: context,
      builder: (context) => _TemplateDialog(
        session: widget.session,
        template: template,
        repos: const [],
      ),
    );
    if (answer == null || !mounted) return;
    await _run(template.id, () async {
      await widget.session.setTemplateTitles(
        id: template.id,
        titles: answer.titles,
      );
      await widget.session.setTemplateShape(
        id: template.id,
        documentClass: answer.documentClass,
        classOptions: answer.classOptions,
        axes: answer.axes,
      );
    });
  }

  /// Copiar una plantilla a un repositorio: con su id --editarla-- o con uno
  /// nuevo --duplicarla--.
  Future<void> _copy(
    OutputTemplate template,
    List<String> writable, {
    bool sameId = false,
  }) async {
    if (writable.isEmpty) return;
    final answer = await showDialog<_TemplateForm>(
      context: context,
      builder: (context) => _TemplateDialog(
        session: widget.session,
        template: template,
        repos: writable,
        fixedId: sameId ? template.id : null,
        suggestedId: sameId ? null : '${template.id}-mia',
      ),
    );
    if (answer == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    await _run(answer.id, () async {
      await widget.session.declareTemplate(
        repo: answer.repo!,
        id: answer.id,
        titles: answer.titles,
        documentClass: answer.documentClass,
        classOptions: answer.classOptions,
        axes: answer.axes,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            sameId
                ? 'Ahora manda tu «${answer.id}». La de Didacta sigue igual.'
                : 'Plantilla «${answer.id}» declarada.',
          ),
        ),
      );
    });
  }

  Future<void> _create(List<String> writable) async {
    final answer = await showDialog<_TemplateForm>(
      context: context,
      builder: (context) =>
          _TemplateDialog(session: widget.session, repos: writable),
    );
    if (answer == null || !mounted) return;
    await _run(
      answer.id,
      () => widget.session.declareTemplate(
        repo: answer.repo!,
        id: answer.id,
        titles: answer.titles,
        documentClass: answer.documentClass,
        classOptions: answer.classOptions,
        axes: answer.axes,
      ),
    );
  }

  /// La cabecera de LaTeX, a mano.
  Future<void> _preamble(OutputTemplate template) async {
    final repo = template.sources.keys
        .where(widget.session.canWriteIn)
        .firstOrNull;
    if (repo == null) return;

    final current = await widget.session.templatePreamble(
      repo: repo,
      id: template.id,
    );
    if (!mounted) return;
    final answer = await showDialog<String>(
      context: context,
      builder: (context) => _PreambleDialog(template: template, text: current),
    );
    if (answer == null || !mounted) return;
    await _run(
      template.id,
      () => widget.session.setTemplatePreamble(
        repo: repo,
        id: template.id,
        text: answer,
      ),
    );
  }

  Future<void> _remove(OutputTemplate template) async {
    final used = _usedBy(template.id);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Quitar «${template.title(widget.session.language)}»'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                used == 0
                    ? 'No la nombra nada, así que quitarla solo borra su '
                          'declaración.'
                    : 'La nombran $used cosa(s) --bloques, temas o '
                          'lecciones--. Dejarán de compilarla, y saldrán en '
                          '«Entre repositorios» hasta que se arreglen.',
                style: const TextStyle(fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 10),
              const Note(
                'Su cabecera se queda donde está. Es LaTeX que alguien '
                'escribió, y volver a declararla con el mismo id la recupera '
                'entera. Si de verdad sobra, bórrala del repositorio.',
              ),
              const SizedBox(height: 6),
              const Note(
                'Si solo quieres dejar de sacar esta versión, apágala en vez '
                'de quitarla: se queda declarada y fuera de lo que se '
                'compila.',
                tone: didactaTeacher,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('template-remove-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await _run(
      template.id,
      () => widget.session.removeTemplate(id: template.id),
    );
  }

  /// Cuántos bloques, temas y lecciones la nombran.
  int _usedBy(String id) {
    final catalogue = widget.session.catalogue;
    var count = 0;
    for (final block in catalogue.blocks) {
      if (block.templates.contains(id)) count += 1;
    }
    for (final unit in catalogue.units) {
      if (unit.templates.contains(id)) count += 1;
    }
    for (final course in catalogue.courses) {
      for (final year in course.years.values) {
        for (final document in year.documents) {
          if (document.profiles.contains(id)) count += 1;
        }
      }
    }
    return count;
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({
    required this.session,
    required this.template,
    required this.writable,
    required this.busy,
    required this.onActive,
    required this.onEdit,
    required this.onCopy,
    required this.onPreamble,
    required this.onRemove,
  });

  final Session session;
  final OutputTemplate template;
  final List<String> writable;
  final bool busy;
  final ValueChanged<bool> onActive;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onPreamble;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final canWrite = template.sources.keys.any(session.canWriteIn);
    return Container(
      key: Key('template-${template.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: didactaSurface,
        border: Border.all(color: didactaRule),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // La casilla que decide si esta versión se saca.
              //
              // Solo en las declaradas: apagar una de serie sería escribir en
              // el programa, y lo que hay que hacer con ella es editarla, que
              // la trae al repositorio.
              Tooltip(
                message: template.declared
                    ? (template.active
                          ? 'Se compila. Púlsala para dejar de sacar esta '
                                'versión.'
                          : 'Apagada: no se compila, y sigue declarada con su '
                                'cabecera.')
                    : 'Las que trae Didacta no se apagan: edítala y pasa a '
                          'estar en tu repositorio.',
                child: Checkbox(
                  key: Key('template-active-${template.id}'),
                  value: template.active,
                  onChanged: busy || !template.declared || !canWrite
                      ? null
                      : (value) => onActive(value ?? true),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.title(session.language),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: template.active ? didactaInk : didactaMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _describe(),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: didactaMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // Dónde vive, que es lo que decide dónde se va a escribir.
              //
              // Tres respuestas distintas y ninguna se puede confundir con
              // otra: un repositorio, la carpeta del programa --que no
              // protege nadie-- o ninguna de las dos, que es una de las
              // quince que trae Didacta.
              if (!template.declared)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Text(
                    'viene con Didacta',
                    style: TextStyle(fontSize: 11, color: didactaMuted),
                  ),
                )
              else
                for (final repo in template.sources.keys)
                  if (repo == Session.programTemplates)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Text(
                        'en el programa · sin copia de seguridad',
                        style: TextStyle(fontSize: 11, color: didactaTeacher),
                      ),
                    )
                  else if (session.colourOf(repo) != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: RepoChip(
                        colour: session.colourOf(repo)!,
                        label: session.workspace.byId(repo)?.label ?? repo,
                        compact: true,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        session.workspace.byId(repo)?.label ?? repo,
                        style: const TextStyle(
                          fontSize: 11,
                          color: didactaMuted,
                        ),
                      ),
                    ),
              const Spacer(),
              if (!busy) ...[
                if (template.declared && canWrite)
                  TextButton(
                    key: Key('template-preamble-${template.id}'),
                    onPressed: onPreamble,
                    child: Text(
                      template.hasPreamble ? 'Cabecera ·' : 'Cabecera',
                    ),
                  ),
                if (writable.isNotEmpty || canWrite)
                  TextButton(
                    key: Key('template-edit-${template.id}'),
                    onPressed: template.declared && !canWrite ? null : onEdit,
                    child: Text(template.declared ? 'Editar' : 'Editar aquí'),
                  ),
                if (writable.isNotEmpty)
                  TextButton(
                    key: Key('template-copy-${template.id}'),
                    onPressed: onCopy,
                    child: const Text('Duplicar'),
                  ),
                if (template.declared && canWrite)
                  IconButton(
                    key: Key('template-remove-${template.id}'),
                    tooltip: 'Quitar esta plantilla',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline, size: 15),
                    onPressed: onRemove,
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Qué produce, en una línea.
  ///
  /// El id primero porque es lo que se escribe en un `taxonomy.yaml` o en un
  /// `year.yaml`, y después lo que decide si esta versión se le puede dar a
  /// un alumno, que es la pregunta que se hace de verdad.
  String _describe() {
    final parts = <String>[
      template.id,
      template.documentClass.isEmpty ? 'sin clase' : template.documentClass,
      switch (template.reveals) {
        'answers' => 'enunciados y resultados',
        'solutions' => 'enunciados, resultados y solución',
        'teacher' => 'todo, con la solución paso a paso',
        _ => 'solo los enunciados',
      },
      if (template.hasPreamble) 'con cabecera propia',
      if (!template.active) 'apagada',
    ];
    return parts.join(' · ');
  }
}

/// Lo que devuelve el formulario de una plantilla.
class _TemplateForm {
  const _TemplateForm({
    required this.id,
    required this.titles,
    required this.documentClass,
    required this.classOptions,
    required this.axes,
    this.repo,
  });

  final String id;
  final Map<String, String> titles;
  final String documentClass;
  final String classOptions;
  final Map<String, String> axes;

  /// En cuál se declara. Null cuando se edita una que ya está declarada.
  final String? repo;
}

class _TemplateDialog extends StatefulWidget {
  const _TemplateDialog({
    required this.session,
    required this.repos,
    this.template,
    this.fixedId,
    this.suggestedId,
  });

  final Session session;

  /// En cuáles se puede declarar. Vacía al editar una que ya lo está.
  final List<String> repos;

  /// De la que se parte, al editar o al duplicar.
  final OutputTemplate? template;

  final String? fixedId;
  final String? suggestedId;

  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<_TemplateDialog> {
  late final List<String> _languages = [
    for (final option in widget.session.catalogue.languageOptions) option.code,
  ];
  late final Map<String, TextEditingController> _titles = {
    for (final code in _languages)
      code: TextEditingController(text: widget.template?.titles[code] ?? ''),
  };
  late final TextEditingController _id = TextEditingController(
    text: widget.fixedId ?? widget.suggestedId ?? '',
  );
  late final TextEditingController _class = TextEditingController(
    text: widget.template?.documentClass ?? 'article',
  );
  late final TextEditingController _options = TextEditingController(
    text: widget.template?.classOptions ?? '',
  );

  /// Los ejes de partida, **enteros**: los que no salen en el formulario se
  /// conservan tal cual. La versión del profesor de las diapositivas lleva un
  /// `notes=show` que no se enseña aquí, y editarle el margen no puede
  /// quitárselo por el camino.
  late final Map<String, String> _axes = {...?widget.template?.axes};

  late String _repo = widget.repos.isEmpty ? '' : widget.repos.first;
  bool _touchedId = false;

  bool get _editing => widget.template != null && widget.repos.isEmpty;

  @override
  void dispose() {
    for (final controller in _titles.values) {
      controller.dispose();
    }
    _id.dispose();
    _class.dispose();
    _options.dispose();
    super.dispose();
  }

  String get _identifier => _editing
      ? widget.template!.id
      : (widget.fixedId ??
            (_touchedId
                ? _id.text.trim()
                : (_id.text.trim().isEmpty
                      ? slugify(_titles[_languages.first]?.text.trim() ?? '')
                      : _id.text.trim())));

  @override
  Widget build(BuildContext context) {
    final taken =
        !_editing &&
        widget.fixedId == null &&
        widget.session.catalogue.templatesInUse.any(
          (template) => template.id == _identifier,
        );

    return AlertDialog(
      title: Text(_editing ? 'Editar la plantilla' : 'La plantilla'),
      content: SizedBox(
        width: 520,
        height: 480,
        child: ListView(
          children: [
            if (widget.fixedId != null)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Note(
                  'Esta viene con Didacta. Al guardar se escribe en tu '
                  'repositorio con el mismo id, y a partir de ahí manda la '
                  'tuya; la de serie se queda como está.',
                  tone: didactaTeacher,
                ),
              ),
            const SectionLabel('Nombre'),
            for (final code in _languages)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  key: Key('template-title-$code'),
                  controller: _titles[code],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: widget.session.catalogue.languageOptions
                        .firstWhere((option) => option.code == code)
                        .name,
                    isDense: true,
                  ),
                ),
              ),
            const Note(
              'Sin nombre no pasa nada: se enseña por lo que hace, '
              '«Diapositivas (sin pausas)».',
            ),
            const SizedBox(height: 12),

            if (!_editing) ...[
              const SectionLabel('Identificador'),
              TextField(
                key: const Key('template-id'),
                controller: _id,
                enabled: widget.fixedId == null,
                onChanged: (_) => setState(() => _touchedId = true),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _identifier.isEmpty ? 'apuntes-a5' : _identifier,
                  errorText: taken ? 'ya hay una plantilla con este id' : null,
                  helperText:
                      'Es lo que escriben los bloques y los temas que se '
                      'compilan con ella. No se traduce y no se cambia.',
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 12),
            ],

            const SectionLabel('Qué produce'),
            TextField(
              key: const Key('template-class'),
              controller: _class,
              decoration: const InputDecoration(
                labelText: 'Clase de documento',
                hintText: 'article, book, beamer',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('template-options'),
              controller: _options,
              decoration: const InputDecoration(
                labelText: 'Opciones de la clase',
                hintText: '12pt,oneside',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),

            const SectionLabel('Ejes'),
            for (final (key, label, values) in templateAxes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DropdownButtonFormField<String>(
                  key: Key('template-axis-$key'),
                  initialValue: values.any((v) => v.$1 == _axes[key])
                      ? _axes[key]
                      : values.first.$1,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: label, isDense: true),
                  items: [
                    for (final (value, name) in values)
                      DropdownMenuItem(value: value, child: Text(name)),
                  ],
                  onChanged: (value) => setState(() {
                    if (value != null) _axes[key] = value;
                  }),
                ),
              ),

            if (widget.repos.length > 1) ...[
              const SectionLabel('Dónde se guarda'),
              DropdownButtonFormField<String>(
                key: const Key('template-repo'),
                initialValue: _repo,
                isExpanded: true,
                decoration: const InputDecoration(isDense: true),
                items: [
                  for (final repo in widget.repos)
                    DropdownMenuItem(
                      value: repo,
                      child: Text(widget.session.templateHomeLabel(repo)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _repo = value ?? widget.repos.first),
              ),
              const SizedBox(height: 4),
              if (_repo == Session.programTemplates)
                const Note(
                  'En el programa no la protege nadie: no está en git, no se '
                  'sincroniza y se va con este ordenador. Hazte copias desde '
                  'Ajustes, y si la plantilla es de la asignatura y no tuya, '
                  'guárdala en su repositorio.',
                  tone: didactaTeacher,
                )
              else
                const Note(
                  'En uno. Una plantilla es un fichero con su cabecera, y '
                  'tenerla en dos es tener dos versiones que pueden '
                  'discrepar. Los demás repositorios la usan sin declararla.',
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
          key: const Key('template-save'),
          onPressed: _identifier.isEmpty || taken || _class.text.trim().isEmpty
              ? null
              : () {
                  // Los ejes de partida con lo elegido encima: así los que no
                  // salen en el formulario siguen ahí.
                  final axes = {..._axes};
                  Navigator.of(context).pop(
                    _TemplateForm(
                      id: _identifier,
                      titles: {
                        for (final entry in _titles.entries)
                          entry.key: entry.value.text.trim(),
                      },
                      documentClass: _class.text.trim(),
                      classOptions: _options.text.trim(),
                      axes: axes,
                      repo: _editing ? null : _repo,
                    ),
                  );
                },
          child: Text(_editing ? 'Guardar' : 'Declarar'),
        ),
      ],
    );
  }
}

/// La cabecera de LaTeX de una plantilla, a mano.
///
/// Un campo de texto monoespaciado y nada más, como el editor del `unit.yaml`
/// en crudo: esto es LaTeX, y lo que hace falta es escribirlo y verlo entero.
class _PreambleDialog extends StatefulWidget {
  const _PreambleDialog({required this.template, required this.text});

  final OutputTemplate template;
  final String text;

  @override
  State<_PreambleDialog> createState() => _PreambleDialogState();
}

class _PreambleDialogState extends State<_PreambleDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Cabecera de «${widget.template.id}»'),
    content: SizedBox(
      width: 640,
      height: 460,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Se lee al final del preámbulo de Didacta, así que aquí se puede '
            'redefinir lo que Didacta acaba de definir: los márgenes, los '
            'colores, un entorno. No lleva `\\documentclass` ni '
            '`\\begin{document}`: de eso ya se encarga la plantilla.',
            style: TextStyle(fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: didactaRule),
              ),
              child: TextField(
                key: const Key('template-preamble-text'),
                controller: _controller,
                maxLines: null,
                expands: true,
                style: monoStyle,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.all(12),
                  hintText: '\\usepackage{lmodern}\n\\geometry{margin=2cm}',
                ),
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
        key: const Key('template-preamble-save'),
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: const Text('Guardar'),
      ),
    ],
  );
}
