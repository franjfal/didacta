/// El editor de una plantilla, con su vista previa al lado.
///
/// La misma forma que el de los snippets, y por lo mismo: una plantilla se
/// juzga mirando el PDF, no leyendo `12pt,oneside`. A la izquierda lo que la
/// define --nombre, clase, ejes, su cabecera de LaTeX--, en qué sitios está
/// y qué se compila con ella; a la derecha, una lección compilada con lo que
/// hay en la pantalla, sin guardar.
///
/// **La vista previa es de una lección de verdad**, no de un texto de
/// ejemplo: lo que decide una plantilla --la página, las pausas, cuánto
/// enseña de un ejercicio-- solo se ve con material. Por defecto, la primera
/// que se compila con ella; se puede cambiar.
///
/// **Guardar escribe en todos los sitios marcados.** Marcar uno nuevo la copia
/// allí, desmarcarlo la quita de ahí y solo de ahí.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../model/catalogue.dart';
import '../model/latex_snippets.dart' show SnippetPreview;
import '../model/library_tree.dart' show languageName;
import '../model/workspace.dart' show repoColours;
import '../model/slug.dart';
import '../state/session.dart';
import 'manage_templates.dart' show templateAxes;
import 'problem.dart';
import 'sync_bar.dart';
import 'tex_field.dart';
import 'tex_highlight.dart';
import 'theme.dart';
import '../l10n/tr.dart';

