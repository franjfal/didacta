/// Las propiedades de un documento: cómo se llama y qué puede salir de él.
///
/// Las dos cosas en el mismo diálogo porque es el mismo gesto --tocar este
/// documento-- y porque el segundo, en cualquier otro sitio, no lo encuentra
/// nadie.
///
/// **Lo de las plantillas es una restricción, no una preselección.** Lo que se
/// marque aquí es lo que se puede compilar de este documento; el diálogo de
/// compilar elige dentro de eso, para una vez. La diferencia importa: si
/// alguien decidió que de este tema no salen diapositivas --porque no caben,
/// porque no se proyecta-- el menú de compilar no es el sitio para saltárselo.
///
/// La lista son las plantillas que valen **donde vive este documento**: las que
/// declara su repositorio, las de los demás abiertos y, si no las declara
/// nadie, las que trae Didacta. Las que vienen de otro repositorio se marcan,
/// porque son las que fallan en la máquina de quien no lo tenga abierto.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';
import '../state/session.dart';
import 'theme.dart';

/// Lo que devuelve el diálogo.
class DocumentProperties {
  const DocumentProperties({required this.titles, required this.templates});

  final Map<String, String> titles;

  /// Qué se puede compilar. Vacía es «lo que digan sus bloques», que es el
  /// estado normal y el que tiene todo el material hasta que alguien decide
  /// otra cosa.
  final List<String> templates;
}

Future<DocumentProperties?> editDocumentProperties(
  BuildContext context, {
  required Session session,
  required Document document,
  required List<String> languages,
  required List<String> allowed,
}) => showDialog<DocumentProperties>(
  context: context,
  builder: (context) => _DocumentPropertiesDialog(
    session: session,
    document: document,
    languages: languages,
    allowed: allowed,
  ),
);

class _DocumentPropertiesDialog extends StatefulWidget {
  const _DocumentPropertiesDialog({
    required this.session,
    required this.document,
    required this.languages,
    required this.allowed,
  });

  final Session session;
  final Document document;
  final List<String> languages;

  /// Lo que se compila hoy de este documento: lo suyo, o lo de sus bloques.
  final List<String> allowed;

  @override
  State<_DocumentPropertiesDialog> createState() =>
      _DocumentPropertiesDialogState();
}

class _DocumentPropertiesDialogState extends State<_DocumentPropertiesDialog> {
  late final Map<String, TextEditingController> _titles = {
    for (final code in widget.languages)
      code: TextEditingController(text: widget.document.titles[code] ?? ''),
  };

  /// Si el documento restringe, o sigue a sus bloques.
  late bool _inherit = widget.document.profiles.isEmpty;

  /// Lo marcado. De partida, lo que se compila hoy -- así desmarcar una es
  /// quitar esa versión y no empezar de cero.
  late final Set<String> _picked = {...widget.allowed};

