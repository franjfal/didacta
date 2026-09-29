/// La biblioteca: 2147 unidades, navegables.
///
/// Esta pantalla estaba mal, y merece la pena decir en qué. Enseñaba las 2147
/// unidades en una lista plana, con un panel de facetas al lado. La lista
/// funcionaba —virtualizada, ordenable, filtrable— y aun así era lo peor que
/// se podía hacer con estos datos, porque **tiraba a la basura la
/// organización que el autor ya había hecho**.
///
/// El material está en un árbol, y está en el árbol en el disco:
/// `content/analysis/normed/definition`. Dos áreas, 51 categorías, 444 temas,
/// mediana de 3 unidades por tema. Eso son tres clics hasta cualquier unidad.
/// La lista plana llegaba a la misma unidad pasando por delante de otras dos
/// mil.
///
/// Así que hay dos vistas, y cada una responde a una pregunta distinta:
///
/// **Explorar** (al entrar) — el árbol, en columnas. «¿Qué hay de análisis?»
/// se responde mirando, no buscando. Cada nivel dice cuánto contiene y cuánto
/// está traducido al idioma que se está mirando.
///
/// **Buscar** (al escribir) — la lista plana, que para una búsqueda es la
/// forma correcta: «hilbert» no es un sitio del árbol, es todo lo que
/// coincide. Vive en `library_search.dart`.
///
/// Y menús de verdad, porque «Árbol», «Traducción», «Tipo» y «Orden» son
/// menús y no cuatro controles sueltos peleándose por el ancho de la cabecera
/// —que es exactamente lo que hacían, hasta comerse unos a otros por debajo
/// de 1000 px.
library;

import 'command_palette.dart';
import 'shortcuts.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/browser.dart';
import '../model/catalogue.dart';
import '../model/fuzzy.dart';
import '../model/library_filter.dart';
import '../model/library_place.dart';
import '../model/library_tree.dart';
import '../model/saved_search.dart';
import '../model/text_search.dart';
import '../router.dart';
import '../state/session.dart';
import 'add_repository.dart';
import 'library_search.dart';
import 'new_unit.dart';
import 'problem.dart';
import 'quick_look.dart';
import 'review_panel.dart';
import 'shell.dart';
import 'theme.dart';
import 'tour.dart';
import 'working.dart';
import '../l10n/tr.dart';

/// El nombre de un bloque, de los que el catálogo ofrece.
///
/// Con caída a [blockLabel] por si llega un id que ya no está en la lista:
/// vale más enseñar «practicas» que dejar el hueco donde alguien espera leer
/// qué está filtrando.
String _blockName(List<CourseBlock> blocks, String id, String language) {
  for (final block in blocks) {
    if (block.id == id) return block.title(language);
  }
  return blockLabel(id, language);
}

/// Dónde está puesto el navegador. Un valor, no dos campos sueltos, para que
/// no se pueda estar en un tema de una categoría que no está abierta.
///
/// Sin área: el área es un filtro sobre las unidades con las que se construye
/// el árbol, no un nivel. Ponerla de nivel partía `analysis` en dos
/// categorías con el mismo nombre, y separaba la teoría de sus ejercicios,
/// que es justo lo que nadie quiere al preguntar «¿qué tengo de esto?».
class BrowsePath {
  const BrowsePath({this.category, this.topic, this.tag});

  final String? category;
  final String? topic;

  /// La etiqueta elegida dentro del tema.
  ///
  /// Es un nivel más de navegación --categoría, tema, etiqueta-- pero no un
  /// nivel más del árbol: se pinta como una fila de filtros encima de la
  /// lista. Una unidad puede llevar varias etiquetas, así que un árbol la
  /// pondría en varias ramas a la vez, y entonces contar deja de significar
  /// nada.
  final String? tag;

  bool get isRoot => category == null;

  /// Entrar en un tema empieza sin etiqueta: las de un tema no son las del
  /// anterior.
  BrowsePath toTopic(String topic) =>
      BrowsePath(category: category, topic: topic);

  BrowsePath withTag(String? tag) =>
      BrowsePath(category: category, topic: topic, tag: tag);