/// Abre el editor. Con [template] null, una plantilla nueva; con
/// [duplicate], una nueva que parte de [template]. Devuelve true si se
/// guardó.
Future<bool?> showTemplateEditor(
  BuildContext context, {
  required Session session,
  OutputTemplate? template,
  bool duplicate = false,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (context) => TemplateEditor(
    session: session,
    template: template,
    duplicate: duplicate,
  ),
);

/// Qué se compila con una plantilla: lo que la nombra, y lo que la hereda.
class TemplateUses {
  const TemplateUses({
    this.blocks = const [],
    this.inheriting = const [],
    this.units = const [],
    this.documents = const [],
  });

  /// Los bloques que la nombran en `taxonomy.yaml`.
  final List<CourseBlock> blocks;

  /// Los que no dicen nada y por eso compilan con todas las encendidas.
  final List<CourseBlock> inheriting;

  /// Las lecciones que se apartan de su bloque y la piden.
  final List<Unit> units;

  /// Los documentos que la piden en su `year.yaml`, con su curso y año.
  final List<(Course, String, Document)> documents;

  /// Cuántas cosas la nombran a propósito. Lo que la hereda no cuenta: no
  /// deja de compilarse nada si se quita.
  int get named => blocks.length + units.length + documents.length;

  bool get isEmpty => named == 0 && inheriting.isEmpty;

  factory TemplateUses.of(Catalogue catalogue, OutputTemplate template) {
    final id = template.id;
    return TemplateUses(
      blocks: [
        for (final block in catalogue.blocks)
          if (block.templates.contains(id)) block,
      ],
      inheriting: [
        if (template.active)
          for (final block in catalogue.blocks)
            if (block.templates.isEmpty) block,
      ],
      units: [
        for (final unit in catalogue.units)
          if (unit.templates.contains(id)) unit,
      ],
      documents: [
        for (final course in catalogue.courses)
          for (final MapEntry(key: year, value: entry) in course.years.entries)
            for (final document in entry.documents)
              if (document.profiles.contains(id)) (course, year, document),
      ],
    );
  }
}

/// Las lecciones con las que tiene sentido mirarla, las que se compilan con
/// ella delante.
///
/// Con un tope: la biblioteca tiene dos mil, y un menú de dos mil no lo lee
/// nadie. Si no se compila nada con ella todavía --una plantilla recién
/// creada--, las primeras de la biblioteca, para que haya algo que ver.
List<Unit> templatePreviewUnits(Catalogue catalogue, String id) {
  const most = 40;
  final using = <Unit>[];
  final others = <Unit>[];
  // Primero las de los documentos que la piden: una hoja de problemas que se
  // compila con ella se mira con sus problemas, no con una lección de teoría.
  for (final course in catalogue.courses) {
    for (final year in course.years.values) {
      for (final document in year.documents) {
        if (!document.profiles.contains(id)) continue;
        for (final reference in document.unitRefs) {
          final unit =
              catalogue.unitByReference(reference, repo: document.repo) ??
              catalogue.unitByReference(reference);
          if (unit != null &&
              using.length < most &&
              !using.any((each) => each.path == unit.path)) {
            using.add(unit);
          }
        }
      }
    }
  }
  for (final unit in catalogue.units) {
    if (using.any((each) => each.path == unit.path)) continue;
    if (catalogue.templatesFor(unit).contains(id) ||
        unit.templates.contains(id)) {
      if (using.length < most) using.add(unit);
    } else if (others.length < most) {
      others.add(unit);
    }
    if (using.length >= most) break;
  }
  return using.isNotEmpty ? using : others;
}

class TemplateEditor extends StatefulWidget {
  const TemplateEditor({
    super.key,
    required this.session,
    this.template,
    this.duplicate = false,
  });

  final Session session;
  final OutputTemplate? template;
  final bool duplicate;

  @override
  State<TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<TemplateEditor> {
  Session get _session => widget.session;

  OutputTemplate? get _original => widget.template;

  /// Si es una que ya está declarada y se edita en su sitio.
  bool get _editing =>
      _original != null && !widget.duplicate && _original!.declared;

  /// Si es una de las que trae Didacta: se escribe con su mismo id.
  bool get _fromDidacta =>
      _original != null && !widget.duplicate && !_original!.declared;

  bool get _creating => !_editing && !_fromDidacta;

  /// Los idiomas en que se le pone nombre: los de los repositorios donde
  /// va a estar, y los que ya tengan uno escrito --que no se pierda una
  /// traducción por no estar ese idioma abierto ahora--.
  late final List<String> _languages = () {
    final catalogue = _session.catalogue;
    final out = <String>[];
    void add(String code) {
      if (code.isNotEmpty && !out.contains(code)) out.add(code);
    }

    for (final home in [
      ...?_original?.sources.keys,
      ..._session.templateHomes,
    ]) {
      if (home == Session.programTemplates) continue;
      add(catalogue.defaultLanguageOf(home));
      catalogue.languagesOf(home).forEach(add);
    }
    for (final MapEntry(:key, :value) in {...?_original?.titles}.entries) {
      if (value.trim().isNotEmpty) add(key);
    }
    if (out.isEmpty) add(_session.language);
    return out;
  }();
  late final Map<String, TextEditingController> _titles = {
    for (final code in _languages)
      code: TextEditingController(
        text: widget.duplicate ? '' : (_original?.titles[code] ?? ''),
      ),
  };
  late final TextEditingController _id = TextEditingController(
    text: widget.duplicate && _original != null
        ? '${_original!.id}-mia'
        : (_original?.id ?? ''),
  );
  late final TextEditingController _class = TextEditingController(
    text: _original?.documentClass ?? 'article',
  );
  late final TextEditingController _options = TextEditingController(
    text: _original?.classOptions ?? '',
  );
  final TexEditingController _preamble = TexEditingController();

  /// Los ejes de partida, **enteros**: los que no salen en el formulario se
  /// conservan. La versión del profesor de las diapositivas lleva un
  /// `notes=show` que no se enseña aquí, y editarle el margen no puede
  /// quitárselo por el camino.
  late final Map<String, String> _axes = {...?_original?.axes};

  late bool _active = _original?.active ?? true;

  /// Dónde va a estar al guardar.
  late final Set<String> _homes = _editing
      ? _original!.sources.keys.toSet()
      : {?_session.templateHomes.firstOrNull};

  /// La cabecera tal como estaba, para saber si ha cambiado.
  String _savedPreamble = '';
  bool _preambleLoaded = false;

  late final List<Unit> _units = templatePreviewUnits(
    _session.catalogue,
    _original?.id ?? '',
  );
  late Unit? _unit = _units.firstOrNull;

  SnippetPreview? _preview;
  String? _previewed;
  bool _compiling = false;
  bool _again = false;
  bool _unavailable = false;
  int _revision = 0;
  Timer? _debounce;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _unavailable =
        _unit == null || _session.liveCompiler(repo: _unit!.repo) == null;
    for (final controller in [
      ..._titles.values,
      _id,
      _class,
      _options,
      _preamble,
    ]) {
      controller.addListener(_changed);
    }
    unawaited(_loadPreamble());
  }

  /// La cabecera guardada, del primer sitio que la tenga.
  Future<void> _loadPreamble() async {
    final original = _original;
    var text = '';
    if (original != null && original.hasPreamble) {
      for (final home in original.sources.keys) {
        try {
          text = await _session.templatePreamble(repo: home, id: original.id);
        } catch (_) {
          continue;
        }
        if (text.trim().isNotEmpty) break;
      }
    }
    if (!mounted) return;
    _savedPreamble = text;
    _preamble.text = text;
    setState(() => _preambleLoaded = true);
    unawaited(_compile());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final controller in [
      ..._titles.values,
      _id,
      _class,
      _options,
      _preamble,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), _compile);
  }

  String get _identifier {
    if (!_creating) return _original!.id;
    final typed = _id.text.trim();
    if (typed.isNotEmpty) return typed;
    return slugify(_titles[_languages.firstOrNull]?.text.trim() ?? '');
  }

  bool get _taken =>
      _creating &&
      _session.catalogue.templatesInUse.any(
        (template) => template.id == _identifier,
      );

  /// Lo que impide guardar, en frases.
  List<String> get _problems => [
    if (_identifier.isEmpty)
      tr('Ponle un nombre o un identificador: es lo que escriben los bloques.'),
    if (_taken) tr('Ya hay una plantilla con este id.'),
    if (_class.text.trim().isEmpty)
      tr('Sin clase de documento no se puede compilar.'),
    if (_homes.isEmpty)
      _editing
          ? tr(
              'Déjala al menos en un sitio. Para quitarla del todo, usa '
              '«Quitar» en la lista.',
            )
          : tr('Elige dónde se guarda.'),
  ];

  /// Beamer define sus propios teoremas, y chocan con los de Didacta: todas
  /// las diapositivas de serie llevan `notheorems`.
  bool get _beamerWithoutNoTheorems =>
      _class.text.trim() == 'beamer' &&
      !_options.text.split(',').map((o) => o.trim()).contains('notheorems');

  Map<String, String> get _currentAxes => {..._axes};

  String get _previewKey => [
    _identifier,
    _class.text.trim(),
    _options.text.trim(),
    for (final key in _axes.keys.toList()..sort()) '$key=${_axes[key]}',
    _preamble.text,
    _unit?.path ?? '',
  ].join('\u0000');

  Future<void> _compile() async {
    if (!mounted || _unavailable || !_preambleLoaded) return;
    final unit = _unit;
    if (unit == null || _class.text.trim().isEmpty) return;
    if (_compiling) {
      _again = true;
      return;
    }
    final key = _previewKey;
    setState(() => _compiling = true);
    try {
      final result = await _session.previewTemplate(
        unit: unit,
        id: _identifier,
        documentClass: _class.text.trim(),
        classOptions: _options.text.trim(),
        axes: _currentAxes,
        preamble: _preamble.text,
      );
      if (!mounted) return;
      setState(() {
        if (result == null) {
          _unavailable = true;
        } else {
          _preview = result;
          _previewed = key;
          _revision += 1;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _preview = SnippetPreview(
          ok: false,
          engineFailed: true,
          errors: ['$error'],
        );
        _previewed = key;
      });
    } finally {
      if (mounted) setState(() => _compiling = false);
    }
    if (_again && mounted) {
      _again = false;
      unawaited(_compile());
    }
  }

  Future<void> _save() async {
    if (_problems.isNotEmpty || _saving) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final session = _session;
    final id = _identifier;
    final titles = {
      for (final entry in _titles.entries) entry.key: entry.value.text.trim(),
    };
    final documentClass = _class.text.trim();
    final classOptions = _options.text.trim();
    final axes = _currentAxes;
    Future<void> declareIn(String home) => session.declareTemplate(
      repo: home,
      id: id,
      titles: titles,
      documentClass: documentClass,
      classOptions: classOptions,
      axes: axes,
      preamble: _preamble.text,
      active: _active,
    );
    setState(() => _saving = true);
    try {
      if (_editing) {
        final original = _original!;
        await session.setTemplateTitles(id: id, titles: titles);
        await session.setTemplateShape(
          id: id,
          documentClass: documentClass,
          classOptions: classOptions,
          axes: axes,
        );
        if (_active != original.active) {
          await session.setTemplateActive(id: id, active: _active);
        }
        if (_preamble.text != _savedPreamble) {
          await session.setTemplatePreambleEverywhere(
            id: id,
            text: _preamble.text,
          );
        }
        // Lo nuevo, con lo que hay en la pantalla: es la versión que se
        // acaba de escribir en los demás.
        for (final home in session.templateHomes) {
          if (_homes.contains(home) && !original.sources.containsKey(home)) {
            await declareIn(home);
          }
        }
        for (final home in original.sources.keys) {
          if (!_homes.contains(home)) {
            await session.removeTemplateFrom(repo: home, id: id);
          }
        }
      } else {
        for (final home in session.templateHomes) {
          if (_homes.contains(home)) await declareIn(home);
        }
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _fromDidacta
                ? tr('Ahora manda tu «{0}». La de Didacta sigue igual.', [id])
                : _homes.length == 1
                ? tr('«{0}» guardada.', [id])
                : tr('«{0}» guardada en {1} sitios.', [id, _homes.length]),
          ),
        ),
      );
      navigator.pop(true);
    } catch (error) {
      showProblemIn(messenger, error);
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.min(1180.0, size.width - 48);
    final height = math.min(820.0, size.height - 48);
    final problems = _problems;
    final form = _form(context);
    final preview = _TemplatePreviewPane(
      preview: _preview,
      compiling: _compiling,
      stale: _preview != null && _previewed != _previewKey,
      unavailable: _unavailable,
      revision: _revision,
      units: _units,
      unit: _unit,
      language: _session.language,
      onUnit: (unit) {
        setState(() => _unit = unit);
        unawaited(_compile());
      },
      onCompile: _compile,
    );

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.dialog),
      ),
      clipBehavior: Clip.antiAlias,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _compile,
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _compile,
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        },
        child: SizedBox(
          key: const Key('template-editor'),
          width: width,
          height: height,
          child: Column(
            children: [
              _Header(
                title: _creating
                    ? tr('Nueva plantilla')
                    : tr('Editar «{0}»', [_original!.title(_session.language)]),
                id: _identifier,
                fromDidacta: _fromDidacta,
                onClose: _saving ? null : () => Navigator.of(context).pop(),
              ),
              Divider(height: 1, color: context.palette.rule),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 860) {
                      return ListView(
                        padding: const EdgeInsets.all(18),
                        children: [
                          form,
                          const SizedBox(height: 18),
                          SizedBox(height: 420, child: preview),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: math.min(500, constraints.maxWidth * 0.46),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                            children: [form],
                          ),
                        ),
                        VerticalDivider(width: 1, color: context.palette.rule),
                        Expanded(child: preview),
                      ],
                    );
                  },
                ),
              ),
              Divider(height: 1, color: context.palette.rule),
              _Footer(
                problems: problems,
                saving: _saving,
                onCancel: _saving ? null : () => Navigator.of(context).pop(),
                onSave: problems.isEmpty && !_saving ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final session = _session;
    final catalogue = session.catalogue;
    final homes = [
      ...session.templateHomes,
      if (_original != null && _editing)
        for (final home in _original!.sources.keys)
          if (!session.templateHomes.contains(home)) home,
    ];
    final uses = _original == null || widget.duplicate
        ? const TemplateUses()
        : TemplateUses.of(catalogue, _original!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_fromDidacta) ...[
          Note(
            tr(
              'Esta viene con Didacta. Al guardar se escribe en tu '
              'repositorio con el mismo id, y a partir de ahí manda la '
              'tuya; la de serie se queda como está.',
            ),
            tone: context.palette.teacher,
          ),
          const SizedBox(height: 12),
        ],
        if (_creating && catalogue.templates.isEmpty) ...[
          Note(
            key: const Key('template-first'),
            tr(
              'Es la primera plantilla que se declara: con ella se escriben '
              'también las que trae Didacta, para que todo se siga compilando '
              'igual. Las que no quieras, se apagan.',
            ),
          ),
          const SizedBox(height: 12),
        ],
        _FormLabel(tr('Cómo se llama')),
        for (final code in _languages)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              key: Key('template-title-$code'),
              controller: _titles[code],
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                labelText:
                    [
                      for (final option in catalogue.languageOptions)
                        if (option.code == code) option.name,
                    ].firstOrNull ??
                    languageName(code),
                hintText: _original?.label,
              ),
            ),
          ),
        Text(
          tr(
            'Sin nombre no pasa nada: se enseña por lo que hace, '
            '«Diapositivas (sin pausas)».',
          ),
          style: TextStyle(fontSize: 11.5, color: context.palette.muted),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('template-id'),
          controller: _id,
          enabled: _creating,
          style: monoStyle.copyWith(fontSize: 12.5, color: context.palette.ink),
          decoration: InputDecoration(
            isDense: true,
            labelText: tr('Identificador'),
            hintText: _identifier.isEmpty ? 'apuntes-a5' : _identifier,
            errorText: _taken ? tr('ya hay una plantilla con este id') : null,
            helperText: tr(
              'Es lo que escriben los bloques y los temas que se compilan con '
              'ella. No se traduce y no se cambia.',
            ),
            helperMaxLines: 3,
          ),
        ),
        const SizedBox(height: 18),
        _FormLabel(tr('Qué produce')),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('template-class'),
                controller: _class,
                style: monoStyle.copyWith(
                  fontSize: 12.5,
                  color: context.palette.ink,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: tr('Clase de documento'),
                  hintText: 'article, book, beamer',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: const Key('template-options'),
                controller: _options,
                style: monoStyle.copyWith(
                  fontSize: 12.5,
                  color: context.palette.ink,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: tr('Opciones de la clase'),
                  hintText: '12pt,oneside',
                ),
              ),
            ),
          ],
        ),
        if (_beamerWithoutNoTheorems) ...[
          const SizedBox(height: 8),
          Note(
            key: const Key('template-notheorems'),
            tr(
              'Con beamer, añade notheorems a las opciones: si no, beamer '
              'define sus propios teoremas y chocan con los de Didacta. Lo '
              'llevan todas las diapositivas de serie.',
            ),
            tone: context.palette.teacher,
          ),
        ],
        const SizedBox(height: 12),
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
              onChanged: (value) {
                if (value == null) return;
                setState(() => _axes[key] = value);
                _changed();
              },
            ),
          ),
        SwitchListTile(
          key: const Key('template-active'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _active,
          onChanged: (value) => setState(() => _active = value),
          title: Text(tr('Encendida'), style: const TextStyle(fontSize: 13)),
          subtitle: Text(
            tr(
              'Apagada se queda declarada, con su cabecera, y fuera de lo que '
              'se compila.',
            ),
            style: TextStyle(fontSize: 11.5, color: context.palette.muted),
          ),
        ),
        const SizedBox(height: 14),
        _FormLabel(tr('Su cabecera de LaTeX')),
        Container(
          decoration: BoxDecoration(
            color: context.palette.surface,
            border: Border.all(color: context.palette.rule),
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          constraints: const BoxConstraints(minHeight: 110, maxHeight: 260),
          child: SingleChildScrollView(
            child: TexField(
              key: const Key('template-preamble-text'),
              controller: _preamble,
              minLines: 5,
              hintText: '\\usepackage{lmodern}\n\\geometry{margin=2cm}',
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tr(
            'Se lee al final del preámbulo de Didacta, así que aquí se puede '
            'redefinir lo que Didacta acaba de definir: los márgenes, los '
            'colores, un entorno. No lleva \\documentclass ni '
            '\\begin{document}: de eso ya se encarga la plantilla.',
          ),
          style: TextStyle(fontSize: 11.5, color: context.palette.muted),
        ),
        const SizedBox(height: 18),
        _FormLabel(tr('En qué repositorios está')),
        if (homes.isEmpty)
          Note(
            tr(
              'No hay ningún repositorio abierto en el que se pueda escribir, '
              'ni carpeta del programa.',
            ),
          )
        else
          Wrap(
            key: const Key('template-editor-homes'),
            spacing: 10,
            runSpacing: 6,
            children: [
              for (final home in homes)
                TemplateHomeSwitch(
                  key: Key('template-editor-in-$home'),
                  session: session,
                  home: home,
                  on: _homes.contains(home),
                  enabled: session.templateHomes.contains(home),
                  onTap: () => setState(() {
                    if (!_homes.remove(home)) _homes.add(home);
                  }),
                ),
            ],
          ),
        const SizedBox(height: 6),
        Text(
          tr(
            'Con uno basta: los demás repositorios la usan sin declararla. '
            'Tenerla también en otro hace que viaje con ese material; al '
            'guardar se escribe en todos los marcados.',
          ),
          style: TextStyle(fontSize: 11.5, color: context.palette.muted),
        ),
        if (_homes.contains(Session.programTemplates)) ...[
          const SizedBox(height: 6),
          Note(
            tr(
              'En el programa no la protege nadie: no está en git, no se '
              'sincroniza y se va con este ordenador. Hazte copias desde '
              'Ajustes, y si la plantilla es de la asignatura y no tuya, '
              'guárdala en su repositorio.',
            ),
            tone: context.palette.teacher,
          ),
        ],
        if (!_creating) ...[
          const SizedBox(height: 18),
          _FormLabel(tr('Dónde se usa')),
          _UsesList(
            uses: uses,
            session: session,
            onPreview: (unit) {
              setState(() => _unit = unit);
              unawaited(_compile());
            },
          ),
        ],
      ],
    );
  }
}