  @override
  void dispose() {
    for (final controller in _titles.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Lo que el documento restringe y **no se puede enseñar ahora**: plantillas
  /// apagadas, o declaradas por un repositorio que no está abierto.
  ///
  /// Se conservan al guardar. Si no, abrir estas propiedades con un
  /// repositorio cerrado y pulsar «Aceptar» borraría restricciones correctas
  /// sin que nadie las haya visto -- la misma regla que hace que apagar un
  /// repositorio no borre nada.
  List<String> get _invisible {
    final known = {
      for (final template in widget.session.catalogue.activeTemplates)
        template.id,
    };
    return [
      for (final id in widget.document.profiles)
        if (!known.contains(id)) id,
    ];
  }

  /// De qué bloques hereda, para poder decir qué pasa si no se restringe.
  List<String> get _inherited {
    final catalogue = widget.session.catalogue;
    final wanted = <String>{};
    for (final block in catalogue.blocksOf(widget.document)) {
      wanted.addAll(catalogue.templatesOfBlock(block));
    }
    return [
      for (final template in catalogue.activeTemplates)
        if (wanted.contains(template.id)) template.id,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final catalogue = session.catalogue;
    final available = catalogue.activeTemplates;
    final inherited = _inherited.toSet();

    return AlertDialog(
      title: const Text('Propiedades del documento'),
      content: SizedBox(
        width: 560,
        height: 560,
        child: ListView(
          children: [
            const SectionLabel('Título'),
            for (final code in widget.languages)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  key: Key('document-title-$code'),
                  controller: _titles[code],
                  autofocus: code == widget.document.language,
                  decoration: InputDecoration(
                    labelText: languageNameOf(session, code),
                    isDense: true,
                    helperText: (widget.document.titles[code] ?? '').isEmpty
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
              'fichero, no se borra el documento.',
            ),
            const SizedBox(height: 12),

            const SectionLabel('Qué se puede compilar'),
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                'Esto limita las versiones de este documento. Al compilar se '
                'elige entre las que queden, para esa vez.',
                style: TextStyle(fontSize: 11.5, color: didactaMuted),
              ),
            ),
            RadioGroup<bool>(
              groupValue: _inherit,
              onChanged: (value) => setState(() => _inherit = value ?? true),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioListTile<bool>(
                    key: const Key('document-templates-inherit'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: true,
                    title: const Text(
                      'Las de sus bloques',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    subtitle: Text(
                      inherited.isEmpty
                          ? 'Todavía no lleva lecciones, así que valen todas '
                                'las encendidas.'
                          : '${inherited.length} versión(es)',
                      style: const TextStyle(fontSize: 11, color: didactaMuted),
                    ),
                  ),
                  const RadioListTile<bool>(
                    key: Key('document-templates-pick'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: false,
                    title: Text('Solo estas', style: TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
            ),
            if (_invisible.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Note(
                  'Además está restringido a ${_invisible.join(', ')}, que no '
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
                  key: Key('document-template-${template.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _inherit
                      ? inherited.contains(template.id)
                      : _picked.contains(template.id),
                  enabled: !_inherit,
                  title: Text(
                    template.title(session.language),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  subtitle: Text(
                    _describe(session, template),
                    style: const TextStyle(fontSize: 11, color: didactaMuted),
                  ),
                  onChanged: (on) => setState(() {
                    if (on ?? false) {
                      _picked.add(template.id);
                    } else {
                      _picked.remove(template.id);
                    }
                  }),
                ),
            const SizedBox(height: 6),
            const Note(
              'Las plantillas se escriben en Ajustes. Aquí solo se dice '
              'cuáles valen para este documento.',
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
          key: const Key('document-properties-save'),
          // Sin ninguna marcada no se puede restringir: sería un documento
          // del que no sale nada, y para eso está «las de sus bloques».
          onPressed: !_inherit && _picked.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  DocumentProperties(
                    titles: {
                      for (final entry in _titles.entries)
                        entry.key: entry.value.text.trim(),
                    },
                    templates: _inherit
                        ? const <String>[]
                        : [
                            for (final template in available)
                              if (_picked.contains(template.id)) template.id,
                            // Y lo que no se podía enseñar, intacto.
                            ..._invisible,
                          ],
                  ),
                ),
          child: const Text('Aceptar'),
        ),
      ],
    );
  }

  /// Qué es esta plantilla, en una línea: su id, lo que enseña de un
  /// ejercicio y --lo que importa aquí-- si la declara otro repositorio.
  ///
  /// Lo último no es un adorno: una versión que sale de una plantilla que
  /// declara el repositorio de al lado compila en esta máquina y no compila
  /// en la de quien solo tenga este.
  String _describe(Session session, OutputTemplate template) {
    final parts = <String>[template.id];
    if (template.givesAway) parts.add(template.shows);
    final elsewhere =
        template.declared &&
        !template.sources.containsKey(widget.document.repo);
    if (elsewhere) {
      final who = template.sources.keys
          .map(
            (repo) => repo == Session.programTemplates
                ? 'el programa'
                : (session.workspace.byId(repo)?.label ?? repo),
          )
          .join(', ');
      parts.add('la declara $who');
    }
    return parts.join(' · ');
  }
}

/// El nombre de un idioma, como lo dice el catálogo.
String languageNameOf(Session session, String code) {
  for (final option in session.catalogue.languageOptions) {
    if (option.code == code) return option.name;
  }
  return code;
}