  /// Un nivel hacia arriba.
  BrowsePath up() {
    if (tag != null) return BrowsePath(category: category, topic: topic);
    if (topic != null) return BrowsePath(category: category);
    return const BrowsePath();
  }
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, this.place = const LibraryPlace()});

  /// Dónde se abre: lo que dice la dirección.
  final LibraryPlace place;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  BrowsePath _path = const BrowsePath();
  LibraryFilter? _filter;

  /// Si lo buscado se busca también en el texto de las lecciones, y lo que
  /// se ha encontrado ahí: null mientras se busca.
  bool _inText = false;
  List<TextHit>? _hits;
  String _hitsFor = '';
  Timer? _textTimer;
  Timer? _queryTimer;

  /// La búsqueda en curso: una respuesta que llega tarde, de una búsqueda
  /// anterior, no pisa la de ahora.
  int _textSearch = 0;

  /// El árbol se construye una vez por catálogo, no por frame: recorrer 2147
  /// unidades para contar una insignia es justo lo que hace que un scroll dé
  /// tirones sin que nadie sepa por qué.
  LibraryTree? _tree;
  Catalogue? _treeFor;
  String? _treeKey;

  @override
  void initState() {
    super.initState();
    _adopt(widget.place);
    // Qué hay compilado, una vez. Es lo que decide qué lecciones se pueden
    // ojear, y se pregunta aquí y no en cada tarjeta porque la respuesta es
    // una sola para las dos mil.
    scheduleMicrotask(() {
      final session = context.read<Session>();
      if (!session.builtKnown) unawaited(session.refreshBuilt());
    });
  }

  @override
  void didUpdateWidget(LibraryPage old) {
    super.didUpdateWidget(old);
    // Cuando la dirección cambia por fuera --atrás, adelante, un enlace--,
    // manda ella. Cuando la cambia esta pantalla, ya coincide y no se toca:
    // reescribir el buscador a mitad de palabra movería el cursor.
    if (widget.place != _place) {
      setState(() => _adopt(widget.place));
    }
  }

  @override
  void dispose() {
    _textTimer?.cancel();
    _queryTimer?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Busca en el texto lo que hay en el buscador, con un respiro: a cada
  /// letra sería lanzar git veinte veces para una palabra.
  void _searchText() {
    _textTimer?.cancel();
    final query = _search.text.trim();
    if (!_inText || query.length < 3) {
      _hits = null;
      _hitsFor = '';
      return;
    }
    if (query == _hitsFor && _hits != null) return;
    _hits = null;
    _hitsFor = query;
    final ticket = ++_textSearch;
    _textTimer = Timer(const Duration(milliseconds: 300), () async {
      final found = await context.read<Session>().searchText(query);
      if (!mounted || ticket != _textSearch) return;
      setState(() => _hits = found);
    });
  }

  /// Pone la pantalla en [place].
  void _adopt(LibraryPlace place) {
    final browse = place.browse;
    _path = BrowsePath(
      category: browse.isNotEmpty ? browse[0] : null,
      topic: browse.length > 1 ? browse[1] : null,
      tag: browse.length > 2 ? browse[2] : null,
    );
    _filter = place.filterIn(_filter?.language ?? 'es');
    if (_search.text != place.query) _search.text = place.query;
    _inText = place.inText;
    _searchText();
  }

  /// Dónde está la pantalla ahora, para escribirlo en la dirección.
  LibraryPlace get _place => LibraryPlace.of(
    (_filter ?? const LibraryFilter()).copyWith(query: _search.text.trim()),
    [?_path.category, ?_path.topic, ?_path.tag],
    inText: _inText,
  );

  /// Lleva a la dirección lo que se acaba de cambiar.
  ///
  /// Con `go` y no con `replace`: la pantalla es la misma, y `go` la
  /// conserva --con el cursor en el buscador-- mientras que `replace` la
  /// crearía de nuevo. El historial no se llena por eso: una dirección que
  /// solo cambia en la consulta es el mismo sitio (ver [NavigationHistory]).
  void _publish() {
    final place = _place;
    if (place == widget.place) return;
    GoRouter.maybeOf(context)?.go(Routes.library(place));
  }

  /// Guarda lo que se está mirando con un nombre, para volver a ello desde
  /// la raíz de la biblioteca.
  Future<void> _saveSearch(Session session) async {
    final url = Routes.library(_place);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NameSearch(suggested: _search.text.trim()),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    await session.saveSearch(name.trim(), url);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('Guardada: «{0}».', [name.trim()]))),
    );
  }

  void _change(VoidCallback change) {
    setState(() {
      change();
      _searchText();
    });
    _publish();
  }

  /// El árbol, sobre las unidades que dejan pasar los filtros.
  ///
  /// **Todos** los filtros menos el texto, que es el que cambia de vista. Antes
  /// solo contaba el bloque: Traducción, Tipo y «sin usar» se ponían en verde
  /// y el árbol seguía enseñándolo todo, así que el filtro solo hacía algo
  /// escribiendo en el buscador.
  ///
  /// Se reconstruye al cambiar de catálogo o de filtro, no por frame: es una
  /// pasada sobre 2147 unidades y ocurre cuando alguien pulsa un filtro.
  LibraryTree _treeOf(Catalogue catalogue, LibraryFilter browse) {
    final key = [
      browse.block,
      browse.category,
      browse.kind,
      browse.tag,
      browse.status,
      browse.unusedOnly,
      browse.language,
    ].join('|');
    if (_treeFor != catalogue || _treeKey != key) {
      _tree = LibraryTree.of(
        catalogue.units.where(browse.matches),
        titleOf: (key) => catalogue.taxonomyTitle(key, browse.language),
      );
      _treeFor = catalogue;
      _treeKey = key;
    }
    return _tree!;
  }

  bool get _searching => _search.text.trim().isNotEmpty;

  // Lo compilado, las recientes y la versión que se ojea avisan por su
  // cuenta, no por la sesión.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      sessionOf(context).settings,
      sessionOf(context).builds,
      sessionOf(context).libraryPrefs,
    ]),
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) =>
      PaletteCommands(commands: _paletteCommands, child: _library(context));

  /// Lo que ofrece la paleta de órdenes en la biblioteca.
  List<PaletteCommand> _paletteCommands(BuildContext context) {
    final session = sessionOf(context);
    return [
      PaletteCommand(
        title: tr('Buscar en la biblioteca'),
        keywords: tr('filtrar lecciones'),
        icon: Icons.search,
        shortcut: AppShortcut.search,
        run: _searchFocus.requestFocus,
      ),
      if (session.canSearchText)
        PaletteCommand(
          title: _inText
              ? tr('Buscar solo en títulos y etiquetas')
              : tr('Buscar también dentro de las lecciones'),
          keywords: tr('texto contenido grep'),
          icon: Icons.manage_search,
          run: () => _change(() => _inText = !_inText),
        ),
    ];
  }

  Widget _library(BuildContext context) {
    final session = watchSession(context);
    final catalogue = session.catalogue;

    // El idioma vive en la sesión para que el recuento del carril y esta
    // pantalla no puedan discrepar sobre a qué idioma se refieren.
    _filter ??= LibraryFilter(language: session.language);
    if (_filter!.language != session.language) {
      _filter = _filter!.copyWith(language: session.language);
    }
    final filter = _filter!.copyWith(query: _search.text.trim());
    // Los mismos filtros gobiernan el árbol y la búsqueda, para que las dos
    // vistas no puedan estar mirando material distinto.
    final browse = filter.copyWith(query: '');
    final tree = _treeOf(catalogue, browse);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_searching) {
            _change(_search.clear);
          } else if (!_path.isRoot) {
            _change(() => _path = _path.up());
          }
        },
      },
      child: Column(
        children: [
          _Header(
            tree: tree,
            session: session,
            filter: filter,
            blocks: catalogue.blocksInUse,
            search: _search,
            searchFocus: _searchFocus,
            searching: _searching,
            path: _path,
            inText: _inText,
            onInText: session.canSearchText
                ? (on) => _change(() => _inText = on)
                : null,
            onFilter: (next) => _change(() => _filter = next),
            // Con un respiro de 120 ms: el campo enseña cada letra por su
            // cuenta, y lo que espera es rehacer la lista, que con dos mil
            // unidades a cada letra se notaba.
            onSearchChanged: () {
              _queryTimer?.cancel();
              _queryTimer = Timer(const Duration(milliseconds: 120), () {
                if (mounted) _change(() {});
              });
            },
            onPath: (next) => _change(() => _path = next),
          ),
          // Lo abierto hace poco y las búsquedas guardadas, en la raíz: es
          // de donde se sale a buscar, y lo que se buscó ayer es lo más
          // probable que se busque hoy.
          if (!_searching && _path.isRoot && catalogue.units.isNotEmpty)
            _Shortcuts(
              session: session,
              onSearch: (url) => GoRouter.maybeOf(context)?.go(url),
            ),
          Expanded(
            child: catalogue.units.isEmpty
                ? _EmptyLibrary(session: session)
                : _searching
                ? _SearchResults(
                    filter: filter,
                    units: catalogue.units,
                    inText: _inText && session.canSearchText,
                    hits: _hits,
                    onSave: session.completeInterface
                        ? () => _saveSearch(session)
                        : null,
                    blocks: catalogue.blocksInUse,
                    onFilter: (next) => _change(() => _filter = next),
                  )
                : TourTarget(
                    id: 'library-browser',
                    child: _Browser(
                      tree: tree,
                      path: _path,
                      language: session.language,
                      filter: filter,
                      blocks: catalogue.blocksInUse,
                      onPath: (next) => _change(() => _path = next),
                      onFilter: (next) => _change(() {
                        _filter = next;
                        // Cambiar de área cambia qué categorías hay, así que
                        // una selección anterior puede haber desaparecido.
                        _path = const BrowsePath();
                      }),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// El nombre de una búsqueda que se guarda.
class _NameSearch extends StatefulWidget {
  const _NameSearch({required this.suggested});

  final String suggested;

  @override
  State<_NameSearch> createState() => _NameSearchState();
}

class _NameSearchState extends State<_NameSearch> {
  late final TextEditingController _name =
      TextEditingController(text: widget.suggested)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.suggested.length,
        );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Guardar esta búsqueda')),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'Con lo buscado, los filtros y lo abierto. Sale en la raíz de la '
              'biblioteca, para volver a ella de un clic.',
            ),
            style: TextStyle(fontSize: 12.5, color: context.palette.muted),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('save-search-name'),
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: tr('Nombre')),
            onSubmitted: (value) => Navigator.of(context).pop(value),
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
        key: const Key('save-search-confirm'),
        onPressed: () => Navigator.of(context).pop(_name.text),
        child: Text(tr('Guardar')),
      ),
    ],
  );
}

/// «Abiertas hace poco» y, en la interfaz completa, las búsquedas guardadas.
///
/// Sin nada que enseñar no ocupa sitio: una fila vacía que dice «todavía no
/// has abierto nada» es una fila que se aprende a no mirar.
class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.session, required this.onSearch});

  final Session session;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([session.libraryPrefs, session.settings]),
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
    final recent = session.recentUnits;
    final saved = session.completeInterface
        ? session.savedSearches
        : const <SavedSearch>[];
    if (recent.isEmpty && saved.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('library-shortcuts'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.palette.panel,
        border: Border(bottom: BorderSide(color: context.palette.rule)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recent.isNotEmpty)
            _ShortcutRow(
              label: tr('Abiertas hace poco'),
              children: [
                for (final unit in recent)
                  ActionChip(
                    key: Key('recent-${unit.path}'),
                    avatar: Icon(
                      Icons.history,
                      size: 14,
                      color: context.palette.muted,
                    ),
                    label: Text(unit.title(session.language)),
                    tooltip: unit.path,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => goTo(context, Routes.unit(unit.path)),
                  ),
              ],
            ),
          if (recent.isNotEmpty && saved.isNotEmpty) const SizedBox(height: 6),
          if (saved.isNotEmpty)
            _ShortcutRow(
              label: tr('Búsquedas guardadas'),
              children: [
                for (final search in saved)
                  InputChip(
                    key: Key('saved-search-${search.name}'),
                    avatar: Icon(
                      Icons.bookmark_outline,
                      size: 14,
                      color: context.palette.muted,
                    ),
                    label: Text(search.name),
                    tooltip: search.url,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onSearch(search.url),
                    deleteButtonTooltipMessage: tr('Olvidar esta búsqueda'),
                    onDeleted: () => session.forgetSearch(search.url),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      SizedBox(
        width: 150,
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: context.palette.muted,
          ),
        ),
      ),
      // En una línea que se desplaza: ocho títulos largos en dos líneas
      // empujarían el árbol hacia abajo cada vez que se abre algo.
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final child in children) ...[
                child,
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
      ),
    ],
  );
}