/// Qué se compila con ella, para saber qué cambia al guardar.
class _UsesList extends StatelessWidget {
  const _UsesList({
    required this.uses,
    required this.session,
    required this.onPreview,
  });

  final TemplateUses uses;
  final Session session;
  final ValueChanged<Unit> onPreview;

  @override
  Widget build(BuildContext context) {
    final language = session.language;
    final muted = TextStyle(fontSize: 12, color: context.palette.muted);
    if (uses.isEmpty) {
      return Text(
        tr(
          'No la nombra ningún bloque, lección ni documento. Se ofrece al '
          'compilar, pero nada sale con ella por defecto.',
        ),
        key: const Key('template-uses-none'),
        style: muted,
      );
    }
    Widget line(String label, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: context.palette.muted,
              ),
            ),
          ),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ],
      ),
    );
    return Column(
      key: const Key('template-uses'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (uses.blocks.isNotEmpty)
          line(
            tr('Bloques'),
            uses.blocks.map((block) => block.title(language)).join(', '),
          ),
        if (uses.inheriting.isNotEmpty)
          line(
            tr('Por defecto'),
            tr(
              '{0}: no dicen con qué plantillas se compilan, así que se '
              'compilan con todas las encendidas.',
              [
                uses.inheriting
                    .map((block) => block.title(language))
                    .join(', '),
              ],
            ),
          ),
        if (uses.documents.isNotEmpty)
          line(
            tr('Documentos'),
            [
              for (final (course, year, document) in uses.documents)
                '${document.title(language)} ($year · ${course.id})',
            ].join(', '),
          ),
        if (uses.units.isNotEmpty) ...[
          line(
            tr('Lecciones'),
            uses.units.length == 1
                ? tr('1 lección la pide aparte de su bloque:')
                : tr('{0} lecciones la piden aparte de su bloque:', [
                    uses.units.length,
                  ]),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 92),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final unit in uses.units.take(12))
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    tooltip: tr('Verla en la vista previa'),
                    label: Text(
                      unit.title(language),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    onPressed: () => onPreview(unit),
                  ),
                if (uses.units.length > 12)
                  Text(tr('y {0} más', [uses.units.length - 12]), style: muted),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// El color de un repositorio en las casillas.
///
/// El suyo, y si no tiene --con un repositorio solo abierto no se le asigna
/// ninguno-- uno de la lista por su posición: con cero la etiqueta sale
/// transparente y la casilla parece vacía.
int templateHomeColour(Session session, String home) {
  final colour = session.colourOf(home);
  if (colour != null && colour != 0) return colour;
  final at = session.workspace.repos.indexWhere((repo) => repo.id == home);
  return repoColours[(at < 0 ? 0 : at) % repoColours.length];
}

/// Si un sitio declara la plantilla: se pulsa para ponerla o quitarla.
///
/// Un repositorio con su color, o la carpeta del programa, que no es de
/// nadie y lo dice en el color de los avisos: lo que se guarda ahí no lo
/// protege git.
class TemplateHomeSwitch extends StatelessWidget {
  const TemplateHomeSwitch({
    super.key,
    required this.session,
    required this.home,
    required this.on,
    required this.enabled,
    required this.onTap,
  });

  final Session session;
  final String home;
  final bool on;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final program = home == Session.programTemplates;
    final label = program
        ? tr('programa')
        : (session.workspace.byId(home)?.label ?? home);
    final colour = program
        ? context.palette.teacher.toARGB32()
        : templateHomeColour(session, home);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Tooltip(
        message: !enabled
            ? tr('{0}: no se puede escribir en él', [label])
            : program
            ? (on
                  ? tr(
                      'Guardada en el programa, sin copia de seguridad. '
                      'Púlsalo para quitarla de ahí.',
                    )
                  : tr(
                      'Guardarla también en el programa: no la protege git y '
                      'se va con este ordenador.',
                    ))
            : on
            ? tr('Está en {0}. Púlsalo para quitarla de ahí.', [label])
            : tr('No está en {0}. Púlsalo para copiarla allí.', [label]),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(Radii.small),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  on ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 15,
                  color: on
                      ? context.palette.repo(colour)
                      : context.palette.muted,
                ),
                const SizedBox(width: 3),
                RepoChip(
                  colour: colour,
                  label: label,
                  compact: true,
                  muted: !on,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Las piezas del editor
// ---------------------------------------------------------------------------

bool get _mac => defaultTargetPlatform == TargetPlatform.macOS;

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.id,
    required this.fromDidacta,
    required this.onClose,
  });

  final String title;
  final String id;
  final bool fromDidacta;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 10, 12),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: context.palette.tint(context.palette.accent, 0.16),
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          child: Icon(
            Icons.picture_as_pdf_outlined,
            size: 17,
            color: context.palette.accentDark,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 1),
              Text(
                fromDidacta
                    ? tr(
                        'id: {0} · de Didacta: al guardar pasa a estar en tu '
                        'repositorio',
                        [id],
                      )
                    : tr('id: {0}', [id.isEmpty ? '—' : id]),
                style: TextStyle(fontSize: 11.5, color: context.palette.muted),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: tr('Cerrar sin guardar'),
          icon: const Icon(Icons.close, size: 18),
          onPressed: onClose,
        ),
      ],
    ),
  );
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.problems,
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final List<String> problems;
  final bool saving;
  final VoidCallback? onCancel;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 16, 12),
    child: Row(
      children: [
        Expanded(
          child: problems.isEmpty
              ? Text(
                  _mac
                      ? tr('⌘↵ compila la vista previa · ⌘S guarda')
                      : tr(
                          'Ctrl+Intro compila la vista previa · Ctrl+S guarda',
                        ),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.palette.muted,
                  ),
                )
              : Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 15,
                      color: context.palette.teacher,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        problems.first,
                        key: const Key('template-problem'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.palette.teacher,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(width: 12),
        TextButton(onPressed: onCancel, child: Text(tr('Cancelar'))),
        const SizedBox(width: 6),
        FilledButton.icon(
          key: const Key('template-save'),
          icon: saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check, size: 16),
          label: Text(tr('Guardar')),
          onPressed: onSave,
        ),
      ],
    ),
  );
}

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: context.palette.muted,
        letterSpacing: 0.7,
      ),
    ),
  );
}

