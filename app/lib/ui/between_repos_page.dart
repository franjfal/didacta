/// Lo que solo puede ir mal con más de un repositorio abierto.
///
/// Dos comprobaciones, y ninguna la puede hacer el motor: `didacta check` mira
/// un repositorio, y desde allí el de al lado sencillamente no existe. Quien
/// tiene los dos delante es esta aplicación, así que es aquí donde se ven.
///
/// **Los metadatos que no coinciden.** Una asignatura repartida se declara en
/// los dos `course.yaml`, y los dos tienen que decir lo mismo. Si uno pone
/// «Análisis Matemático I» y el otro «Analisis Matematico I», el que se enseña
/// depende de en qué orden se abrieron los repositorios: el mismo material se
/// ve distinto en dos máquinas y nadie sabe cuál es el bueno.
///
/// **Las lecciones sin bloque.** Una lección dice a qué parte de la
/// asignatura pertenece --la teoría, los problemas-- y quién es cada bloque lo
/// declara un `taxonomy.yaml`, que puede ser el del repositorio de al lado.
/// Una lección que nombra un bloque que no declara ninguno de los abiertos se
/// ve entera, y eso es a propósito; pero el bloque sale por su id, y casi
/// siempre significa que falta abrir un repositorio o que alguien quitó el
/// bloque y dejó atrás sus lecciones.
///
/// **Los documentos que llaman fuera de su repositorio.** Un documento y las
/// unidades que compone tienen que vivir en el mismo: LaTeX resuelve las rutas
/// bajo una sola raíz, así que un documento que llama al de al lado compila en
/// la máquina que tiene los dos abiertos y no compila en la de quien solo
/// tiene uno. Eso no se descubre editando; se descubre cuando otra persona va
/// a dar la clase.
///
/// **Los snippets que no coinciden.** Un snippet que está en dos
/// repositorios es uno: el mismo `\begin{resumen}` tiene que salir igual
/// compile quien compile. Si uno cambió la definición y el otro no, sale
/// distinto según la máquina, y eso no lo ve nadie mirando un solo PDF.
///
/// Nada se resuelve solo. Son ficheros que pueden ser de otra persona, y
/// propagar el valor «más nuevo» por cuenta propia deshace el cambio de quien
/// todavía no lo ha enviado. Se enseña, se explica, y se pulsa.
///
/// La sección vivía en Ajustes, que es donde se pone lo que no tiene sitio.
/// Tiene sitio: es trabajo pendiente sobre el material, como las traducciones,
/// y en Ajustes no se entra a mirar si algo va mal.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';
import '../model/latex_snippets.dart';
import '../router.dart';
import '../state/session.dart';
import 'manage_blocks.dart';
import 'manage_snippets.dart';
import 'problem.dart';
import 'shell.dart';
import 'sync_bar.dart';
import 'theme.dart';
import '../l10n/tr.dart';

class BetweenReposPage extends StatelessWidget {
  const BetweenReposPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);
    final conflicts = session.catalogue.metadataConflicts;
    final crossing = session.catalogue.crossRepoUses;
    final orphans = session.catalogue.undeclaredBlocks;
    final snippets = session.snippetConflicts;
    final total =
        conflicts.length + crossing.length + orphans.length + snippets.length;

    return Column(
      children: [
        PageHeader(
          title: tr('Entre repositorios'),
          subtitle: total == 0
              ? tr('Todo cuadra')
              : tr('{0} cosa(s) por mirar', [total]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 28),
            children: [
              SectionLabel(tr('Metadatos que no coinciden')),
              _ConflictsSection(session: session),

              SectionLabel(tr('Lecciones sin bloque')),
              _OrphanBlocksSection(session: session, blocks: orphans),

              SectionLabel(tr('Documentos que llaman fuera')),
              _CrossingSection(session: session, uses: crossing),

              SectionLabel(tr('Snippets que no coinciden')),
              _SnippetsSection(session: session, conflicts: snippets),
            ],
          ),
        ),
      ],
    );
  }
}

/// Las lecciones que nombran un bloque que no declara nadie.
///
/// No es un error y no esconde nada: las lecciones se ven enteras, y el
/// bloque se enseña por su id. Eso es a propósito --quien no tenga el
/// repositorio donde alguien puso el nombre tiene que seguir viendo todo su
/// material-- pero casi siempre significa una de dos cosas, y las dos se
/// arreglan: falta abrir el repositorio que lo declara, o alguien quitó el
/// bloque y dejó atrás sus lecciones.
///
/// Las dos salidas están aquí: declararlo, o mandar sus lecciones a un bloque
/// que sí exista.
class _OrphanBlocksSection extends StatelessWidget {
  const _OrphanBlocksSection({required this.session, required this.blocks});

