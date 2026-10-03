/// Las plantillas de compilación: verlas, escribirlas, repartirlas entre
/// repositorios y apagarlas.
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
import '../state/session.dart';
import 'problem.dart';
import 'template_editor.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Los ejes que se pueden tocar, con su nombre y sus valores.
///
/// Los mismos cinco que documenta `didacta-profiles.tex`, más la maqueta. Lo
/// que una plantilla declare fuera de esta lista **se conserva**: la versión
/// del profesor de las diapositivas lleva un `notes=show` que no sale aquí, y
/// editarle el margen no puede quitárselo por el camino.
List<(String, String, List<(String, String)>)> get templateAxes => [
  (
    'medium',
    tr('Medio'),
    [('slides', tr('Diapositivas')), ('document', tr('Documento'))],
  ),
  (
    'detail',
    tr('Detalle'),
    [('brief', tr('Lo que cabe')), ('full', tr('Todo'))],
  ),
  (
    'audience',
    tr('Audiencia'),
    [('student', tr('Alumno')), ('teacher', tr('Profesor'))],
  ),
  (
    'solutions',
    tr('Soluciones'),
    [
      ('hidden', tr('Ninguna')),
      ('answers', tr('Los resultados')),
      ('full', tr('La solución entera')),
    ],
  ),
  (
    'pauses',
    tr('Pausas'),
    [('on', tr('Se respetan')), ('off', tr('Se colapsan'))],
  ),
  (
    'layout',
    tr('Maqueta'),
    [
      ('normal', tr('Normal')),
      ('compact', tr('Compacta')),
      ('exam', tr('Examen')),
    ],
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
                    title: Text(
                      tr('Lo que toque'),
                      style: TextStyle(fontSize: 12.5),
                    ),
                    subtitle: Text(
                      widget.inherited,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.palette.muted,
                      ),
                    ),
                  ),
                  RadioListTile<bool>(
                    key: Key('templates-pick'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: false,
                    title: Text(tr('Estas'), style: TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
            ),
            const Divider(height: 12),
            if (_invisible.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Note(
                  tr(
                    'Esto se compila además en {0}, que no '
                    'se pueden enseñar aquí --están apagadas, o las declara un '
                    'repositorio que no está abierto--. Se quedan como están.',
                    [_invisible.join(', ')],
                  ),
                  tone: context.palette.teacher,
                ),
              ),
            if (available.isEmpty)
              Note(tr('No hay ninguna plantilla encendida.'))
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
                    style: TextStyle(
                      fontSize: 11,
                      color: context.palette.muted,
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
          child: Text(tr('Cancelar')),
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
          child: Text(tr('Aceptar')),
        ),
      ],
    );
  }
}

/// Las plantillas, en su propia sección de Ajustes.
///
/// Era un diálogo detrás de un botón dentro de «Bloques y plantillas», y
/// quien buscaba dónde se edita lo que sale de compilar no lo encontraba.
/// Ahora es la sección entera, con la forma de la de los snippets: la lista
/// se ve al entrar, y cada una se abre en un editor con su vista previa
/// (`template_editor.dart`).
///
/// Y cada plantilla dice **en qué repositorios está**, con una casilla por
/// cada uno, como los snippets. Una basta para usarla en todos --los demás la
/// nombran sin declararla--, pero tenerla también en otro es lo que hace que
/// viaje con ese material y que no dependa de tener abierto el primero.
/// Marcar uno la copia entera, con su cabecera; editarla escribe en todos.
class TemplatesManager extends StatefulWidget {
  const TemplatesManager({super.key, required this.session});

  final Session session;

  @override
  State<TemplatesManager> createState() => _TemplatesManagerState();
}