/// La biblioteca sin ninguna lección: por qué, y qué hacer.
///
/// Era un árbol vacío con «0 unidades» encima. Hay dos motivos y cada uno
/// tiene su salida: no hay ningún repositorio abierto, o el que hay no tiene
/// lecciones todavía.
class _EmptyLibrary extends StatefulWidget {
  const _EmptyLibrary({required this.session});

  final Session session;

  @override
  State<_EmptyLibrary> createState() => _EmptyLibraryState();
}

class _EmptyLibraryState extends State<_EmptyLibrary> {
  bool _working = false;
  String _doing = '';

  late final RepositoryAdder _adder = RepositoryAdder(
    session: widget.session,
    onBusy: (working) {
      if (mounted) setState(() => _working = working);
    },
    onStep: (what) {
      if (mounted) setState(() => _doing = what);
    },
    onProgress: (_) {},
    onProblem: (problem) {
      if (mounted && problem != null) showProblem(context, problem);
    },
  );

  @override
  Widget build(BuildContext context) {
    final noRepository = widget.session.workspace.isEmpty;
    // Desplazable: en un móvil, con un aviso encima, no cabe entero.
    return Center(
      key: const Key('empty-library'),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.library_books_outlined,
                  size: 40,
                  color: context.palette.faint,
                ),
                const SizedBox(height: 12),
                Text(
                  noRepository
                      ? tr('La biblioteca está vacía')
                      : tr('Todavía no hay ninguna lección'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  noRepository
                      ? tr(
                          'No hay ningún repositorio abierto. Añade el tuyo, o '
                          'prueba Didacta con un ejemplo en tu cuenta de '
                          'GitHub.',
                        )
                      : tr(
                          'Una lección es una carpeta dentro de content/ o '
                          'problems/ del repositorio, con un .tex por idioma. '
                          'La guía cuenta cómo es una.',
                        ),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: context.palette.muted),
                ),
                const SizedBox(height: 16),
                if (_working)
                  Working(step: _doing)
                else
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (noRepository) ...[
                        FilledButton.icon(
                          key: const Key('empty-library-add'),
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(tr('Añadir un repositorio')),
                          onPressed: () => goTo(
                            context,
                            Routes.settings(section: 'repositorios'),
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const Key('empty-library-example'),
                          icon: const Icon(
                            Icons.auto_stories_outlined,
                            size: 16,
                          ),
                          label: Text(tr('Probar con un ejemplo')),
                          onPressed: widget.session.signedIn
                              ? () => _adder.example(context)
                              : null,
                        ),
                      ] else
                        OutlinedButton.icon(
                          key: const Key('empty-library-guide'),
                          icon: const Icon(Icons.menu_book_outlined, size: 16),
                          label: Text(tr('Cómo se escribe una lección')),
                          onPressed: () => openLink('${didactaDocs}escribir/'),
                        ),
                    ],
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
// La cabecera y los menús
// ---------------------------------------------------------------------------

/// Si hay algún filtro de los menús puesto: todo menos el texto y el bloque.
bool _narrowing(LibraryFilter filter) =>
    filter.copyWith(query: '', clearBlock: true).hasFacets;

/// Cuántas unidades hay en el bloque que se mira, sin más filtros.
int _inBlock(Session session, LibraryFilter filter) => filter.block == null
    ? session.catalogue.units.length
    : session.catalogue.units
          .where((unit) => unit.block == filter.block)
          .length;

class _Header extends StatelessWidget {
  const _Header({
    required this.tree,
    required this.session,
    required this.filter,
    required this.blocks,
    required this.search,
    required this.searchFocus,
    required this.searching,
    required this.path,
    required this.onFilter,
    required this.onSearchChanged,
    required this.onPath,
    this.inText = false,
    this.onInText,
  });

  /// El interruptor «En el texto». Sin [onInText] no sale: sin copia local
  /// no hay dónde buscar.
  final bool inText;
  final ValueChanged<bool>? onInText;

  final LibraryTree tree;
  final Session session;
  final LibraryFilter filter;
  final List<CourseBlock> blocks;
  final TextEditingController search;
  final FocusNode searchFocus;
  final bool searching;
  final BrowsePath path;
  final ValueChanged<LibraryFilter> onFilter;
  final VoidCallback onSearchChanged;
  final ValueChanged<BrowsePath> onPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(bottom: BorderSide(color: context.palette.rule)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 700;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // La biblioteca tiene su propia cabecera --con el buscador
                  // y los idiomas-- pero el botón de volver tiene que estar
                  // en todas: si falta en una pantalla, deja de ser una forma
                  // de moverse y pasa a ser una que a veces está. Delante del
                  // título, como en las demás, y no en una fila para él solo.
                  const BackForward(),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Text(
                            tr('Biblioteca'),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            searching
                                ? tr('Buscando «{0}»', [filter.query])
                                : _narrowing(filter)
                                // Con filtros, cuántas quedan y cuáles: un
                                // árbol recortado que no lo dice parece la
                                // biblioteca entera con material de menos. El
                                // bloque no cuenta: es el área que se mira, y
                                // se ve arriba de la primera columna.
                                ? tr(
                                    '{0} de {1} '
                                    'unidades · '
                                    '{2}',
                                    [
                                      tree.unitCount,
                                      _inBlock(session, filter),
                                      filter
                                          .copyWith(clearBlock: true)
                                          .describe(),
                                    ],
                                  )
                                : tr(
                                    '{0} unidades · '
                                    '{1} categorías · '
                                    '{2} temas',
                                    [
                                      tree.unitCount,
                                      tree.categoryCount,
                                      tree.topicCount,
                                    ],
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: context.palette.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // En una pantalla ancha. En un móvil, el título, el
                  // idioma y esto no caben en la misma línea, y de las tres
                  // la que se puede dejar para el escritorio es esta:
                  // ojear un PDF de diapositivas en 390 px no es ojear.
                  if (!narrow && session.canCompile) ...[
                    // Todo lo abierto: una orden del castellano en el
                    // valenciano, una figura que falta, un «??».
                    TextButton.icon(
                      key: const Key('library-review'),
                      icon: const Icon(Icons.fact_check_outlined, size: 16),
                      label: Text(tr('Revisar')),
                      onPressed: () => showReview(
                        context,
                        session,
                        repos: session.snippetRepos.isEmpty
                            ? const [null]
                            : session.snippetRepos,
                        title: session.snippetRepos.length > 1
                            ? tr('los repositorios')
                            : tr('el repositorio'),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _PreviewPicker(session: session),
                    const SizedBox(width: 8),
                  ],
                  _LanguagePicker(session: session),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // Los filtros llevan la misma marca del tour en los dos
                  // sitios: nunca están los dos a la vez.
                  if (!narrow) ...[
                    TourTarget(
                      id: 'library-filters',
                      child: _LibraryMenus(
                        filter: filter,
                        onFilter: onFilter,
                        blocks: blocks,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: TourTarget(
                      id: 'library-search',
                      child: _SearchField(
                        controller: search,
                        focus: searchFocus,
                        inText: inText,
                        onChanged: onSearchChanged,
                      ),
                    ),
                  ),
                  if (onInText != null) ...[
                    const SizedBox(width: 6),
                    // Aquí, al lado de lo que se escribe, y no en Ajustes: es
                    // una pregunta de esta búsqueda, no una preferencia.
                    FilterChip(
                      key: const Key('search-in-text'),
                      label: Text(tr('En el texto')),
                      tooltip: tr(
                        'Buscar también dentro de las lecciones, no solo '
                        'en su título, su ruta y sus etiquetas',
                      ),
                      selected: inText,
                      onSelected: onInText,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                  if (narrow) ...[
                    const SizedBox(width: 4),
                    TourTarget(
                      id: 'library-filters',
                      child: _LibraryMenus(
                        filter: filter,
                        onFilter: onFilter,
                        blocks: blocks,
                        compact: true,
                      ),
                    ),
                  ],
                ],
              ),
              if (!searching && !path.isRoot) ...[
                const SizedBox(height: 10),
                _Breadcrumbs(tree: tree, path: path, onPath: onPath),
              ],
              if (filter.hasFacets) ...[
                const SizedBox(height: 9),
                _ActiveFilters(
                  filter: filter,
                  onFilter: onFilter,
                  blocks: blocks,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// «Árbol», «Traducción», «Tipo» y «Orden», como menús.
class _LibraryMenus extends StatelessWidget {
  const _LibraryMenus({
    required this.filter,
    required this.onFilter,
    required this.blocks,
    this.compact = false,
  });

  final LibraryFilter filter;
  final ValueChanged<LibraryFilter> onFilter;

  /// Los bloques que hay, declarados o nombrados. Ver [Catalogue.blocksInUse].
  final List<CourseBlock> blocks;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return MenuAnchor(
        builder: (context, controller, child) => IconButton(
          tooltip: tr('Ver y filtrar'),
          icon: Badge(
            isLabelVisible: filter.isNarrowed,
            child: const Icon(Icons.tune, size: 20),
          ),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
        menuChildren: [
          // Con uno solo no hay nada que elegir: un filtro cuyo único valor
          // es «todo» ocupa sitio y no contesta ninguna pregunta.
          if (blocks.length > 1) ...[
            ..._blockItems(context),
            const Divider(height: 1),
          ],
          ..._statusItems(context),
          const Divider(height: 1),
          ..._kindItems(context),
          const Divider(height: 1),
          ..._sortItems(context),
          const Divider(height: 1),
          ..._extraItems(context),
        ],
      );
    }

    return MenuBar(
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(0),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      children: [
        // Sin «Árbol»: el filtro de área está siempre a la vista, arriba de
        // la primera columna. Un menú que repite un control visible solo
        // añade un sitio donde mirar. En estrecho sí va en el menú, porque
        // ahí la columna desaparece al bajar de nivel.
        SubmenuButton(
          style: _pill(
            context,
            filter.status != StatusFilter.any || filter.unusedOnly,
          ),
          leadingIcon: const Icon(Icons.translate, size: 16),
          trailingIcon: const Icon(Icons.expand_more, size: 16),
          menuChildren: [
            ..._statusItems(context),
            const Divider(height: 1),
            ..._extraItems(context),
          ],
          child: Text(tr('Traducción'), style: _pillText),
        ),
        const SizedBox(width: 6),
        SubmenuButton(
          style: _pill(context, filter.kind != null),
          leadingIcon: const Icon(Icons.category_outlined, size: 16),
          trailingIcon: const Icon(Icons.expand_more, size: 16),
          menuChildren: _kindItems(context),
          child: Text(tr('Tipo'), style: _pillText),
        ),
        const SizedBox(width: 6),
        SubmenuButton(
          style: _pill(context, filter.sort != LibrarySort.path),
          leadingIcon: const Icon(Icons.sort, size: 16),
          trailingIcon: const Icon(Icons.expand_more, size: 16),
          menuChildren: _sortItems(context),
          child: Text(tr('Orden'), style: _pillText),
        ),
      ],
    );
  }

  /// Sin familia a propósito: se mezcla con la del botón. Un `textStyle`
  /// en el estilo del botón la sustituiría entera.
  static const TextStyle _pillText = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  /// Un filtro como un botón con borde, en verde si está puesto.
  ///
  /// Eran tres palabras sueltas en negrita, y no se veía ni que eran menús
  /// ni cuál estaba filtrando: la única forma de saber por qué la biblioteca
  /// enseñaba doce unidades era abrirlos uno a uno.
  static ButtonStyle _pill(BuildContext context, bool active) => ButtonStyle(
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
    minimumSize: const WidgetStatePropertyAll(Size(0, 38)),
    backgroundColor: WidgetStatePropertyAll(
      active ? context.palette.selected : context.palette.card,
    ),
    foregroundColor: WidgetStatePropertyAll(
      active ? context.palette.accentDark : context.palette.ink,
    ),
    iconColor: WidgetStatePropertyAll(
      active ? context.palette.accentDark : context.palette.muted,
    ),
    side: WidgetStatePropertyAll(
      BorderSide(
        color: active ? context.palette.accentDark : context.palette.rule,
      ),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.control),
      ),
    ),
  );

  List<Widget> _blockItems(BuildContext context) => [
    _check(
      context,
      tr('Todo'),
      filter.block == null,
      () => onFilter(filter.copyWith(clearBlock: true)),
    ),
    for (final block in blocks)
      _check(
        context,
        block.title(filter.language),
        filter.block == block.id,
        () => onFilter(filter.copyWith(block: block.id)),
      ),
  ];

  List<Widget> _statusItems(BuildContext context) => [
    for (final (status, label) in [
      (StatusFilter.any, tr('Cualquier estado')),
      (StatusFilter.present, tr('Existe en este idioma')),
      (StatusFilter.missing, tr('Falta en este idioma')),
      (StatusFilter.needsWork, tr('Por revisar o desactualizada')),
    ])
      _check(
        context,
        label,
        filter.status == status,
        () => onFilter(filter.copyWith(status: status)),
      ),
  ];

  List<Widget> _kindItems(BuildContext context) => [
    _check(
      context,
      tr('Cualquier tipo'),
      filter.kind == null,
      () => onFilter(filter.copyWith(clearKind: true)),
    ),
    const Divider(height: 1),
    for (final kind in const [
      'theory',
      'problem',
      'handout',
      'practical',
      'seminar',
      'example',
      'activity',
      'experiment',
      'history',
    ])
      MenuItemButton(
        leadingIcon: Dot(colour: context.palette.kind(kind)),
        trailingIcon: filter.kind == kind
            ? const Icon(Icons.check, size: 15)
            : null,
        onPressed: () => onFilter(
          filter.kind == kind
              ? filter.copyWith(clearKind: true)
              : filter.copyWith(kind: kind),
        ),
        child: Text(kindName(kind)),
      ),
  ];

  List<Widget> _sortItems(BuildContext context) => [
    for (final (sort, label) in [
      (LibrarySort.path, tr('Por ruta')),
      (LibrarySort.title, tr('Por título')),
      (LibrarySort.usage, tr('Más usadas primero')),
      (LibrarySort.needsWork, tr('Por traducir primero')),
    ])
      _check(
        context,
        label,
        filter.sort == sort,
        () => onFilter(filter.copyWith(sort: sort)),
      ),
  ];

  List<Widget> _extraItems(BuildContext context) => [
    _check(
      context,
      tr('Solo las que no usa ninguna asignatura'),
      filter.unusedOnly,
      () => onFilter(filter.copyWith(unusedOnly: !filter.unusedOnly)),
    ),
    if (filter.isNarrowed)
      MenuItemButton(
        leadingIcon: const Icon(Icons.filter_alt_off_outlined, size: 15),
        onPressed: () => onFilter(
          LibraryFilter(language: filter.language, sort: filter.sort),
        ),
        child: Text(tr('Quitar los filtros')),
      ),
  ];

  Widget _check(
    BuildContext context,
    String label,
    bool on,
    VoidCallback onPressed,
  ) => MenuItemButton(
    leadingIcon: Icon(
      on ? Icons.check : null,
      size: 15,
      color: context.palette.accentDark,
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}

/// Un cuadrado de color: el tipo de una unidad, del mismo color que en el PDF.
class Dot extends StatelessWidget {
  const Dot({super.key, required this.colour, this.size = 9});

  final Color colour;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    margin: const EdgeInsets.only(left: 3),
    decoration: BoxDecoration(
      color: colour,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focus,
    required this.onChanged,
    this.inText = false,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onChanged;
  final bool inText;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(7),
      borderSide: BorderSide(color: context.palette.rule),
    );
    return TextField(
      controller: controller,
      focusNode: focus,
      style: const TextStyle(fontSize: 13.5),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: context.palette.card,
        hintText: inText
            ? tr('Buscar también dentro de las lecciones…')
            : tr('Buscar por título, ruta o etiqueta…'),
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 16),
                tooltip: tr('Limpiar'),
                onPressed: () {
                  controller.clear();
                  onChanged();
                },
              ),
        border: border,
        enabledBorder: border,
      ),
      onChanged: (_) => onChanged(),
    );
  }
}

/// Qué versión se abre al ojear una lección.
///
/// Arriba y una sola para toda la biblioteca: quien prepara una clase está
/// mirando diapositivas toda la tarde, y elegirlo en cada tarjeta sería el
/// mismo clic dos mil veces.
class _PreviewPicker extends StatelessWidget {
  const _PreviewPicker({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session.settings,
    builder: (context, _) => _listenedBuild(context),
  );

  Widget _listenedBuild(BuildContext context) {
    // Las que tienen sentido para ojear una lección: lo que se proyecta y lo
    // que se lee. Un examen o una hoja de problemas del profesor no son
    // versiones de una lección suelta.
    final profiles = [
      for (final profile in session.catalogue.profiles)
        if (const {
          'slides',
          'notes',
          'handout',
          'problems',
        }.contains(profile.family))
          profile,
    ];
    if (profiles.isEmpty) return const SizedBox.shrink();

    return MenuAnchor(
      key: const Key('preview-picker'),
      builder: (context, controller, child) => Tooltip(
        message: tr('Qué versión se abre al ojear una lección'),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.visibility_outlined, size: 15),
          label: Text(
            profiles
                    .where((p) => p.id == session.previewProfile)
                    .map((p) => p.name)
                    .firstOrNull ??
                session.previewProfile,
          ),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
      menuChildren: [
        for (final profile in profiles)
          MenuItemButton(
            key: Key('preview-${profile.id}'),
            leadingIcon: Icon(
              profile.id == session.previewProfile
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 15,
              color: profile.id == session.previewProfile
                  ? context.palette.accentDark
                  : context.palette.muted,
            ),
            onPressed: () => session.setPreviewProfile(profile.id),
            child: Text(profile.name),
          ),
      ],
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    // Los mismos que ofrece la barra de arriba, y por la misma razón: dos
    // sitios donde se elige el idioma del contenido tienen que ofrecer lo
    // mismo, o el que se elige depende de por dónde se pasó.
    final languages = [
      for (final option in session.languageChoices) option.code,
    ];
    if (languages.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.palette.rule),
        borderRadius: BorderRadius.circular(7),
        color: context.palette.card,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final code in languages)
            _LanguageTab(
              code: code,
              selected: code == session.language,
              first: code == languages.first,
              last: code == languages.last,
              onTap: () => sessionOf(context).language = code,
            ),
        ],
      ),
    );
  }
}

class _LanguageTab extends StatelessWidget {
  const _LanguageTab({
    required this.code,
    required this.selected,
    required this.first,
    required this.last,
    required this.onTap,
  });

  final String code;
  final bool selected;
  final bool first;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.horizontal(
      left: Radius.circular(first ? 6 : 0),
      right: Radius.circular(last ? 6 : 0),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? context.palette.accentDark : Colors.transparent,
          borderRadius: radius,
        ),
        child: Text(
          code,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? context.palette.onAccent : context.palette.muted,
          ),
        ),
      ),
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({
    required this.tree,
    required this.path,
    required this.onPath,
  });

  final LibraryTree tree;
  final BrowsePath path;
  final ValueChanged<BrowsePath> onPath;

  @override
  Widget build(BuildContext context) {
    final category = path.category == null
        ? null
        : tree.category(path.category!);
    final topic = category == null || path.topic == null
        ? null
        : category.topic(path.topic!);

    return Wrap(
      spacing: 2,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Crumb(
          key: const Key('crumb-root'),
          label: tr('Biblioteca'),
          onTap: () => onPath(const BrowsePath()),
          last: category == null,
        ),
        if (category != null)
          _Crumb(
            key: const Key('crumb-category'),
            label: category.label,
            onTap: () => onPath(BrowsePath(category: category.category)),
            last: topic == null,
          ),
        if (topic != null)
          _Crumb(
            key: const Key('crumb-topic'),
            label: topic.label,
            onTap: path.tag == null
                ? null
                : () => onPath(
                    BrowsePath(
                      category: category?.category,
                      topic: topic.topic,
                    ),
                  ),
            last: path.tag == null,
          ),
        if (path.tag != null)
          _Crumb(
            key: const Key('crumb-tag'),
            label: humaniseSlug(path.tag!),
            onTap: null,
            last: true,
          ),
      ],
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({
    super.key,
    required this.label,
    required this.onTap,
    required this.last,
  });

  final String label;
  final VoidCallback? onTap;
  final bool last;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: last ? FontWeight.w700 : FontWeight.w400,
              color: last ? context.palette.ink : context.palette.accentDark,
            ),
          ),
        ),
      ),
      if (!last)
        Icon(Icons.chevron_right, size: 15, color: context.palette.muted),
    ],
  );
}