/// La vista previa: la lección compilada con lo de la pantalla, o por qué no.
class _TemplatePreviewPane extends StatelessWidget {
  const _TemplatePreviewPane({
    required this.preview,
    required this.compiling,
    required this.stale,
    required this.unavailable,
    required this.revision,
    required this.units,
    required this.unit,
    required this.language,
    required this.onUnit,
    required this.onCompile,
  });

  final SnippetPreview? preview;
  final bool compiling;
  final bool stale;
  final bool unavailable;
  final int revision;
  final List<Unit> units;
  final Unit? unit;
  final String language;
  final ValueChanged<Unit> onUnit;
  final VoidCallback onCompile;

  @override
  Widget build(BuildContext context) {
    final result = preview;
    final status = unavailable
        ? tr('Sin compilar')
        : compiling
        ? tr('Compilando…')
        : result == null
        ? ''
        : !result.ok
        ? (result.engineFailed ? tr('Sin compilar') : tr('No compila'))
        : stale
        ? tr('Ha cambiado: se vuelve a compilar al parar de escribir')
        : tr('Compilado en {0} s', [
            result.seconds.toStringAsFixed(1).replaceAll('.', ','),
          ]);
    final current = unit;
    return Material(
      key: const Key('template-preview'),
      color: context.palette.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
            child: Row(
              children: [
                Text(
                  tr('VISTA PREVIA'),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: context.palette.muted,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    status,
                    key: const Key('template-preview-status'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: result != null && !result.ok && !compiling
                          ? context.palette.teacher
                          : context.palette.muted,
                    ),
                  ),
                ),
                if (current != null && units.length > 1)
                  PopupMenuButton<Unit>(
                    key: const Key('template-preview-unit'),
                    tooltip: tr('Con qué lección se mira'),
                    onSelected: onUnit,
                    itemBuilder: (context) => [
                      for (final each in units)
                        PopupMenuItem<Unit>(
                          value: each,
                          height: 34,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 22,
                                child: each.path == current.path
                                    ? const Icon(Icons.check, size: 14)
                                    : null,
                              ),
                              Flexible(
                                child: Text(
                                  each.title(language),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: context.palette.rule),
                        borderRadius: BorderRadius.circular(Radii.control),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.article_outlined,
                            size: 15,
                            color: context.palette.muted,
                          ),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Text(
                              current.title(language),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: context.palette.ink,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_drop_down,
                            size: 17,
                            color: context.palette.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                IconButton(
                  key: const Key('template-compile'),
                  tooltip: _mac
                      ? tr('Compilar ahora (⌘↵)')
                      : tr('Compilar ahora (Ctrl+Intro)'),
                  onPressed: compiling || unavailable ? null : onCompile,
                  icon: compiling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.palette.rule),
          Expanded(child: _content(context, result)),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, SnippetPreview? result) {
    if (unavailable) {
      return _Empty(
        icon: Icons.desktop_mac_outlined,
        text: unit == null
            ? tr(
                'No hay ninguna lección con la que mirarla: abre un '
                'repositorio con material. Se puede guardar igual.',
              )
            : tr(
                'Aquí no se puede compilar. La vista previa necesita la '
                'aplicación de escritorio, con el motor de Didacta y TeX: se '
                'puede guardar igual, y se comprueba al compilar.',
              ),
      );
    }
    if (result == null) {
      return _Empty(
        icon: Icons.visibility_outlined,
        text: compiling
            ? tr('Compilando la vista previa…')
            : tr('Aquí se verá una lección compilada con esta plantilla.'),
      );
    }
    if (!result.ok) {
      return ListView(
        key: const Key('template-preview-errors'),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 17,
                color: context.palette.teacher,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.engineFailed
                      ? tr(
                          'No se ha podido compilar: el motor no ha arrancado. '
                          'No es un error de la plantilla.',
                        )
                      : tr(
                          'No compila. Guardada así, no saldrá nada de lo que '
                          'se compile con ella.',
                        ),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: context.palette.teacher,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.palette.terminal,
              borderRadius: BorderRadius.circular(Radii.control),
            ),
            child: SelectableText(
              result.errors.isEmpty
                  ? tr('LaTeX no ha dicho por qué.')
                  : result.errors.join('\n\n'),
              style: monoStyle.copyWith(
                fontSize: 12,
                height: 1.4,
                color: didactaOnTerminal,
              ),
            ),
          ),
        ],
      );
    }
    final pdf = result.pdf;
    if (pdf == null) {
      return _Empty(
        icon: Icons.help_outline,
        text: tr('Ha compilado, pero no ha dejado ningún PDF.'),
      );
    }
    return Opacity(
      opacity: stale || compiling ? 0.55 : 1,
      child: ColoredBox(
        key: const Key('template-preview-pdf'),
        color: context.palette.pdfBackdrop,
        child: PdfViewer.file(
          pdf,
          key: ValueKey('$pdf#$revision'),
          params: PdfViewerParams(
            margin: 14,
            backgroundColor: context.palette.pdfBackdrop,
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: context.palette.faint),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: context.palette.muted,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
