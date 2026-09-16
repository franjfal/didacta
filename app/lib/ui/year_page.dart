/// One academic year: the documents it is made of.
///
/// This is the composition view. What matters here is that a year holds no
/// content -- every line is a reference into `content/` or `problems/` -- so
/// the screen's job is to make the *selection and order* legible, and to say
/// when a reference points at nothing.
///
/// A broken reference is shown in place rather than skipped. A composition
/// that silently omits a missing unit looks complete and compiles short, which
/// is the failure that is hardest to notice.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/compiler.dart';
import '../data/content_gateway.dart';
import '../model/catalogue.dart';
import '../model/composition_file.dart';
import '../model/line_diff.dart';
import '../router.dart';
import '../state/session.dart';
import 'build_console.dart';
import 'commit_dialog.dart';
import 'course_admin_ui.dart';
import 'new_document.dart';
import 'pdf_dialog.dart';
import 'shell.dart';
import 'sync_bar.dart';
import 'build_button.dart';
import 'heading_title.dart';
import 'theme.dart';

class YearPage extends StatelessWidget {
  const YearPage({super.key, required this.courseId, required this.year});

  final String courseId;
  final String year;

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);
    final course = session.courseById(courseId);
    final entry = course?.years[year];

    if (course == null || entry == null) {
      return _NotHere(
        what: '$courseId · $year',
        hint:
            'No está en el catálogo. Puede que el año no exista todavía, o '
            'que el catálogo esté desactualizado (`didacta index`).',
      );
    }

    final references = entry.documents.fold<int>(
      0,
      (sum, document) => sum + document.unitRefs.length,
    );
    final broken = _brokenCount(entry, session);
    final crossing = [
      for (final use in session.catalogue.crossRepoUses)
        if (use.course == courseId && use.year == year) use,
    ];

    return Column(
      children: [
        PageHeader(
          title: '${course.title(session.language)} · $year',
          subtitle: [
            '${entry.documents.length} documentos',
            '$references referencias',
            if (entry.group != null) entry.group!,
            'idioma ${entry.language}',
          ].join(' · '),
          breadcrumbs: [('Asignaturas', Routes.courses())],
          actions: [
            if (session.admin() != null)
              IconButton(
                key: const Key('remove-year'),
                tooltip: 'Quitar este curso académico',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _removeYear(context, session, course),
              ),
          ],
        ),
        if (broken > 0)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Note(
              '$broken referencia(s) de esta composición no apuntan a ninguna '
              'unidad del catálogo. Se muestran en su sitio, no se omiten: una '
              'composición que se salta lo que falta parece completa y compila '
              'corta.',
              tone: didactaTeacher,
            ),
          ),
        // Lo que compila aquí y no compilaría en la máquina de al lado.
        if (crossing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Note(
              '${crossing.length} referencia(s) de este curso llaman a '
              'lecciones de otro repositorio. Compilan aquí, donde están los '
              'dos abiertos, y no compilan para quien solo tenga uno.\n\n'
              '${crossing.take(3).join('\n')}'
              '${crossing.length > 3 ? '\n…' : ''}',
              tone: didactaTeacher,
            ),
          ),
        Expanded(
          child: _Documents(
            // Con clave: cambiar de año tiene que recargar el fichero, y sin
            // esto el estado del anterior se quedaría pegado.
            key: ValueKey('${course.id}/$year'),
            course: course,
            year: year,
            entry: entry,
            session: session,
          ),
        ),
      ],
    );
  }

  int _brokenCount(CourseYear entry, Session session) {
    var broken = 0;
    for (final document in entry.documents) {
      for (final reference in document.unitRefs) {
        // En **su** repositorio. Resolverla contra el montón haría que una
        // unidad del de al lado pareciera estar en su sitio, que es justo lo
        // que rompe la compilación de quien solo tenga uno.
        if (session.catalogue.unitByReference(reference, repo: document.repo) ==
            null) {
          broken += 1;
        }
      }
    }
    return broken;
  }

  /// Quita este curso académico, y vuelve a la asignatura.
  ///
  /// Vuelve porque la pantalla en la que estás deja de existir: quedarse
  /// enseñando un curso borrado es peor que navegar.
  Future<void> _removeYear(
    BuildContext context,
    Session session,
    Course course,
  ) async {
    final admin = session.admin();
    if (admin == null) return;

    final onlyOne = course.years.length == 1;
    final confirmed = await confirmRemoval(
      context,
      title: '¿Quitar el curso $year de «${course.title(session.language)}»?',
      preview: () => admin.previewRemoveYear(course.id, year),
      warning: onlyOne
          ? 'Es el único curso de la asignatura, así que se queda sin '
                'ninguno. Las unidades no se tocan: lo que se pierde es la '
                'selección y el orden de este curso.'
          : 'Las unidades no se tocan, y los demás cursos de la asignatura '
                'tampoco. Lo que se pierde es la selección y el orden de '
                'este.',
    );
    if (!confirmed || !context.mounted) return;

    final done = await runAdmin(
      context,
      session,
      (admin) => admin.removeYear(course.id, year),
      done: 'Curso $year quitado como un commit.',
    );
    if (!done || !context.mounted) return;
    await session.reloadCatalogue();
    if (context.mounted) context.go(Routes.courses());
  }
}

/// Los grupos de contenido de un año: su orden, y los que hay.
///
/// La misma idea que el editor de composición pero un nivel más arriba. Un
/// año es una lista de documentos --temas, hojas de problemas, seminarios--
/// y reordenarlos es una edición tan normal como reordenar las unidades de
/// dentro: el tema 3 pasa a darse antes que el 2, y el fichero tiene que
/// decirlo.
///
/// Mueve **bloques enteros de `year.yaml`**, comentarios incluidos, y guarda
/// como un commit con su diff delante, igual que todo lo demás.
class _Documents extends StatefulWidget {
  const _Documents({
    super.key,
    required this.course,
    required this.year,
    required this.entry,
    required this.session,
  });

  final Course course;
  final String year;
  final CourseYear entry;
  final Session session;

  /// El repositorio cuyo `year.yaml` se edita.
  ///
  /// Con varios abiertos, un año puede tener temas de más de uno: cada uno
  /// tiene su `year.yaml` y el orden vive dentro de cada fichero, así que
  /// reordenar cruzando repositorios no es una operación que exista. Se edita
  /// el del primero que aporte algo, y los demás se ven con su color.
  String get repo => entry.documents.isEmpty ? '' : entry.documents.first.repo;

  String get path => 'courses/${course.id}/$year/year.yaml';