class _TemplatesManagerState extends State<TemplatesManager> {
  String? _busy;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final catalogue = session.catalogue;
    final templates = catalogue.templatesInUse;
    final missing = catalogue.undeclaredTemplates;
    final writable = session.templateHomes;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(
                  'Una plantilla es una salida: qué PDF sale de una lección o de '
                  'un tema. Trae la clase de documento, sus opciones y --si '
                  'quieres-- tu propia cabecera de LaTeX. Las que trae Didacta se '
                  'pueden editar, y editar una es escribirla en un repositorio: a '
                  'partir de ahí manda la tuya, y la de serie se queda intacta.',
                ),
                style: TextStyle(fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 6),
              Text(
                tr(
                  'Las casillas de cada una dicen en qué repositorios está. Con '
                  'una basta para usarla en todos; marcar otro la copia allí con '
                  'su cabecera, y al editarla se escribe en todos los marcados.',
                ),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: context.palette.muted,
                ),
              ),
              if (missing.isNotEmpty) ...[
                const SizedBox(height: 10),
                Note(
                  tr(
                    'Algún bloque, tema o lección se compila con estas y no las '
                    'declara ningún repositorio abierto: {0}. '
                    'No se compilan --pedirle a LaTeX una salida que no existe es '
                    'un error, no un PDF raro-- así que falta abrir el '
                    'repositorio donde estén, o declararlas aquí.',
                    [missing.join(', ')],
                  ),
                  tone: context.palette.teacher,
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      templates.length == 1
                          ? tr('1 plantilla')
                          : tr('{0} plantillas', [templates.length]),
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.muted,
                      ),
                    ),
                  ),
                  if (writable.isNotEmpty)
                    OutlinedButton.icon(
                      key: const Key('new-template'),
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(tr('Nueva plantilla')),
                      onPressed: _busy != null ? null : _create,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              for (final template in templates)
                _TemplateRow(
                  session: session,
                  template: template,
                  writable: writable,
                  busy: _busy == template.id,
                  onActive: (active) => _setActive(template, active),
                  uses: TemplateUses.of(catalogue, template),
                  onToggle: (home) => _toggle(template, home),
                  onEdit: () => _edit(template),
                  onCopy: () => _copy(template),
                  onRemove: () => _remove(template),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ponerla en un sitio más, o quitarla de uno.
  ///
  /// Quitarla del último que la declara es quitarla del todo, y eso se
  /// pregunta: lo que la nombre deja de compilarla.
  Future<void> _toggle(OutputTemplate template, String home) async {
    final session = widget.session;
    final label = session.templateHomeLabel(home);
    if (template.sources.containsKey(home)) {
      if (template.sources.length <= 1) return _remove(template);
      return _run(
        template.id,
        () => session.removeTemplateFrom(repo: home, id: template.id),
      );
    }
    final messenger = ScaffoldMessenger.of(context);
    final first = session.catalogue.templates.isEmpty;
    await _run(template.id, () async {
      await session.addTemplateTo(repo: home, id: template.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            first
                ? tr(
                    '«{0}» está ahora en {1}, con las demás que trae Didacta: '
                    'todo se sigue compilando igual.',
                    [template.id, label],
                  )
                : !template.declared
                ? tr('Ahora manda tu «{0}». La de Didacta sigue igual.', [
                    template.id,
                  ])
                : tr('«{0}» también está en {1}.', [template.id, label]),
          ),
        ),
      );
    });
  }

  Future<void> _run(String id, Future<void> Function() work) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = id);
    try {
      await work();
    } catch (error) {
      showProblemIn(messenger, error);
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

  /// Editar una plantilla, en el editor con su vista previa.
  ///
  /// Si no la declara nadie --es una de las que trae el programa-- editarla
  /// es **escribirla** en un repositorio, con su mismo id; el editor lo dice
  /// antes de nada.
  Future<void> _edit(OutputTemplate template) async {
    setState(() => _busy = template.id);
    try {
      await showTemplateEditor(
        context,
        session: widget.session,
        template: template,
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Una nueva que parte de esta.
  Future<void> _copy(OutputTemplate template) => showTemplateEditor(
    context,
    session: widget.session,
    template: template,
    duplicate: true,
  );

  Future<void> _create() =>
      showTemplateEditor(context, session: widget.session);

  Future<void> _remove(OutputTemplate template) async {
    final used = TemplateUses.of(widget.session.catalogue, template).named;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          tr('Quitar «{0}»', [template.title(widget.session.language)]),
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                used == 0
                    ? tr(
                        'No la nombra nada, así que quitarla solo borra su '
                        'declaración.',
                      )
                    : tr(
                        'La nombran {0} cosa(s) --bloques, temas o '
                        'lecciones--. Dejarán de compilarla, y saldrán en '
                        '«Entre repositorios» hasta que se arreglen.',
                        [used],
                      ),
                style: const TextStyle(fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 10),
              Note(
                tr(
                  'Su cabecera se queda donde está. Es LaTeX que alguien '
                  'escribió, y volver a declararla con el mismo id la recupera '
                  'entera. Si de verdad sobra, bórrala del repositorio.',
                ),
              ),
              const SizedBox(height: 6),
              Note(
                tr(
                  'Si solo quieres dejar de sacar esta versión, apágala en vez '
                  'de quitarla: se queda declarada y fuera de lo que se '
                  'compila.',
                ),
                tone: context.palette.teacher,
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
            key: const Key('template-remove-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Quitar')),
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
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({
    required this.session,
    required this.template,
    required this.writable,
    required this.busy,
    required this.onActive,
    required this.uses,
    required this.onToggle,
    required this.onEdit,
    required this.onCopy,
    required this.onRemove,
  });

  final Session session;
  final OutputTemplate template;

  /// Dónde se puede escribir: los repositorios y la carpeta del programa.
  final List<String> writable;
  final bool busy;
  final ValueChanged<bool> onActive;

  /// Ponerla en un sitio, o quitarla de él.
  final ValueChanged<String> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onRemove;

  /// Qué se compila con ella.
  final TemplateUses uses;

  /// Las casillas que salen: donde se puede escribir, y donde está aunque
  /// no se pueda --para que se vea quién más la tiene--.
  List<String> get _homes => [
    for (final home in writable) home,
    for (final home in template.sources.keys)
      if (!writable.contains(home)) home,
  ];

  @override
  Widget build(BuildContext context) {
    final canWrite = template.sources.keys.any(writable.contains);
    return Container(
      key: Key('template-${template.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border.all(color: context.palette.rule),
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
                          ? tr(
                              'Se compila. Púlsala para dejar de sacar esta '
                              'versión.',
                            )
                          : tr(
                              'Apagada: no se compila, y sigue declarada con su '
                              'cabecera.',
                            ))
                    : tr(
                        'Las que trae Didacta no se apagan: edítala y pasa a '
                        'estar en tu repositorio.',
                      ),
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
                        color: template.active
                            ? context.palette.ink
                            : context.palette.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _describe(),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.palette.muted,
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
              // Dónde vive, que es lo que decide dónde se va a escribir: una
              // casilla por sitio, marcada si la declara. Ninguna marcada es
              // una de las quince que trae Didacta, y se dice con letras.
              if (!template.declared)
                Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text(
                    tr('viene con Didacta'),
                    style: TextStyle(
                      fontSize: 11,
                      color: context.palette.muted,
                    ),
                  ),
                ),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final home in _homes)
                      TemplateHomeSwitch(
                        key: Key('template-${template.id}-in-$home'),
                        session: session,
                        home: home,
                        on: template.sources.containsKey(home),
                        enabled: !busy && writable.contains(home),
                        onTap: () => onToggle(home),
                      ),
                  ],
                ),
              ),
              if (!busy) ...[
                if (writable.isNotEmpty || canWrite)
                  TextButton(
                    key: Key('template-edit-${template.id}'),
                    onPressed: template.declared && !canWrite ? null : onEdit,
                    child: Text(
                      template.declared ? tr('Editar') : tr('Editar aquí'),
                    ),
                  ),
                if (writable.isNotEmpty)
                  TextButton(
                    key: Key('template-copy-${template.id}'),
                    onPressed: onCopy,
                    child: Text(tr('Duplicar')),
                  ),
                if (template.declared && canWrite)
                  IconButton(
                    key: Key('template-remove-${template.id}'),
                    tooltip: tr('Quitarla de todos los sitios'),
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
      template.documentClass.isEmpty ? tr('sin clase') : template.documentClass,
      switch (template.reveals) {
        'answers' => tr('enunciados y resultados'),
        'solutions' => tr('enunciados, resultados y solución'),
        'teacher' => tr('todo, con la solución paso a paso'),
        _ => tr('solo los enunciados'),
      },
      if (template.hasPreamble) tr('con cabecera propia'),
      if (uses.named == 1)
        tr('la usa 1 cosa')
      else if (uses.named > 1)
        tr('la usan {0} cosas', [uses.named])
      else if (uses.inheriting.isNotEmpty)
        tr('por defecto en los bloques sin lista'),
      if (!template.active) tr('apagada'),
    ];
    return parts.join(' · ');
  }
}