  final Session session;
  final List<String> blocks;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                'Cada lección dice a qué parte de la asignatura pertenece, y '
                'quién es cada bloque lo declara un `taxonomy.yaml` que puede '
                'estar en otro repositorio. Estas nombran uno que no declara '
                'ninguno de los abiertos: se ven enteras, pero el bloque sale '
                'por su id.',
              ),
              style: TextStyle(fontSize: 12.5, height: 1.45),
            ),
            const SizedBox(height: 10),
            if (blocks.isEmpty)
              Note(tr('Todas las lecciones tienen su bloque declarado.'))
            else ...[
              for (final id in blocks)
                _OrphanBlockRow(session: session, id: id),
              const SizedBox(height: 6),
              Note(
                tr(
                  'Si el bloque es de otra persona, lo que falta es abrir su '
                  'repositorio: declararlo aquí crea un segundo sitio donde '
                  'vive el mismo nombre, y entonces pueden discrepar.',
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

class _OrphanBlockRow extends StatelessWidget {
  const _OrphanBlockRow({required this.session, required this.id});

  final Session session;
  final String id;

  @override
  Widget build(BuildContext context) {
    final units = session.catalogue.unitsInBlock(id);
    final repos = {
      for (final unit in units)
        if (unit.repo.isNotEmpty) unit.repo,
    };
    final canWrite = session.workspace.repos.any(
      (repo) => session.canWriteIn(repo.id),
    );
    return Container(
      key: Key('orphan-block-$id'),
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
              Expanded(
                child: Text(
                  id,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (canWrite) ...[
                TextButton(
                  key: Key('declare-orphan-$id'),
                  onPressed: () => declareNamedBlock(context, session, id),
                  child: Text(tr('Declararlo')),
                ),
                if (session.catalogue.blocks.isNotEmpty)
                  TextButton(
                    key: Key('move-orphan-$id'),
                    onPressed: () => moveBlockLessons(context, session, id),
                    child: Text(tr('Mover sus lecciones')),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              Text(
                units.length == 1
                    ? tr('lo nombra 1 lección')
                    : tr('lo nombran {0} lecciones', [units.length]),
                style: TextStyle(fontSize: 11.5, color: context.palette.muted),
              ),
              Text(
                'en',
                style: TextStyle(fontSize: 11.5, color: context.palette.muted),
              ),
              for (final repo in repos)
                RepoChip(
                  colour: session.colourOf(repo) ?? 0xFF62697A,
                  label: session.workspace.byId(repo)?.label ?? repo,
                  compact: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Los documentos que componen una unidad de otro repositorio.
///
/// No se arregla desde aquí, y eso es honesto: arreglarlo es mover la unidad
/// --con su carpeta, sus idiomas y sus figuras-- o mover el documento, y las
/// dos cosas cambian dónde vive material que puede estar usando otra persona.
/// Lo que hace falta primero es saber que pasa y dónde.
class _CrossingSection extends StatelessWidget {
  const _CrossingSection({required this.session, required this.uses});

  final Session session;
  final List<CrossRepoUse> uses;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                'Un documento y las unidades que compone tienen que estar en el '
                'mismo repositorio. LaTeX las busca bajo una sola raíz, así que '
                'esto compila en tu máquina --que tiene los dos-- y no compila '
                'en la de quien solo tenga uno.',
              ),
              style: TextStyle(fontSize: 12.5, height: 1.45),
            ),
            const SizedBox(height: 10),
            if (uses.isEmpty)
              Note(tr('Ningún documento llama fuera de su repositorio.'))
            else ...[
              for (final use in uses) _CrossingRow(session: session, use: use),
              const SizedBox(height: 6),
              Note(
                tr(
                  'Se arregla moviendo la unidad al repositorio del documento, '
                  'o el documento al de la unidad. Las dos cosas cambian dónde '
                  'vive material que puede estar usando otra persona, así que '
                  'no se hacen desde aquí.',
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

class _CrossingRow extends StatelessWidget {
  const _CrossingRow({required this.session, required this.use});

  final Session session;
  final CrossRepoUse use;

  @override
  Widget build(BuildContext context) => Container(
    key: Key(
      'crossing-${use.course}-${use.year}-${use.document}-${use.reference}',
    ),
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
            Expanded(
              child: Text(
                '${use.course} · ${use.year} · ${use.document}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              key: Key('open-crossing-${use.document}-${use.reference}'),
              onPressed: () => goTo(
                context,
                Routes.document(use.course, use.year, use.document),
              ),
              child: Text(tr('Abrir')),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            Text(
              use.reference,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            Text(
              tr('está en'),
              style: TextStyle(fontSize: 11.5, color: context.palette.muted),
            ),
            RepoChip(
              colour: session.colourOf(use.unitRepo) ?? 0xFF62697A,
              label:
                  session.workspace.byId(use.unitRepo)?.label ?? use.unitRepo,
              compact: true,
            ),
            Text(
              tr('y el documento en'),
              style: TextStyle(fontSize: 11.5, color: context.palette.muted),
            ),
            RepoChip(
              colour: session.colourOf(use.documentRepo) ?? 0xFF62697A,
              label:
                  session.workspace.byId(use.documentRepo)?.label ??
                  use.documentRepo,
              compact: true,
            ),
          ],
        ),
      ],
    ),
  );
}

class _ConflictsSection extends StatelessWidget {
  const _ConflictsSection({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final conflicts = session.catalogue.metadataConflicts;
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
                  'Una asignatura --o un grado, o un bloque-- declarada en dos '
                  'repositorios tiene que decir lo mismo en los dos. Si no, lo '
                  'que se enseña depende de en qué orden se abrieron.',
                ),
                style: TextStyle(fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 10),
              if (conflicts.isEmpty)
                Note(tr('Todo coincide.'))
              else
                for (final conflict in conflicts)
                  _ConflictRow(session: session, conflict: conflict),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConflictRow extends StatelessWidget {
  const _ConflictRow({required this.session, required this.conflict});

  final Session session;
  final MetadataConflict conflict;

  @override
  Widget build(BuildContext context) => Container(
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
        Text(switch (conflict.about) {
          ConflictAbout.degree => tr(
            'Grado {0} · '
            '{1}',
            [conflict.course, conflict.fieldLabel],
          ),
          ConflictAbout.block => tr(
            'Bloque {0} · '
            '{1}',
            [conflict.course, conflict.fieldLabel],
          ),
          ConflictAbout.template => tr(
            'Plantilla {0} · '
            '{1}',
            [conflict.course, conflict.fieldLabel],
          ),
          ConflictAbout.course => '${conflict.course} · ${conflict.fieldLabel}',
        }, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        // Un botón por valor: el que se pulsa es el que se queda, y se
        // escribe en los demás. Nada de «el más nuevo gana»: son ficheros que
        // pueden ser de otra persona.
        for (final entry in conflict.values.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '«${entry.value}»',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                const SizedBox(width: 8),
                RepoChip(
                  colour: session.colourOf(entry.key) ?? 0xFF62697A,
                  label: session.workspace.byId(entry.key)?.label ?? entry.key,
                  compact: true,
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: Key(
                    'use-${conflict.course}-${conflict.field}-${entry.key}',
                  ),
                  onPressed: conflict.fixable
                      ? () => _use(context, entry.value)
                      : null,
                  child: Text(tr('Usar este')),
                ),
              ],
            ),
          ),
        if (!conflict.fixable)
          Note(switch (conflict.about) {
            ConflictAbout.degree => tr(
              'De un grado solo se puede igualar el título desde aquí. '
              'Lo demás, a mano en `degrees.yaml`.',
            ),
            ConflictAbout.block => tr(
              'De un bloque solo se puede igualar el nombre desde aquí. '
              'Lo demás, a mano en `taxonomy.yaml`.',
            ),
            ConflictAbout.template => tr(
              'De una plantilla solo se puede igualar el nombre desde aquí. '
              'La clase y las opciones se cambian editándola: cambiar a '
              'distancia qué PDF sale es algo que se mira antes de '
              'pulsar.',
            ),
            ConflictAbout.course => tr(
              'Este campo hay que igualarlo a mano: Didacta no sabe en '
              'qué línea de `course.yaml` se escribe.',
            ),
          }, tone: context.palette.teacher),
      ],
    ),
  );

  Future<void> _use(BuildContext context, String value) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Una asignatura y un grado se escriben en ficheros distintos, y el de
      // los grados es una lista: no se direcciona por clave, así que lo lleva
      // su propio escritor.
      final written = switch (conflict.about) {
        ConflictAbout.degree => await session.setDegreeTitles(
          id: conflict.course,
          titles: {conflict.language!: value},
        ),
        // Un bloque vive en la lista de `taxonomy.yaml`, que tampoco se
        // direcciona por clave: lo escribe [TaxonomyFile], que lo busca por
        // su id.
        ConflictAbout.block => await session.setBlockTitles(
          id: conflict.course,
          titles: {conflict.language!: value},
        ),
        // Y una plantilla, en la lista de `templates.yaml`.
        ConflictAbout.template => await session.setTemplateTitles(
          id: conflict.course,
          titles: {conflict.language!: value},
        ),
        ConflictAbout.course => await session.resolveMetadata(
          conflict: conflict,
          value: value,
        ),
      };
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            written == 0
                ? tr('No se ha podido escribir en ningún repositorio.')
                : written == 1
                ? tr('Igualado en un repositorio.')
                : tr('Igualado en {0} repositorios.', [written]),
          ),
        ),
      );
    } catch (error) {
      showProblemIn(messenger, error);
    }
  }
}

/// Los snippets que dos repositorios declaran distinto.
///
/// Uno a uno y entero, no campo a campo como los metadatos: un snippet es su
/// definición, su nombre y sus argumentos juntos, y quedarse con el rótulo de
/// uno y la definición de otro da un snippet que no ha escrito nadie. Se
/// elige de qué repositorio es el bueno, y ese se copia en los demás.
class _SnippetsSection extends StatelessWidget {
  const _SnippetsSection({required this.session, required this.conflicts});

  final Session session;
  final List<SnippetConflict> conflicts;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                'Un snippet declarado en dos repositorios tiene que decir lo '
                'mismo en los dos: si no, el mismo \\begin sale distinto según '
                'dónde se compile. Elige cuál es el bueno y se copia en los '
                'demás.',
              ),
              style: TextStyle(fontSize: 12.5, height: 1.45),
            ),
            const SizedBox(height: 10),
            if (conflicts.isEmpty)
              Note(tr('Todos los snippets dicen lo mismo en todas partes.'))
            else
              for (final conflict in conflicts)
                _SnippetConflictRow(session: session, conflict: conflict),
          ],
        ),
      ),
    ),
  );
}