  @override
  State<_Documents> createState() => _DocumentsState();
}

class _DocumentsState extends State<_Documents> {
  /// Un `year.yaml` por repositorio que aporte algo al año.
  ///
  /// Todos a la vez y no uno elegido, que es lo que había: con uno, la
  /// pantalla enseñaba media asignatura y cambiar de repositorio parecía
  /// navegar a otro sitio. Son dos fuentes de **una** composición, así que se
  /// leen las dos y se escribe en la que toque según el documento que se
  /// mueva. El orden vive dentro de cada fichero, así que es lo único que no
  /// cruza: arrastrar ordena entre los del mismo repositorio.
  final Map<String, ContentFile> _files = {};
  final Map<String, String> _text = {};
  final Map<String, String> _loaded = {};

  /// El orden en pantalla, por repositorio. Sale del fichero y no del
  /// catálogo: el catálogo se genera aparte y puede ir por detrás de lo que
  /// se acaba de guardar.
  final Map<String, List<String>> _order = {};

  bool _loading = true;
  bool _saving = false;
  Object? _error;

  /// Los repositorios que aportan algo a este año, en el orden del espacio de
  /// trabajo: es el que da el mismo resultado en todas las pantallas.
  ///
  /// Los que el espacio de trabajo no conoce van detrás en lugar de caerse.
  /// Quien manda en qué hay que enseñar es el catálogo, y un documento cuyo
  /// repositorio no se reconozca sigue siendo un documento: desaparecer de la
  /// pantalla es la única respuesta que no vale.
  List<String> get _repos {
    // `widget.entry` ya viene filtrado, así que un repositorio apagado no
    // aporta nada y su `year.yaml` no se abre. Eso es lo que hace que apagar
    // sea apagar: leerlo igual dejaba sus documentos en la lista del fichero
    // y fuera del catálogo, que es exactamente la forma que tiene un
    // documento recién creado -- y salían en gris, como si estuvieran a
    // medias.
    final aporta = widget.entry.repos;
    final ordered = [
      for (final repo in widget.session.workspace.repos)
        if (aporta.contains(repo.id)) repo.id,
    ];
    return [
      ...ordered,
      for (final repo in aporta)
        if (!ordered.contains(repo)) repo,
    ];
  }

  Iterable<String> get _dirtyRepos => [
    for (final repo in _text.keys)
      if (_text[repo] != _loaded[repo]) repo,
  ];

  bool get _dirty => _dirtyRepos.isNotEmpty;