/// Los filtros puestos, como fichas que se quitan de un toque.
///
/// Un filtro activo que no se ve es la forma más rápida de que alguien crea
/// que le falta material.
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({
    required this.filter,
    required this.onFilter,
    required this.blocks,
  });

  final LibraryFilter filter;
  final ValueChanged<LibraryFilter> onFilter;
  final List<CourseBlock> blocks;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (filter.block != null)
        _Chip(
          // Con clave porque el nombre del bloque ya está en pantalla --en su
          // pestaña-- y una prueba que busque el texto encontraría los dos.
          key: const Key('filter-chip-block'),
          label: _blockName(blocks, filter.block!, filter.language),
          onRemove: () => onFilter(filter.copyWith(clearBlock: true)),
        ),
      if (filter.kind != null)
        _Chip(
          label: kindName(filter.kind!),
          colour: context.palette.kind(filter.kind!),
          onRemove: () => onFilter(filter.copyWith(clearKind: true)),
        ),
      if (filter.category != null)
        _Chip(
          label:
              sessionOf(
                context,
              ).catalogue.taxonomyTitle(filter.category!, filter.language) ??
              humaniseSlug(filter.category!),
          onRemove: () => onFilter(filter.copyWith(clearCategory: true)),
        ),
      if (filter.tag != null)
        _Chip(
          label: '#${filter.tag}',
          onRemove: () => onFilter(filter.copyWith(clearTag: true)),
        ),
      if (filter.status != StatusFilter.any)
        _Chip(
          label: switch (filter.status) {
            StatusFilter.present => tr('existe en {0}', [filter.language]),
            StatusFilter.missing => tr('falta en {0}', [filter.language]),
            StatusFilter.needsWork => tr('por revisar'),
            StatusFilter.any => '',
          },
          onRemove: () => onFilter(filter.copyWith(status: StatusFilter.any)),
        ),
      if (filter.unusedOnly)
        _Chip(
          label: tr('sin usar en ninguna asignatura'),
          onRemove: () => onFilter(filter.copyWith(unusedOnly: false)),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 5, runSpacing: 5, children: chips);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.onRemove,
    this.colour,
  });

  final String label;
  final VoidCallback onRemove;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final tone = colour ?? context.palette.accentDark;
    return InkWell(
      onTap: onRemove,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 3, 6, 3),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.10),
          border: Border.all(color: tone.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: tone,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.close,
              size: 13,
              color: tone,
              semanticLabel: tr('Quitar este filtro'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Explorar: el árbol
// ---------------------------------------------------------------------------

class _Browser extends StatelessWidget {
  const _Browser({
    required this.tree,
    required this.path,
    required this.language,
    required this.filter,
    required this.blocks,
    required this.onPath,
    required this.onFilter,
  });

  final LibraryTree tree;
  final BrowsePath path;
  final String language;
  final LibraryFilter filter;
  final List<CourseBlock> blocks;
  final ValueChanged<BrowsePath> onPath;
  final ValueChanged<LibraryFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final category = path.category == null
            ? null
            : tree.category(path.category!);

        // En estrecho se baja un nivel a la vez, con el migas de pan de la
        // cabecera para volver. Tres columnas de 130 px no son tres columnas.
        if (constraints.maxWidth < 760) {
          if (category == null) {
            return _CategoryColumn(
              tree: tree,
              path: path,
              language: language,
              filter: filter,
              blocks: blocks,
              onPath: onPath,
              onFilter: onFilter,
            );
          }
          if (path.topic == null) {
            return _TopicColumn(
              category: category,
              path: path,
              language: language,
              onPath: onPath,
            );
          }
          return _UnitColumn(
            category: category,
            path: path,
            language: language,
            sort: filter.sort,
            onPath: onPath,
          );
        }

        return Row(
          children: [
            SizedBox(
              width: 252,
              child: _CategoryColumn(
                tree: tree,
                path: path,
                language: language,
                filter: filter,
                blocks: blocks,
                onPath: onPath,
                onFilter: onFilter,
              ),
            ),
            const VerticalDivider(width: 1),
            if (category == null)
              Expanded(
                child: _Overview(
                  tree: tree,
                  language: language,
                  onPath: onPath,
                  filtered: _narrowing(filter)
                      ? filter.copyWith(clearBlock: true).describe()
                      : null,
                  onClear: () => onFilter(
                    LibraryFilter(
                      language: language,
                      sort: filter.sort,
                      block: filter.block,
                    ),
                  ),
                ),
              )
            else ...[
              SizedBox(
                width: 232,
                child: _TopicColumn(
                  category: category,
                  path: path,
                  language: language,
                  onPath: onPath,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _UnitColumn(
                  category: category,
                  path: path,
                  language: language,
                  sort: filter.sort,
                  onPath: onPath,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// La primera columna: el filtro de bloque y las categorías.
class _CategoryColumn extends StatelessWidget {
  const _CategoryColumn({
    required this.tree,
    required this.path,
    required this.language,
    required this.filter,
    required this.blocks,
    required this.onPath,
    required this.onFilter,
  });

  final LibraryTree tree;
  final BrowsePath path;
  final String language;
  final LibraryFilter filter;
  final List<CourseBlock> blocks;
  final ValueChanged<BrowsePath> onPath;
  final ValueChanged<LibraryFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.palette.panel,
      child: Column(
        children: [
          _BlockFilter(filter: filter, onFilter: onFilter, blocks: blocks),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _ColumnHeader(
                  label: tr('{0} categorías', [tree.categoryCount]),
                  count: tree.unitCount,
                  selected: path.isRoot,
                  onTap: () => onPath(const BrowsePath()),
                ),
                for (final category in tree.categories)
                  _CategoryRow(
                    category: category,
                    language: language,
                    selected: path.category == category.category,
                    onTap: () =>
                        onPath(BrowsePath(category: category.category)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Los bloques de la asignatura, o todos.
///
/// Un filtro y no un nivel del árbol: la teoría de espacios normados y sus
/// ejercicios son la misma asignatura, y separarlos obliga a mirar en dos
/// sitios lo que se prepara junto. Pero seguir queriendo ver solo las hojas
/// de problemas es razonable, y para eso está aquí.
///
/// Eran dos y estaban escritos aquí. Ahora son los que el repositorio
/// declare, así que quien parta su asignatura en teoría, problemas y
/// prácticas de ordenador ve tres pestañas sin que nadie toque este fichero.
///
/// **Con uno solo no aparece.** Un filtro cuyo único valor es «todo» ocupa el
/// alto de la columna para no contestar ninguna pregunta.
class _BlockFilter extends StatelessWidget {
  const _BlockFilter({
    required this.filter,
    required this.onFilter,
    required this.blocks,
  });

  final LibraryFilter filter;
  final ValueChanged<LibraryFilter> onFilter;
  final List<CourseBlock> blocks;

  @override
  Widget build(BuildContext context) {
    if (blocks.length < 2) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.palette.rule)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      child: Align(
        alignment: Alignment.centerLeft,
        // Del tamaño de sus palabras, no del ancho de la columna.
        //
        // Estaban con `Expanded` y en una ventana estrecha se convertían en
        // tres botones enormes que dominaban la pantalla: es un filtro, no
        // la acción principal. Agrupados en una sola cápsula además se leen
        // como lo que son, tres estados de lo mismo.
        child: Container(
          decoration: BoxDecoration(
            color: context.palette.panel,
            border: Border.all(color: context.palette.rule),
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          padding: const EdgeInsets.all(2),
          // `Flexible` y no `Expanded`: cada pestaña ocupa lo que dice su
          // palabra cuando hay sitio, y se encoge cuando no. La columna de
          // categorías puede quedarse en 200 px, y ahí las tres juntas no
          // caben; con `Expanded` siempre ocupaban todo el ancho, que era el
          // problema contrario.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: _BlockTab(
                  label: tr('Todo'),
                  selected: filter.block == null,
                  onTap: () => onFilter(filter.copyWith(clearBlock: true)),
                ),
              ),
              for (final block in blocks)
                Flexible(
                  child: _BlockTab(
                    label: block.title(filter.language),
                    selected: filter.block == block.id,
                    onTap: () => onFilter(filter.copyWith(block: block.id)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockTab extends StatelessWidget {
  const _BlockTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Hoverable(
    onTap: onTap,
    builder: (context, hovering) => AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: selected
            ? context.palette.card
            : (hovering ? context.palette.hover : Colors.transparent),
        borderRadius: BorderRadius.circular(Radii.small),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: context.palette.shadow.withValues(alpha: 0.08),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? context.palette.accentDark : context.palette.muted,
        ),
      ),
    ),
  );
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({
    required this.label,
    required this.count,
    this.onTap,
    this.selected = false,
  });

  final String label;
  final int count;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Hoverable(
    onTap: onTap,
    builder: (context, hovering) => Container(
      color: selected
          ? context.palette.accentDark.withValues(alpha: 0.08)
          : (hovering ? context.palette.hover : null),
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: context.palette.muted,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: context.palette.muted,
            ),
          ),
        ],
      ),
    ),
  );
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final CategoryNode category;
  final String language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = category.progressIn(language);
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        decoration: BoxDecoration(
          color: selected
              ? context.palette.card
              : (hovering ? context.palette.hover : Colors.transparent),
          border: Border(
            left: BorderSide(
              width: 3,
              color: selected
                  ? context.palette.accentDark
                  : (hovering
                        ? context.palette.accentDark.withValues(alpha: 0.35)
                        : Colors.transparent),
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(11, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    category.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${category.count}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.palette.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ProgressBar(progress: progress, height: 5),
          ],
        ),
      ),
    );
  }
}

/// La segunda columna: los temas de una categoría.
class _TopicColumn extends StatelessWidget {
  const _TopicColumn({
    required this.category,
    required this.path,
    required this.language,
    required this.onPath,
  });

  final CategoryNode category;
  final BrowsePath path;
  final String language;
  final ValueChanged<BrowsePath> onPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.palette.surface,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _ColumnHeader(
            label: tr('{0} temas', [category.topics.length]),
            count: category.count,
            selected: path.topic == null,
            onTap: () => onPath(BrowsePath(category: category.category)),
          ),
          for (final topic in category.topics)
            _TopicRow(
              topic: topic,
              language: language,
              selected: path.topic == topic.topic,
              onTap: () => onPath(path.toTopic(topic.topic)),
            ),
        ],
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({
    required this.topic,
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final TopicNode topic;
  final String language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? context.palette.accentDark.withValues(alpha: 0.08)
              : null,
          border: Border(bottom: BorderSide(color: context.palette.rule)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topic.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      for (final kind in topic.kinds.take(4))
                        Dot(colour: context.palette.kind(kind), size: 7),
                      const SizedBox(width: 6),
                      Text(
                        '${topic.count}',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.palette.muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: selected
                  ? context.palette.accentDark
                  : context.palette.rule,
            ),
          ],
        ),
      ),
    );
  }
}

/// La tercera columna: las unidades, como tarjetas.
///
/// Tarjetas y no filas: aquí hay una docena de cosas, no dos mil, así que el
/// sitio que sobra se gasta en que se lean. La densidad era la respuesta
/// correcta a una lista de 2147 y la equivocada a una de doce.
class _UnitColumn extends StatelessWidget {
  const _UnitColumn({
    required this.category,
    required this.path,
    required this.language,
    required this.onPath,
    this.sort = LibrarySort.path,
  });

  final CategoryNode category;
  final BrowsePath path;
  final String language;
  final ValueChanged<BrowsePath> onPath;

  /// El «Orden» de la cabecera, que antes solo ordenaba lo buscado.
  final LibrarySort sort;

  @override
  Widget build(BuildContext context) {
    final topic = path.topic == null ? null : category.topic(path.topic!);
    final groups = topic == null ? category.topics : [topic];
    // Las etiquetas del sitio donde se está, no las del catálogo: dentro de
    // un tema lo que se quiere es su reparto, no las cuatrocientas que hay en
    // la biblioteca entera.
    final tags = topic == null ? category.tags : topic.tags;
    final session = watchSession(context);
    // Crear aquí, en el tema que se mira: es donde se echa en falta la lección.
    final canCreate =
        session.admin() != null &&
        session.workspace.repos.any((repo) => session.canWriteIn(repo.id));

    // Una lista de filas y `ListView.builder`: se construye lo que se ve. Un
    // tema con cuatrocientos problemas eran cuatrocientas tarjetas hechas de
    // golpe para enseñar doce.
    final rows = <Widget Function()>[
      if (canCreate)
        () => Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const Key('library-new-unit'),
            icon: const Icon(Icons.add, size: 16),
            label: Text(
              topic == null
                  ? tr('Nueva lección en {0}', [category.label])
                  : tr('Nueva lección en {0}', [topic.label]),
            ),
            onPressed: () => createUnitFrom(
              context,
              session,
              category: category.category,
              topic: topic?.topic,
            ),
          ),
        ),
      if (tags.isNotEmpty) ...[
        () => _TagFilter(
          tags: tags,
          selected: path.tag,
          onSelected: (tag) => onPath(path.withTag(tag)),
        ),
        () => const SizedBox(height: 6),
      ],
      for (final group in groups)
        if (_shown(group.units) case final shown when shown.isNotEmpty) ...[
          () => Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    group.label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  shown.length == 1
                      ? tr('1 unidad')
                      : tr('{0} unidades', [shown.length]),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.palette.muted,
                  ),
                ),
              ],
            ),
          ),
          for (final unit in shown)
            () => UnitCard(unit: unit, language: language),
          () => const SizedBox(height: 16),
        ],
    ];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index](),
    );
  }

  List<Unit> _shown(List<Unit> units) =>
      LibraryFilter(language: language, sort: sort).apply([
        for (final unit in units)
          if (path.tag == null || unit.tags.contains(path.tag)) unit,
      ]);
}