class _SnippetConflictRow extends StatelessWidget {
  const _SnippetConflictRow({required this.session, required this.conflict});

  final Session session;
  final SnippetConflict conflict;

  @override
  Widget build(BuildContext context) {
    final entry = conflict.entry;
    return Container(
      key: Key('snippet-conflict-${conflict.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border.all(color: context.palette.rule),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.call_split, size: 15, color: context.palette.teacher),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tr(
                    'Snippet «{0}» · '
                    '{1}',
                    [entry.shown.label, conflict.differences.keys.join(', ')],
                  ),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    showSnippetEditor(context, session: session, entry: entry),
                child: Text(tr('Abrir')),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final field in conflict.differences.entries) ...[
            Text(
              field.key,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.palette.muted,
              ),
            ),
            const SizedBox(height: 3),
            for (final value in field.value.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: RepoChip(
                          colour: snippetRepoColour(session, value.key),
                          label:
                              session.workspace.byId(value.key)?.label ??
                              value.key,
                          compact: true,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value.value.isEmpty ? tr('(nada)') : value.value,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle.copyWith(
                          fontSize: 11.5,
                          color: value.value.isEmpty
                              ? context.palette.muted
                              : context.palette.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final repo in entry.byRepo.keys)
                OutlinedButton(
                  key: Key('use-snippet-${conflict.id}-from-$repo'),
                  onPressed: () => _use(context, repo),
                  child: Text(
                    tr(
                      'Quedarse con el de '
                      '{0}',
                      [session.workspace.byId(repo)?.label ?? repo],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _use(BuildContext context, String repo) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final written = await session.useSnippetFrom(id: conflict.id, repo: repo);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            written == 0
                ? tr('No se ha podido escribir en ningún repositorio.')
                : written == 1
                ? tr('Igualado en un repositorio.')
                : tr('Igualado en {0} repositorios.', [written]),
          ),
        ),
      );
    } catch (error) {
      showProblemIn(messenger, error);
    }
  }
}