  String _pathIn(String repo) =>
      'courses/${widget.course.id}/${widget.year}/year.yaml';

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_load);
    scheduleMicrotask(_loadOutputs);
  }

  @override
  void didUpdateWidget(_Documents old) {
    super.didUpdateWidget(old);
    // Apagar un repositorio cambia qué composiciones hay abiertas. Se quitan
    // las que sobran y se traen las que falten, en vez de recargarlo todo:
    // recargar se llevaría por delante lo que estuviera sin guardar en las
    // demás, y filtrar no es motivo para perder una edición.
    final want = _repos.toSet();
    final have = _files.keys.toSet();
    if (want.length == have.length && want.containsAll(have)) return;
    setState(() {
      for (final gone in have.difference(want)) {
        _files.remove(gone);
        _text.remove(gone);
        _loaded.remove(gone);
        _order.remove(gone);
      }
    });
    final missing = want.difference(have);
    if (missing.isNotEmpty) scheduleMicrotask(() => _loadInto(missing));
  }

  /// Trae las composiciones de [repos] sin tocar las que ya están abiertas.
  Future<void> _loadInto(Set<String> repos) async {
    for (final repo in repos) {
      try {
        final file = await widget.session.gatewayFor(repo).read(_pathIn(repo));
        if (!mounted) return;
        setState(() {
          _files[repo] = file;
          _text[repo] = file.text;
          _loaded[repo] = file.text;
          _order[repo] = CompositionFile(file.text).documentIds();
        });
      } catch (_) {
        // Uno que no se deja leer no puede con los demás.
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final files = <String, ContentFile>{};
    Object? failure;
    for (final repo in _repos) {
      try {
        files[repo] = await widget.session.gatewayFor(repo).read(_pathIn(repo));
      } catch (thrown) {
        // Uno que no se deja leer no puede llevarse por delante a los demás:
        // es la misma regla que abrir repositorios.
        failure ??= thrown;
      }
    }
    if (!mounted) return;
    setState(() {
      _files
        ..clear()
        ..addAll(files);
      _text
        ..clear()
        ..addAll({for (final e in files.entries) e.key: e.value.text});
      _loaded
        ..clear()
        ..addAll({for (final e in files.entries) e.key: e.value.text});
      _order
        ..clear()
        ..addAll({
          for (final e in files.entries)
            e.key: CompositionFile(e.value.text).documentIds(),
        });
      _error = files.isEmpty ? failure : null;
      _loading = false;
    });
  }

  /// Aplica un cambio al fichero de un repositorio, o dice por qué no.
  void _edit(
    String repo,
    void Function(CompositionFile file) change, {
    String? failure,
  }) {
    final composition = CompositionFile(_text[repo] ?? '');
    try {
      change(composition);
    } on CompositionException catch (thrown) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${failure ?? 'No se ha tocado el fichero'}: ${thrown.message}',
          ),
          backgroundColor: didactaTeacher,
          duration: const Duration(seconds: 7),
        ),
      );
      return;
    }
    setState(() {
      _text[repo] = composition.text;
      _order[repo] = CompositionFile(composition.text).documentIds();
    });
  }

  /// Reordena dentro de una tarjeta, sin tocar lo que hay fuera de ella.
  ///
  /// Un tema no tiene por qué ocupar posiciones seguidas en el `year.yaml`
  /// --sus documentos pueden estar repartidos, y uno puede pertenecer a dos
  /// temas--, así que no se mueve un elemento de la lista global: se toman
  /// **las posiciones que ocupan estos ids** y se rellenan con ellos en el
  /// orden nuevo. Lo de en medio se queda donde estaba.
  void _reorderWithin(String repo, List<String> ids, int from, int to) {
    if (from == to || ids.length < 2) return;
    final order = _order[repo];
    if (order == null) return;
    final moved = [...ids];
    moved.insert(to, moved.removeAt(from));

    final slots = [
      for (var index = 0; index < order.length; index += 1)
        if (ids.contains(order[index])) index,
    ];
    if (slots.length != moved.length) return;

    final next = [...order];
    for (var index = 0; index < slots.length; index += 1) {
      next[slots[index]] = moved[index];
    }
    _edit(repo, (file) => file.setDocumentOrder(next));
  }

  /// Los temas y lo que va en cada uno, listos para dibujar.
  ///
  /// El catálogo manda en qué hay y cómo se agrupa --junta los repositorios,
  /// que es de lo que trata esto-- y el fichero abierto manda el orden de lo
  /// suyo: es lo que hace que arrastrar se vea antes de guardar. Un documento
  /// que está en el fichero y todavía no en el índice --recién creado-- sale
  /// suelto hasta el próximo `didacta index`, porque quién lo agrupa lo dice
  /// el índice.
  List<_CardGroup> _groups(Map<String, Document> byId) {
    final groups = [
      for (final group in widget.entry.byTheme) _CardGroup.from(group, _repos),
    ];

    // Los recién creados: están en un fichero y todavía no en el índice. El
    // tema al que pertenecen lo dice **el fichero**, que acaba de escribirlo,
    // así que van a su tarjeta y no a un limbo al final de la pantalla --
    // crear un documento en el Tema 1 y verlo aparecer debajo de todo, sin
    // nombre, parecía que hubiera salido mal.
    for (final entry in _drafts.entries) {
      for (final draft in entry.value) {
        if (byId.containsKey(draft.id)) continue;
        final theme = draft.themes.isEmpty ? null : draft.themes.first;
        var target = groups
            .where((group) => group.theme?.id == theme)
            .firstOrNull;
        if (target == null && theme == null) {
          target = groups.where((group) => group.isLoose).firstOrNull;
        }
        if (target == null) {
          // Su tema no está declarado en ningún repositorio abierto: sale
          // suelto, como cualquier otro documento en ese caso.
          target = _CardGroup.pending(const {});
          groups.add(target);
        }
        target.pending.putIfAbsent(entry.key, () => []).add(draft.id);
      }
    }

    // El orden en vivo de cada fichero, que es lo que hace que arrastrar se
    // vea antes de guardar.
    for (final group in groups) {
      for (final entry in group.byRepo.entries) {
        final order = _order[entry.key];
        if (order == null) continue;
        final rank = {for (var i = 0; i < order.length; i += 1) order[i]: i};
        entry.value.sort((a, b) => (rank[a] ?? 0).compareTo(rank[b] ?? 0));
      }
    }
    return groups;
  }

  /// Lo que hay compilado de cada documento de este curso.
  ///
  /// Se pregunta al motor una vez por curso, no documento por documento: es
  /// lo que decide si cada fila enseña el atajo de ver el PDF, y treinta
  /// procesos para dibujar una lista no es una opción.
  Map<String, List<ExistingOutput>> _outputs = const {};

  /// De todos los repositorios que aportan algo a este curso, no del primero.
  ///
  /// Cada uno compila en su propia carpeta de salida, así que preguntando solo
  /// al primero la mitad de los documentos de una asignatura partida salen sin
  /// icono de PDF aunque estén compilados. No se notaba mientras el visor
  /// enseñaba un idioma: se notó al enseñar los que hay.
  Future<void> _loadOutputs() async {
    final found = <String, List<ExistingOutput>>{};
    for (final repo in _repos) {
      final compiler = widget.session.compiler(repo: repo);
      if (compiler == null) continue;
      try {
        final mine = await compiler.documentOutputs(
          '${widget.course.id}@${widget.year}',
        );
        for (final entry in mine.entries) {
          (found[entry.key] ??= []).addAll(entry.value);
        }
      } catch (_) {
        // No poder saberlo quita un atajo, no una pantalla. Y que un
        // repositorio no conteste no puede dejar sin atajos a los demás.
      }
    }
    if (!mounted) return;
    setState(() => _outputs = found);
  }

  /// Lo que cada fichero abierto dice de sus documentos.
  ///
  /// Se lee del texto en vivo y no del catálogo: es lo único que sabe de un
  /// documento en los segundos que van desde crearlo hasta guardarlo y
  /// reindexar.
  Map<String, List<DocumentDraft>> get _drafts => {
    for (final entry in _text.entries)
      entry.key: CompositionFile(entry.value).documentDrafts(),
  };

  /// Los temas plegados. Una decisión del sitio de trabajo, no de la pantalla:
  /// quien no da el Tema 3 este año lo pliega una vez, no cada mañana.
  Set<String> get _collapsed =>
      widget.session.collapsedThemes(widget.course.id, widget.year);

  bool _isCollapsed(_CardGroup group) =>
      group.theme != null && _collapsed.contains(group.theme!.id);

  void _toggleCollapsed(_CardGroup group) {
    final theme = group.theme;
    if (theme == null) return;
    unawaited(
      widget.session.setThemeCollapsed(
        course: widget.course.id,
        year: widget.year,
        theme: theme.id,
        collapsed: !_collapsed.contains(theme.id),
      ),
    );
  }

  /// Crea un documento, dentro de un tema o suelto.
  Future<void> _add({String? theme}) async {
    // Dónde se crea. Con varios repositorios hay que decirlo, porque el
    // documento vive entero en uno: se compila contra su raíz y referencia
    // unidades suyas. Con uno, no hay nada que preguntar.
    final repo = await _whereToWrite();
    if (repo == null || !mounted) return;

    final draft = await showDialog<NewDocument>(
      context: context,
      builder: (context) => NewDocumentDialog(
        taken: [for (final ids in _order.values) ...ids],
        language: widget.session.language,
        languages: widget.session.catalogue.languages,
      ),
    );
    if (draft == null || !mounted) return;
    _edit(
      repo,
      (file) => file.addDocument(
        id: draft.id,
        kind: draft.kind,
        title: draft.title,
        themes: theme == null ? const [] : [theme],
      ),
    );
  }

  /// Declara un tema en este curso.
  ///
  /// Escribe en `themes.yaml` y no en el `year.yaml`, así que pasa por el
  /// motor y queda en un commit como el resto de operaciones de estructura.
  Future<void> _addTheme() async {
    final repo = await _whereToWrite();
    if (repo == null || !mounted) return;

    final draft = await showDialog<NewTheme>(
      context: context,
      builder: (context) => NewThemeDialog(
        taken: [for (final theme in widget.entry.themes) theme.id],
        language: widget.session.language,
      ),
    );
    if (draft == null || !mounted) return;

    final done = await runAdmin(
      context,
      widget.session,
      (admin) => admin.createTheme(
        course: widget.course.id,
        year: widget.year,
        id: draft.id,
        title: draft.title,
        language: widget.session.language,
      ),
      repo: repo,
      done: 'Tema «${draft.title}» creado.',
    );
    if (done) await widget.session.reloadCatalogue();
  }

  /// Los repositorios donde se puede escribir en este curso.
  ///
  /// Los que ya aportan algo; y si no aporta ninguno --un curso recién
  /// creado, o un tema recién declarado y todavía vacío-- los que estén
  /// abiertos. Sin esto, un año sin documentos no dejaba crear el primero:
  /// no había de dónde sacar en qué repositorio escribirlo.
  List<String> get _writable {
    final repos = _repos;
    if (repos.isNotEmpty) return repos;
    return [for (final repo in widget.session.workspace.repos) repo.id];
  }

  /// Compila lo que cuelga de un tema, o el curso entero.
  ///
  /// Todas las versiones de cada documento: es lo que se quiere al darle a
  /// compilar sobre un bloque, y elegir cuáles sería otra pantalla.
  /// Los idiomas de esta asignatura, con su nombre, para el menú de compilar.
  List<LanguageOption> get _buildLanguages => buildLanguagesOf(
    declared: widget.course.languages,
    known: widget.session.catalogue.languageOptions,
    fallback: widget.session.language,
  );

  /// Cómo se llama el idioma en el que se está trabajando.
  String _currentLanguageName() {
    final current = widget.session.language;
    for (final option in _buildLanguages) {
      if (option.code == current) return option.name;
    }
    // El de la barra puede no ser de esta asignatura; entonces se compila el
    // primero suyo, y el botón dice ese.
    return _buildLanguages.first.name;
  }

  /// Lo que compila una pulsación corta: el idioma actual si la asignatura lo
  /// da, y si no el primero que dé.
  List<String> _tapLanguages() {
    final current = widget.session.language;
    final options = _buildLanguages;
    return options.any((option) => option.code == current)
        ? [current]
        : [options.first.code];
  }

  Future<void> _buildAll({
    String? theme,
    String? document,
    List<String> languages = const [],
  }) async {
    final entry = widget.entry;
    final wanted = [
      for (final candidate in entry.documents)
        if (document != null
            ? candidate.id == document
            : theme == null || candidate.themes.contains(theme))
          (
            repo: candidate.repo,
            course: widget.course.id,
            year: widget.year,
            id: candidate.id,
            title: candidate.title(widget.session.language),
          ),
    ];
    if (wanted.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aquí no hay nada que compilar todavía.')),
      );
      return;
    }

    final what = document != null
        ? wanted.single.title
        : theme == null
        ? '${widget.course.title(widget.session.language)} · ${widget.year}'
        : entry.themes
                  .where((t) => t.id == theme)
                  .map((t) => t.title(widget.session.language))
                  .firstOrNull ??
              theme;

    final console = widget.session.buildConsole;
    unawaited(showBuildConsole(context, console));
    await widget.session.buildDocuments(
      wanted,
      title: what,
      languages: languages,
    );
    // Lo que acaba de salir, para que los atajos de ver el PDF aparezcan sin
    // tener que volver a entrar.
    await _loadOutputs();
  }

  /// El título de un tema, en todos los idiomas a la vez.
  ///
  /// Se escribe en el `themes.yaml` del repositorio que lo declara, que es
  /// **uno**: los demás solo lo nombran desde sus documentos. Esa asimetría
  /// es lo que permite que quien no tenga ese repositorio siga viendo todo el
  /// material, suelto.
  Future<void> _editThemeTitle(CourseTheme theme) async {
    final titles = await editHeadingTitles(
      context,
      heading: 'tema',
      languages: [for (final option in _buildLanguages) option.code],
      titles: theme.titles,
      reference: widget.entry.language,
      note:
          'Un idioma en blanco se queda marcado como pendiente en el fichero, '
          'no se borra el tema.',
    );
    if (titles == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.session.setThemeTitles(
        repo: theme.repo,
        course: widget.course.id,
        year: widget.year,
        id: theme.id,
        titles: titles,
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Título del tema cambiado, como un commit.'),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  /// El título de un documento, en todos los idiomas a la vez.
  Future<void> _editDocumentTitle(Document document) async {
    final repo = _repoOf(document.id) ?? document.repo;
    final titles = await editHeadingTitles(
      context,
      heading: 'documento',
      languages: [for (final option in _buildLanguages) option.code],
      titles: document.titles,
      reference: document.language,
      note:
          'Un idioma en blanco se queda marcado como pendiente en el fichero, '
          'no se borra el documento.',
    );
    if (titles == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.session.setDocumentTitles(
        repo: repo,
        course: widget.course.id,
        year: widget.year,
        id: document.id,
        titles: titles,
      );
      // El `year.yaml` que esta pantalla tiene abierto acaba de cambiar en
      // disco; sin releerlo, el siguiente guardado escribiría encima con el
      // título viejo.
      await _loadInto({repo});
      messenger.showSnackBar(
        const SnackBar(content: Text('Título cambiado, como un commit.')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  /// Abre lo compilado de un documento, con una pestaña por versión.
  Future<void> _openPdfs(String id, String title) async {
    final outputs = _outputs[id] ?? const <ExistingOutput>[];
    if (outputs.isEmpty) return;
    final compiler = widget.session.compiler(repo: _repoOf(id));
    await showBuiltPdfs(
      context,
      title: title,
      outputs: outputs,
      // El de la barra de arriba sale elegido, que es en el que se está
      // trabajando; si de ese no hay nada compilado, el primero que haya.
      language: widget.session.language,
      languages: _buildLanguages,
      onOpenExternally: compiler == null
          ? null
          : (path) => unawaited(compiler.open(path)),
    );
  }

  /// En qué repositorio se escribe. Se pregunta solo si hay más de uno.
  Future<String?> _whereToWrite() async {
    final repos = _writable;
    if (repos.length == 1) return repos.single;
    return pickRepository(context, widget.session);
  }

  /// En qué `year.yaml` está un documento.
  String? _repoOf(String id) {
    for (final entry in _order.entries) {
      if (entry.value.contains(id)) return entry.key;
    }
    return null;
  }

  Future<void> _remove(String id, String title) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Quitar «$title»?'),
        content: const SizedBox(
          width: 420,
          child: Text(
            'Se va el grupo y su composición: qué unidades llevaba y en qué '
            'orden. Las unidades no se tocan, siguen en la biblioteca y en '
            'los demás grupos que las usen.\n\n'
            'Queda como un commit, así que se puede revertir.',
            style: TextStyle(fontSize: 12.5, height: 1.45),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirm-remove-document'),
            style: FilledButton.styleFrom(backgroundColor: didactaTeacher),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final repo = _repoOf(id);
    if (repo != null) _edit(repo, (file) => file.removeDocument(id));
  }

  /// Guarda lo que se haya tocado: un commit por repositorio.
  ///
  /// Uno por repositorio y no uno solo porque son ficheros de historiales
  /// distintos. Con uno tocado --lo normal-- esto es exactamente lo de
  /// siempre: un diálogo y un commit.
  Future<void> _save() async {
    for (final repo in _dirtyRepos.toList()) {
      final before = _loaded[repo] ?? '';
      final after = _text[repo] ?? '';
      final message = await showDialog<String>(
        context: context,
        builder: (context) => CommitDialog(
          before: before,
          after: after,
          suggested: _suggested(repo),
        ),
      );
      if (message == null || !mounted) return;

      setState(() => _saving = true);
      try {
        final sha = await widget.session
            .gatewayFor(repo)
            .commit(
              path: _pathIn(repo),
              text: after,
              sha: _files[repo]?.sha ?? '',
              message: message,
            );
        if (!mounted) return;
        setState(() {
          _loaded[repo] = after;
          _files[repo] = ContentFile(
            path: _pathIn(repo),
            text: after,
            sha: sha,
          );
          _saving = false;
        });
      } on ContentException catch (thrown) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(thrown.message),
            backgroundColor: didactaTeacher,
            duration: const Duration(seconds: 6),
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('year.yaml guardado como un commit.')),
    );
    await widget.session.reloadCatalogue();
  }

  /// Qué ha cambiado, en palabras.
  String _suggested(String repo) {
    final before = CompositionFile(_loaded[repo] ?? '').documentIds();
    final now = _order[repo] ?? const <String>[];
    final added = now.where((id) => !before.contains(id)).toList();
    final gone = before.where((id) => !now.contains(id)).toList();
    final where = '${widget.course.id} ${widget.year}';

    if (added.length == 1 && gone.isEmpty) {
      return 'Añadir el grupo ${added.first} a $where';
    }
    if (gone.length == 1 && added.isEmpty) {
      return 'Quitar el grupo ${gone.first} de $where';
    }
    if (added.isEmpty && gone.isEmpty) {
      return 'Cambiar el orden de los grupos de $where';
    }
    return 'Cambiar los grupos de $where';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _LoadFailed(
        error: _error!,
        path: _pathIn(_repos.firstOrNull ?? ''),
        onRetry: _load,
      );
    }

    final session = widget.session;
    final canWrite = _writable.any(session.canWriteIn);
    var added = 0;
    var removed = 0;
    for (final repo in _dirtyRepos) {
      final size = diffSize(_loaded[repo] ?? '', _text[repo] ?? '');
      added += size.added;
      removed += size.removed;
    }
    final byId = {
      for (final document in widget.entry.documents) document.id: document,
    };
    final draftsById = {
      for (final list in _drafts.values)
        for (final draft in list) draft.id: draft,
    };

    return Column(
      children: [
        if (_dirty || _saving)
          _SaveBar(
            added: added,
            removed: removed,
            saving: _saving,
            onDiscard: _saving
                ? null
                : () => setState(() {
                    for (final repo in _text.keys.toList()) {
                      final original = _loaded[repo] ?? '';
                      _text[repo] = original;
                      _order[repo] = CompositionFile(original).documentIds();
                    }
                  }),
            onSave: canWrite && !_saving ? _save : null,
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 72),
            children: [
              for (final group in _groups(byId))
                _ThemeCard(
                  key: ValueKey('theme-${group.theme?.id ?? 'loose'}'),
                  group: group,
                  course: widget.course,
                  year: widget.year,
                  session: session,
                  collapsed: _isCollapsed(group),
                  canWrite: canWrite,
                  drafts: draftsById,
                  outputs: _outputs,
                  onBuild: (languages) =>
                      _buildAll(theme: group.theme?.id, languages: languages),
                  onBuildDocument: (id, languages) =>
                      _buildAll(document: id, languages: languages),
                  buildLanguages: _buildLanguages,
                  onEditTitle:
                      group.theme != null &&
                          widget.session.canWriteIn(group.theme!.repo)
                      ? () => _editThemeTitle(group.theme!)
                      : null,
                  onEditDocumentTitle: canWrite ? _editDocumentTitle : null,
                  onOpenPdfs: _openPdfs,
                  onToggle: () => _toggleCollapsed(group),
                  onReorder: _reorderWithin,
                  onRemove: (id, title) => _remove(id, title),
                  onAdd: () => _add(theme: group.theme?.id),
                ),
            ],
          ),
        ),
        if (canWrite)
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: didactaPanel,
              border: Border(top: BorderSide(color: didactaRule)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            // En `Wrap` y no en `Row`: en una pantalla estrecha los dos
            // botones no caben en una línea, y una fila que no cabe no se
            // parte, se desborda.
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Un tema y no un documento: es el nivel que se crea primero.
                // Los documentos van dentro de un tema, y tienen su botón
                // allí -- crearlos aquí obligaba a decir después a cuál
                // pertenecen, que es el paso que se olvida.
                FilledButton.icon(
                  key: const Key('add-theme'),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Nuevo tema'),
                  onPressed: _addTheme,
                ),
                // Para lo que no es de ningún tema: la FAQ, la notación, el
                // calendario. Existe, así que tiene por dónde crearse.
                TextButton(
                  key: const Key('add-document'),
                  onPressed: () => _add(),
                  child: const Text('Documento suelto'),
                ),
                // El curso entero. Detrás y con otro relieve: es la
                // operación más larga que hay aquí --puede ser media hora-- y
                // no se pulsa por error al ir a crear algo. En el mismo
                // `Wrap` que los demás, porque `Spacer` no cabe en uno y una
                // fila que no cabe se desborda.
                GestureDetector(
                  onLongPressStart: _buildLanguages.length < 2
                      ? null
                      : (details) async {
                          final chosen = await askBuildLanguages(
                            context,
                            at: details.globalPosition,
                            options: _buildLanguages,
                            current: widget.session.language,
                          );
                          if (chosen != null) {
                            await _buildAll(languages: chosen);
                          }
                        },
                  child: OutlinedButton.icon(
                    key: const Key('build-year'),
                    icon: const Icon(Icons.play_circle_outline, size: 16),
                    label: Text(
                      _buildLanguages.length < 2
                          ? 'Compilar el curso'
                          : 'Compilar el curso en ${_currentLanguageName()}',
                    ),
                    onPressed: () => _buildAll(languages: _tapLanguages()),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// La barra de guardar, que solo aparece cuando hay algo que guardar.
/// Lo que va en una tarjeta: un tema, y sus documentos por repositorio.
///
/// Repartidos por repositorio y no en una lista porque el orden no es global.
/// Cada `year.yaml` guarda el suyo, así que arrastrar ordena entre los del
/// mismo fichero; lo que sí es común es el tema, que es de lo que trata esto.
class _CardGroup {
  _CardGroup({
    this.theme,
    required this.byRepo,
    Map<String, List<String>>? pending,
    // Copiado y no usado tal cual: los pendientes se van añadiendo mientras
    // se arman los grupos, y un mapa constante no se deja tocar.
  }) : pending = {...?pending};

  factory _CardGroup.from(ThemedDocuments group, List<String> repos) =>
      _CardGroup(
        theme: group.theme,
        byRepo: {
          for (final repo in repos)
            if (group.documents.any((d) => d.repo == repo))
              repo: [
                for (final document in group.documents)
                  if (document.repo == repo) document.id,
              ],
        },
      );

  /// Los recién creados, que están en un fichero y aún no en el índice.
  factory _CardGroup.pending(Map<String, List<String>> ids) =>
      _CardGroup(byRepo: const {}, pending: ids);

  /// Null es «los que no están en ningún tema declarado»: salen sin tarjeta,
  /// tal como salían antes de que los temas existieran.
  final CourseTheme? theme;

  /// Los ids de cada repositorio, en el orden de su fichero.
  final Map<String, List<String>> byRepo;

  final Map<String, List<String>> pending;

  bool get isLoose => theme == null;

  int get length =>
      byRepo.values.fold(0, (sum, ids) => sum + ids.length) +
      pending.values.fold(0, (sum, ids) => sum + ids.length);
}

/// Un tema, con sus documentos dentro.
///
/// Una tarjeta y no una cabecera porque lo que hay que ver de un vistazo es
/// **qué entra en el Tema 1**, y eso incluye material de varios repositorios:
/// la teoría de uno, la práctica de otro. Con una lista corrida eso no se ve,
/// y era la pregunta que la pantalla no contestaba.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    super.key,
    required this.group,
    required this.course,
    required this.year,
    required this.session,
    required this.collapsed,
    required this.canWrite,
    required this.drafts,
    required this.outputs,
    required this.onBuild,
    required this.onBuildDocument,
    required this.buildLanguages,
    this.onEditTitle,
    this.onEditDocumentTitle,
    required this.onOpenPdfs,
    required this.onToggle,
    required this.onReorder,
    required this.onRemove,
    required this.onAdd,
  });

  final _CardGroup group;
  final Course course;
  final String year;
  final Session session;
  final bool collapsed;
  final bool canWrite;

  /// Lo que el fichero sabe de los documentos que aún no están en el índice.
  final Map<String, DocumentDraft> drafts;

  /// Lo que hay compilado, por documento.
  final Map<String, List<ExistingOutput>> outputs;

  /// Compilar todas las versiones de todo lo que cuelga de este tema.
  final BuildRequest onBuild;

  /// Los idiomas entre los que elegir al mantener pulsado el botón.
  final List<LanguageOption> buildLanguages;

  /// Cambiar el título del tema. Null cuando no se puede escribir en el
  /// repositorio que lo declara.
  final VoidCallback? onEditTitle;

  /// Cambiar el título de un documento. Null cuando no se puede escribir.
  final void Function(Document document)? onEditDocumentTitle;

  /// Compilar todas las versiones de un documento.
  final void Function(String id, List<String> languages) onBuildDocument;

  /// Ver lo compilado de un documento, con una pestaña por versión.
  final void Function(String id, String title) onOpenPdfs;

  final VoidCallback onToggle;
  final void Function(String repo, List<String> ids, int from, int to)
  onReorder;
  final void Function(String id, String title) onRemove;

  /// Crear un documento **dentro de este tema**. Aquí y no en un botón de
  /// abajo: creado desde el tema ya sabe a cuál pertenece, y ese es el paso
  /// que se olvidaba.
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final byId = {
      for (final document in session.catalogue.documentsIn(course.id, year))
        document.id: document,
    };

    // Los sueltos no llevan tarjeta: son los de siempre, y enmarcarlos diría
    // que son un grupo, que es justo lo que no son.
    if (group.isLoose) {
      return Column(children: _tiles(byId));
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 2),
      decoration: BoxDecoration(
        color: didactaPanel,
        border: Border.all(color: didactaRule),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          if (!collapsed)
            Container(
              color: didactaCard,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._tiles(byId),
                  if (canWrite)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
                        child: TextButton.icon(
                          key: Key('add-document-${group.theme!.id}'),
                          icon: const Icon(Icons.add, size: 15),
                          label: const Text('Documento en este tema'),
                          onPressed: onAdd,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) => InkWell(
    key: Key('theme-header-${group.theme!.id}'),
    onTap: onToggle,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
      child: Row(
        children: [
          Icon(
            collapsed ? Icons.chevron_right : Icons.expand_more,
            size: 18,
            color: didactaMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              group.theme!.title(session.language),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Flexible y no fijo: en una ventana estrecha la cabecera lleva el
          // título, la cuenta y tres botones, y el que tiene que ceder es
          // esto. Con un `Text` a secas la fila se desborda quince píxeles.
          Flexible(
            child: Text(
              _count(),
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: const TextStyle(fontSize: 11.5, color: didactaMuted),
            ),
          ),
          // El título del tema en todos los idiomas. Solo en el repositorio
          // que lo declara: los demás únicamente lo nombran desde sus
          // documentos, y ahí no hay título que cambiar.
          if (onEditTitle != null)
            TitleButton(
              id: 'theme-${group.theme!.id}',
              what: 'este tema',
              onPressed: onEditTitle!,
            ),
          // Compilar el tema entero. En la cabecera y no dentro: es una
          // operación sobre el bloque, y desde aquí se ve sin desplegarlo.
          BuildButton(
            id: 'theme-${group.theme!.id}',
            what: 'todo el tema «${group.theme!.title(session.language)}»',
            options: buildLanguages,
            current: session.language,
            onBuild: onBuild,
          ),
        ],
      ),
    ),
  );

  /// Cuántos documentos se están viendo, y cuántos hay.
  ///
  /// El total sale del catálogo sin filtrar, así que apagar un repositorio no
  /// esconde en silencio la mitad de un tema: dice «3 de 7» y se ve que falta
  /// algo y dónde está.
  String _count() {
    final visible = group.length;
    final theme = group.theme;
    var total = visible;
    if (theme != null) {
      final full = session.fullYear(course.id, year);
      if (full != null) {
        total = full.documents
            .where((document) => document.themes.contains(theme.id))
            .length;
      }
    }
    if (total > visible) return '$visible de $total documentos';
    return visible == 1 ? '1 documento' : '$visible documentos';
  }

  /// Una sublista arrastrable por repositorio.
  ///
  /// Se ven seguidas, sin separador ni título: lo que se enseña es el tema
  /// entero, y de qué repositorio sale cada fila ya lo dice su color. Lo
  /// único que no cruza es el arrastre, porque el orden vive en cada fichero.
  List<Widget> _tiles(Map<String, Document> byId) => [
    for (final entry in group.byRepo.entries)
      ReorderableListView.builder(
        key: ValueKey('${group.theme?.id ?? 'loose'}-${entry.key}'),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: entry.value.length,
        onReorderItem: session.canWriteIn(entry.key)
            ? (from, to) => onReorder(entry.key, entry.value, from, to)
            : (_, _) {},
        itemBuilder: (context, index) {
          final id = entry.value[index];
          final document = byId[id];
          return _DocumentTile(
            key: ValueKey('document-${group.theme?.id ?? 'loose'}-$id'),
            index: index,
            course: course,
            year: year,
            id: id,
            document: document,
            session: session,
            canWrite: session.canWriteIn(entry.key),
            outputs: outputs[id] ?? const [],
            onBuild: (languages) => onBuildDocument(id, languages),
            buildLanguages: buildLanguages,
            onEditTitle:
                document != null &&
                    onEditDocumentTitle != null &&
                    session.canWriteIn(entry.key)
                ? () => onEditDocumentTitle!(document)
                : null,
            onOpenPdfs: () =>
                onOpenPdfs(id, document?.title(session.language) ?? id),
            onRemove: () =>
                onRemove(id, document?.title(session.language) ?? id),
          );
        },
      ),
    for (final entry in group.pending.entries)
      for (final id in entry.value)
        _DocumentTile(
          key: ValueKey('document-pending-$id'),
          index: -1,
          course: course,
          year: year,
          id: id,
          document: null,
          draft: drafts[id],
          session: session,
          canWrite: false,
          onRemove: () {},
        ),
  ];
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.added,
    required this.removed,
    required this.saving,
    required this.onDiscard,
    required this.onSave,
  });

  final int added;
  final int removed;
  final bool saving;
  final VoidCallback? onDiscard;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Color(0xFFF3F7F1),
      border: Border(bottom: BorderSide(color: didactaRule)),
    ),
    padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
    child: Row(
      children: [
        const Icon(Icons.edit_outlined, size: 15, color: didactaAccentDark),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Sin guardar · +$added −$removed en year.yaml',
            style: const TextStyle(fontSize: 12.5, color: didactaMuted),
          ),
        ),
        if (onDiscard != null)
          TextButton(onPressed: onDiscard, child: const Text('Descartar')),
        const SizedBox(width: 4),
        FilledButton.icon(
          key: const Key('documents-save'),
          icon: saving
              ? const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check, size: 16),
          label: Text(saving ? 'Guardando…' : 'Guardar'),
          onPressed: onSave,
        ),
      ],
    ),
  );
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({
    required this.error,
    required this.path,
    required this.onRetry,
  });

  final Object error;
  final String path;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No se pudo leer la composición',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            SelectableText(
              path,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: didactaMuted,
              ),
            ),
            const SizedBox(height: 10),
            SelectableText('$error', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reintentar'),
                onPressed: onRetry,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    super.key,
    required this.index,
    required this.course,
    required this.year,
    required this.id,
    required this.document,
    this.draft,
    required this.session,
    required this.canWrite,
    this.outputs = const [],
    this.onBuild,
    this.buildLanguages = const [],
    this.onEditTitle,
    this.onOpenPdfs,
    required this.onRemove,
  });

  final int index;
  final Course course;
  final String year;
  final String id;

  /// Null para un grupo que está en el fichero y todavía no en el catálogo:
  /// el índice se genera aparte, así que el recién creado se ve aquí antes
  /// de que `didacta index` lo recoja. Enseñarlo a medias es mejor que
  /// hacerlo desaparecer hasta el siguiente índice.
  final Document? document;

  /// Lo que el fichero sabe de él, para los segundos que van desde crearlo
  /// hasta que el índice lo recoge. Null cuando ya está en el catálogo.
  final DocumentDraft? draft;

  final Session session;
  final bool canWrite;

  /// Lo que hay compilado de este documento.
  final List<ExistingOutput> outputs;

  /// Compilar todas sus versiones. Null cuando no se puede compilar.
  final BuildRequest? onBuild;
  final List<LanguageOption> buildLanguages;

  /// Cambiar su título en todos los idiomas. Null en un documento que todavía
  /// no está en el índice: no hay entrada que reescribir hasta que se guarde.
  final VoidCallback? onEditTitle;

  /// Ver lo compilado, con una pestaña por versión.
  final VoidCallback? onOpenPdfs;

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final document = this.document;
    if (document == null) return _pending(context);

    final resolved = [
      for (final reference in document.unitRefs)
        (
          reference,
          session.catalogue.unitByReference(reference, repo: document.repo),
        ),
    ];
    final broken = resolved.where((pair) => pair.$2 == null).length;

    return Hoverable(
      onTap: () => context.go(Routes.document(course.id, year, document.id)),
      builder: (context, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        decoration: BoxDecoration(
          color: hovering ? didactaHover : Colors.transparent,
          border: const Border(bottom: BorderSide(color: didactaRule)),
        ),
        padding: const EdgeInsets.fromLTRB(6, 10, 12, 10),
        // Con `LayoutBuilder` porque la fila tiene un suelo: asa, barra del
        // tipo, título, idiomas, abrir el PDF, título, compilar, quitar y la
        // flecha. En una ventana de móvil eso no cabe, y lo que cede es el
        // resumen de idiomas, que informa pero no se pulsa. Sin esto la fila
        // se desborda quince píxeles, que es como se descubrió.
        child: LayoutBuilder(
          builder: (context, space) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (canWrite)
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: Icon(
                      Icons.drag_indicator,
                      size: 17,
                      color: didactaMuted,
                    ),
                  ),
                )
              else
                const SizedBox(width: 10),
              Container(
                width: 3,
                height: 34,
                margin: const EdgeInsets.only(top: 2, right: 10),
                decoration: BoxDecoration(
                  color: kindColour(document.kind),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            document.title(session.language),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        // De qué repositorio es este tema. Solo con varios
                        // abiertos: con uno, marcar no dice nada.
                        if (session.colourOf(document.repo) != null) ...[
                          const SizedBox(width: 8),
                          RepoChip(
                            colour: session.colourOf(document.repo)!,
                            label:
                                session.workspace.byId(document.repo)?.label ??
                                document.repo,
                            compact: true,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    // A Wrap, not a Row: four pieces of metadata after a
                    // document id do not fit on a phone, and a second line is
                    // better than a hidden one.
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          document.id,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                            color: didactaMuted,
                          ),
                        ),
                        Text(
                          kindName(document.kind),
                          style: TextStyle(
                            fontSize: 11,
                            color: kindColour(document.kind),
                          ),
                        ),
                        Text(
                          '${document.unitRefs.length} unidades',
                          style: const TextStyle(
                            fontSize: 11,
                            color: didactaMuted,
                          ),
                        ),
                        if (broken > 0)
                          Row(
                            children: [
                              const Icon(
                                Icons.link_off,
                                size: 12,
                                color: didactaTeacher,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '$broken',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: didactaTeacher,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Which languages this document's content is available in, taken
              // from the units it uses -- so a document can be seen to be
              // buildable in Valencian before opening it.
              if (space.maxWidth >= 520)
                _LanguageSummary(
                  units: [
                    for (final pair in resolved)
                      if (pair.$2 != null) pair.$2!,
                  ],
                  languages: session.catalogue.languages,
                ),
              // Ver lo compilado, si hay algo. Antes que compilar a propósito:
              // mirar cómo quedó es lo que más se hace, y compilar es lo que se
              // hace cuando lo de al lado dice que está viejo.
              _OpenButton(
                id: id,
                outputs: outputs,
                onPressed: onOpenPdfs ?? () {},
              ),
              if (onEditTitle != null)
                TitleButton(
                  id: 'document-$id',
                  what: 'este documento',
                  onPressed: onEditTitle!,
                ),
              if (onBuild != null)
                BuildButton(
                  id: 'document-$id',
                  what: '«${document.title(session.language)}»',
                  options: buildLanguages,
                  current: session.language,
                  onBuild: onBuild!,
                ),
              if (canWrite)
                IconButton(
                  key: Key('remove-document-$id'),
                  tooltip: 'Quitar este documento',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 15),
                  onPressed: onRemove,
                ),
              const Icon(Icons.chevron_right, size: 18, color: didactaMuted),
            ],
          ),
        ),
      ),
    );
  }

  /// Un grupo recién creado, todavía no indexado.
  /// Un documento que está en el fichero y todavía no en el índice.
  ///
  /// Con la misma forma que los demás --asa, barra del tipo, título-- y en
  /// gris. Antes era una línea con el identificador en monoespaciada, y un
  /// documento recién creado parecía un error en lugar de lo que era: el
  /// mismo documento, esperando a que se regenere el índice. Lo que cambia es
  /// el color y la nota de al lado, no la forma.
  Widget _pending(BuildContext context) {
    final title = draft?.title(session.language) ?? id;
    final kind = draft?.kind ?? 'theory';

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: didactaRule)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canWrite)
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Icon(
                  Icons.drag_indicator,
                  size: 17,
                  color: didactaMuted,
                ),
              ),
            )
          else
            const SizedBox(width: 10),
          Container(
            width: 3,
            height: 34,
            margin: const EdgeInsets.only(top: 2, right: 10),
            decoration: BoxDecoration(
              // Atenuada, como el resto de la fila: el tipo se ve, y se ve
              // que esto aún no está del todo.
              color: kindColour(kind).withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: didactaMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      kind,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: didactaMuted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'sin indexar todavía',
                      style: TextStyle(fontSize: 11.5, color: didactaEx),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (canWrite)
            IconButton(
              key: Key('remove-document-$id'),
              tooltip: 'Quitar este documento',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 15),
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}

class _LanguageSummary extends StatelessWidget {
  const _LanguageSummary({required this.units, required this.languages});

  final List<Unit> units;
  final List<String> languages;

  @override
  Widget build(BuildContext context) {
    if (units.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (final code in languages)
          Builder(
            builder: (context) {
              final present = units
                  .where((unit) => unit.statusIn(code).exists)
                  .length;
              final complete = present == units.length;
              final colour = present == 0
                  ? didactaMuted
                  : complete
                  ? didactaAccentDark
                  : didactaEx;
              return Tooltip(
                message: '$code: $present de ${units.length} unidades',
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: present == 0 ? null : colour.withValues(alpha: 0.10),
                    border: Border.all(
                      color: present == 0 ? didactaRule : colour,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    complete ? code : '$code $present/${units.length}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: present == 0 ? didactaMuted : colour,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _NotHere extends StatelessWidget {
  const _NotHere({required this.what, required this.hint});

  final String what;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PageHeader(
          title: 'No encontrado',
          breadcrumbs: [('Asignaturas', Routes.courses())],
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      what,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(hint, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () => context.go(Routes.courses()),
                      child: const Text('Ver las asignaturas'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// El botón de abrir lo compilado, cuando hay algo que abrir.
///
/// Solo aparece si el PDF existe: un atajo que lleva a un fichero que no está
/// es peor que no tener atajo. Cuando lo que hay se ha quedado viejo respecto
/// a la composición, se dice con el color -- se puede abrir igual, porque
/// mirar un PDF de ayer es una cosa razonable de querer hacer.
class _OpenButton extends StatelessWidget {
  const _OpenButton({
    required this.id,
    required this.outputs,
    required this.onPressed,
  });

  final String id;
  final List<ExistingOutput> outputs;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (outputs.isEmpty) return const SizedBox.shrink();
    final stale = outputs.every((output) => output.stale);
    return IconButton(
      key: Key('open-pdf-$id'),
      tooltip: stale
          ? 'Ver el PDF (de antes del último cambio)'
          : outputs.length == 1
          ? 'Ver el PDF'
          : 'Ver los ${outputs.length} PDF',
      visualDensity: VisualDensity.compact,
      icon: Icon(
        stale ? Icons.picture_as_pdf_outlined : Icons.picture_as_pdf,
        size: 17,
      ),
      color: stale ? didactaMuted : didactaThm,
      onPressed: onPressed,
    );
  }
}