/// Las etiquetas de donde se está, encima de la lista.
///
/// El nivel que falta entre el tema y los ficheros. Va aquí y no en el árbol
/// de la izquierda porque una unidad puede llevar varias etiquetas: en un
/// árbol saldría en varias ramas a la vez, y entonces los números de al lado
/// dejan de sumar lo que hay.
class _TagFilter extends StatelessWidget {
  const _TagFilter({
    required this.tags,
    required this.selected,
    required this.onSelected,
  });

  final List<TagCount> tags;
  final String? selected;

  /// `null` para quitar el filtro.
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: EdgeInsets.only(right: 3, bottom: 1),
          child: Text(
            tr('Etiquetas'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: context.palette.muted,
              letterSpacing: 0.4,
            ),
          ),
        ),
        for (final entry in tags)
          FilterChip(
            key: Key('tag-${entry.tag}'),
            label: Text('${humaniseSlug(entry.tag)} · ${entry.count}'),
            selected: selected == entry.tag,
            visualDensity: VisualDensity.compact,
            labelStyle: const TextStyle(fontSize: 12),
            // Volver a pulsar la que está puesta la quita: es el gesto que
            // todo el mundo intenta, y sin él hace falta buscar una equis.
            onSelected: (_) =>
                onSelected(selected == entry.tag ? null : entry.tag),
          ),
      ],
    );
  }
}

/// Una unidad como tarjeta.
class UnitCard extends StatelessWidget {
  const UnitCard({super.key, required this.unit, required this.language});

  final Unit unit;
  final String language;

  @override
  Widget build(BuildContext context) {
    final fallback = unit.titleIsFallback(language);
    final repoTint = watchSession(context).colourOf(unit.repo);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Hoverable(
        onTap: () => context.go(Routes.unit(unit.path)),
        builder: (context, hovering) => AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          decoration: BoxDecoration(
            color: context.palette.card,
            // Al pasar por encima: el borde se tiñe del verde de la casa y
            // aparece una sombra muy corta. Es lo que hace que una rejilla de
            // tarjetas se sienta viva sin que las miles de filas de las
            // listas lleven sombra, que sería ruido.
            border: Border.all(
              color: hovering
                  ? context.palette.accentDark
                  : context.palette.rule,
              width: hovering ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(Radii.card),
            boxShadow: hovering
                ? [
                    BoxShadow(
                      color: context.palette.shadow.withValues(alpha: 0.07),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          padding: EdgeInsets.fromLTRB(
            hovering ? 11.6 : 12,
            hovering ? 9.6 : 10,
            hovering ? 9.6 : 10,
            hovering ? 9.6 : 10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Dot(colour: context.palette.kind(unit.kind)),
                  ),
                  const SizedBox(width: 8),
                  // El repositorio del que sale, cuando hay más de uno: dos
                  // pueden tener la misma ruta y son cosas distintas.
                  if (repoTint != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 3, right: 6),
                      child: Container(
                        width: 3,
                        height: 14,
                        decoration: BoxDecoration(
                          color: context.palette.repo(repoTint),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                  Expanded(
                    child: Text(
                      unit.title(language),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        // Marcado cuando el título no está en el idioma
                        // pedido, para que un título castellano en un
                        // listado valenciano no se lea como traducido.
                        fontStyle: fallback
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: fallback ? context.palette.muted : null,
                      ),
                    ),
                  ),
                  QuickLookButton(
                    unit: unit,
                    language: language,
                    visible: hovering,
                  ),
                  if (unit.warnings.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: unit.warnings.join('\n'),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        size: 15,
                        color: context.palette.ex,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 9,
                runSpacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    kindName(unit.kind),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.palette.kind(unit.kind),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  for (final code in unit.statuses.keys)
                    StatusBadge(language: code, status: unit.statusIn(code)),
                  if (unit.usedBy.isEmpty)
                    Text(
                      tr('sin usar'),
                      style: TextStyle(fontSize: 11, color: context.palette.ex),
                    )
                  else
                    Tooltip(
                      message: unit.usedBy
                          .map((use) => use.toString())
                          .join('\n'),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.link,
                            size: 12,
                            color: context.palette.muted,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${unit.usedBy.length}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: context.palette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Al entrar, sin nada elegido: dónde está el material.
///
/// Antes esto era la lista de 2147 unidades, que no responde a ninguna
/// pregunta. Esto responde a la primera que tiene alguien que abre la
/// aplicación: qué hay, cuánto, y cuánto está traducido.
class _Overview extends StatelessWidget {
  const _Overview({
    required this.tree,
    required this.language,
    required this.onPath,
    this.filtered,
    this.onClear,
  });

  final LibraryTree tree;
  final String language;
  final ValueChanged<BrowsePath> onPath;

  /// Qué filtros hay puestos, dicho para leer; null sin ninguno.
  final String? filtered;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final all = tree.categories;
    // Nada que enseñar por culpa de los filtros: decirlo, y cuáles, en vez
    // de una pantalla vacía que parece una biblioteca sin material.
    if (all.isEmpty && filtered != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('Nada con estos filtros'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                filtered!,
                key: const Key('library-empty-filters'),
                style: TextStyle(fontSize: 12.5, color: context.palette.muted),
              ),
              const SizedBox(height: 10),
              TextButton(
                key: const Key('library-clear-filters'),
                onPressed: onClear,
                child: Text(tr('Quitar los filtros')),
              ),
            ],
          ),
        ),
      );
    }
    final whole = TranslationProgress.of(tree.byPath.values, language);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Tarjetas de unos 280 px: dos columnas en un portátil, cuatro en un
        // monitor, una en una ventana estrecha.
        final columns = (constraints.maxWidth / 280).floor().clamp(1, 4);
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          children: [
            Text(
              tr('Dónde está el material'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              tr(
                'Las categorías de mayor a menor. La barra de cada una es el '
                'estado del {0}.',
                [languageName(language)],
              ),
              style: TextStyle(fontSize: 12.5, color: context.palette.muted),
            ),
            const SizedBox(height: 9),
            ProgressLegend(progress: whole),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 9,
              crossAxisSpacing: 9,
              childAspectRatio: 2.9,
              children: [
                for (final category in all)
                  _CategoryCard(
                    category: category,
                    language: language,
                    onTap: () =>
                        onPath(BrowsePath(category: category.category)),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.language,
    required this.onTap,
  });

  final CategoryNode category;
  final String language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = category.progressIn(language);
    return Material(
      color: context.palette.card,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: context.palette.rule),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                category.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${category.count}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Expanded: «· 49 temas · 39 probl.» no cabe en una tarjeta
                  // estrecha, y sin esto desborda en lugar de recortarse.
                  Expanded(
                    child: Text(
                      tr(
                        '· {0} temas'
                        '{1}',
                        [
                          category.topics.length,
                          category.problems > 0
                              ? tr(' · {0} probl.', [category.problems])
                              : '',
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.palette.muted,
                      ),
                    ),
                  ),
                ],
              ),
              ProgressBar(progress: progress),
            ],
          ),
        ),
      ),
    );
  }
}

/// La barra de traducción: al día, por revisar y sin escribir.
///
/// Tres tramos y no un porcentaje, porque un porcentaje junta los dos casos
/// que necesitan trabajo distinto: nada escrito, y escrito pero desfasado.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.progress, this.height = 6});

  final TranslationProgress progress;
  final double height;

  /// El gris de lo que no está escrito. Es la vía de la barra además del
  /// tramo, para que una barra sin nada hecho siga siendo una barra y no un
  /// hueco: «no hay nada» y «no se dibujó» tienen que distinguirse.
  static Color trackIn(DidactaPalette palette) => palette.track;

  @override
  Widget build(BuildContext context) {
    if (progress.total == 0) return SizedBox(height: height);
    return Tooltip(
      message: tr(
        '{0} al día · {1} por revisar · '
        '{2} sin escribir',
        [progress.done, progress.needsWork, progress.missing],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Container(
          height: height,
          color: trackIn(context.palette),
          // Estirados: un `ColoredBox` sin hijo mide cero de alto, y la barra
          // enseñaba solo la vía gris aunque todo estuviera al día.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (progress.done > 0)
                Expanded(
                  flex: progress.done,
                  child: ColoredBox(color: context.palette.accentDark),
                ),
              if (progress.needsWork > 0)
                Expanded(
                  flex: progress.needsWork,
                  child: ColoredBox(color: context.palette.ex),
                ),
              if (progress.missing > 0)
                Expanded(flex: progress.missing, child: const SizedBox()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Qué significan los colores de la barra.
///
/// Sin esto la barra es decoración: tres colores que nadie sabe leer. Y aquí
/// hace falta de verdad, porque el migrador dejó 2057 unidades en `draft`, y
/// una pared ámbar sin explicación parece un error en lugar de lo que es
/// —material migrado que nadie ha revisado todavía—.
class ProgressLegend extends StatelessWidget {
  const ProgressLegend({super.key, required this.progress});

  final TranslationProgress progress;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 5,
    children: [
      _key(
        context,
        context.palette.accentDark,
        tr('{0} al día', [progress.done]),
      ),
      _key(
        context,
        context.palette.ex,
        tr('{0} por revisar', [progress.needsWork]),
      ),
      _key(
        context,
        ProgressBar.trackIn(context.palette),
        tr('{0} sin escribir', [progress.missing]),
      ),
    ],
  );

  Widget _key(BuildContext context, Color colour, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: TextStyle(fontSize: 11.5, color: context.palette.muted),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Buscar
// ---------------------------------------------------------------------------

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.filter,
    required this.units,
    required this.blocks,
    required this.onFilter,
    this.inText = false,
    this.hits,
    this.onSave,
  });

  final LibraryFilter filter;
  final List<Unit> units;
  final List<CourseBlock> blocks;
  final ValueChanged<LibraryFilter> onFilter;

  /// Guardar esta búsqueda, en la interfaz completa.
  final VoidCallback? onSave;

  /// Si se busca también en el texto, y lo encontrado ahí (null mientras se
  /// busca).
  final bool inText;
  final List<TextHit>? hits;

  @override
  Widget build(BuildContext context) {
    final titled = filter.apply(units);
    final facets = LibraryFacets.of(units, filter);
    // Lo encontrado en el texto, por lección. Primero lo que casa por el
    // título --es lo que más se parece a lo que se busca-- y después lo que
    // solo lo dice dentro, con los mismos filtros puestos.
    final byPath = <String, List<TextHit>>{};
    for (final hit in hits ?? const <TextHit>[]) {
      (byPath[hit.unitPath] ??= []).add(hit);
    }
    // Por la ruta, y por el repositorio cuando se sabe: dos repositorios
    // pueden tener la misma ruta y son lecciones distintas.
    List<TextHit>? linesOf(Unit unit) {
      final found = [
        for (final hit in byPath[unit.path] ?? const <TextHit>[])
          if (unit.repo.isEmpty || hit.repo.isEmpty || hit.repo == unit.repo)
            hit,
      ];
      return found.isEmpty ? null : found;
    }

    final facetsOnly = filter.copyWith(query: '');
    final seen = titled.toSet();
    final inside = [
      for (final unit in units)
        if (!seen.contains(unit) &&
            facetsOnly.matches(unit) &&
            linesOf(unit) != null)
          unit,
    ];
    // Lo que se parece --casa con una errata-- va al final, detrás también
    // de lo que lo dice dentro: eso sí es lo que se ha escrito.
    final typos = filter.typosIn(units);
    final near = [
      for (final unit in titled)
        if (filter.queryMatch(unit, typos: typos) == SearchMatch.near) unit,
    ];
    final nearSet = near.toSet();
    final found = [
      for (final unit in titled)
        if (!nearSet.contains(unit)) unit,
      ...inside,
      ...near,
    ];
    final nearNote = near.isEmpty
        ? ''
        : near.length == found.length
        ? (near.length == 1
              ? tr(' · ninguna tal cual, se parece a lo que buscas')
              : tr(' · ninguna tal cual, se parecen a lo que buscas'))
        : near.length == 1
        ? tr(' · 1 parecida')
        : tr(' · {0} parecidas', [near.length]);
    final String textNote;
    if (!inText) {
      textNote = '';
    } else if (hits == null) {
      textNote = tr(' · buscando en el texto…');
    } else if (inside.isEmpty) {
      textNote = '';
    } else {
      textNote = tr(' · {0} por lo que dicen dentro', [inside.length]);
    }
    final summary = found.isEmpty
        ? (inText && hits == null
              ? tr('Buscando en el texto…')
              : tr('Nada coincide'))
        : found.length == 1
        ? tr('1 unidad de {0}{1}{2}', [facets.total, textNote, nearNote])
        : tr('{0} unidades de {1}{2}{3}', [
            found.length,
            facets.total,
            textNote,
            nearNote,
          ]);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Column(
          children: [
            Container(
              width: double.infinity,
              color: context.palette.panel,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      summary,
                      key: const Key('search-summary'),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.palette.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (onSave != null)
                    TextButton.icon(
                      key: const Key('save-search'),
                      icon: const Icon(Icons.bookmark_add_outlined, size: 15),
                      label: Text(tr('Guardar esta búsqueda')),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onSave,
                    ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  if (wide) ...[
                    SizedBox(
                      width: 236,
                      child: FilterPanel(
                        facets: facets,
                        filter: filter,
                        blocks: blocks,
                        onChanged: onFilter,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                  ],
                  Expanded(
                    child: UnitList(
                      units: found,
                      filter: filter,
                      lines: {for (final unit in found) unit: ?linesOf(unit)},
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
