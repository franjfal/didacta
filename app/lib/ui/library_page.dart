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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../model/catalogue.dart';
import '../model/library_filter.dart';
import '../model/library_tree.dart';
import '../router.dart';
import '../state/session.dart';
import 'library_search.dart';
import 'quick_look.dart';
import 'shell.dart';
import 'theme.dart';

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
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  BrowsePath _path = const BrowsePath();
  LibraryFilter? _filter;

  /// El árbol se construye una vez por catálogo, no por frame: recorrer 2147
  /// unidades para contar una insignia es justo lo que hace que un scroll dé
  /// tirones sin que nadie sepa por qué.
  LibraryTree? _tree;
  Catalogue? _treeFor;
  String? _treeBlock;

  @override
  void initState() {
    super.initState();
    // Qué hay compilado, una vez. Es lo que decide qué lecciones se pueden
    // ojear, y se pregunta aquí y no en cada tarjeta porque la respuesta es
    // una sola para las dos mil.
    scheduleMicrotask(() {
      final session = context.read<Session>();
      if (!session.builtKnown) session.refreshBuilt();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// El árbol, sobre las unidades del área elegida.
  ///
  /// Se reconstruye al cambiar de catálogo o de bloque, no por frame: es una
  /// pasada sobre 2147 unidades y ocurre cuando alguien pulsa un filtro.
  LibraryTree _treeOf(Catalogue catalogue, String? block) {
    if (_treeFor != catalogue || _treeBlock != block) {
      _tree = LibraryTree.of(
        block == null
            ? catalogue.units
            : catalogue.units.where((unit) => unit.block == block),
      );
      _treeFor = catalogue;
      _treeBlock = block;
    }
    return _tree!;
  }

  bool get _searching => _search.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);
    final catalogue = session.catalogue;

    // El idioma vive en la sesión para que el recuento del carril y esta
    // pantalla no puedan discrepar sobre a qué idioma se refieren.
    _filter ??= LibraryFilter(language: session.language);
    if (_filter!.language != session.language) {
      _filter = _filter!.copyWith(language: session.language);
    }
    final filter = _filter!.copyWith(query: _search.text.trim());
    // El mismo filtro de área gobierna el árbol y la búsqueda, para que las
    // dos vistas no puedan estar mirando material distinto.
    final tree = _treeOf(catalogue, filter.block);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_searching) {
            setState(_search.clear);
          } else if (!_path.isRoot) {
            setState(() => _path = _path.up());
          }
        },
      },
      child: Column(
        children: [
          _Header(
            tree: tree,
            session: session,
            filter: filter,
            search: _search,
            searchFocus: _searchFocus,
            searching: _searching,
            path: _path,
            onFilter: (next) => setState(() => _filter = next),
            onSearchChanged: () => setState(() {}),
            onPath: (next) => setState(() => _path = next),
          ),
          Expanded(
            child: _searching
                ? _SearchResults(
                    filter: filter,
                    units: catalogue.units,
                    onFilter: (next) => setState(() => _filter = next),
                  )
                : _Browser(
                    tree: tree,
                    path: _path,
                    language: session.language,
                    filter: filter,
                    onPath: (next) => setState(() => _path = next),
                    onFilter: (next) => setState(() {
                      _filter = next;
                      // Cambiar de área cambia qué categorías hay, así que
                      // una selección anterior puede haber desaparecido.
                      _path = const BrowsePath();
                    }),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// La cabecera y los menús
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.tree,
    required this.session,
    required this.filter,
    required this.search,
    required this.searchFocus,
    required this.searching,
    required this.path,
    required this.onFilter,
    required this.onSearchChanged,
    required this.onPath,
  });

  final LibraryTree tree;
  final Session session;
  final LibraryFilter filter;
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
      decoration: const BoxDecoration(
        color: didactaSurface,
        border: Border(bottom: BorderSide(color: didactaRule)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 700;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // La biblioteca tiene su propia cabecera --con el buscador y
              // los idiomas-- pero el botón de volver tiene que estar en
              // todas: si falta en una pantalla, deja de ser una forma de
              // moverse y pasa a ser una que a veces está.
              const Align(
                alignment: Alignment.centerLeft,
                child: BackForward(),
              ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Text(
                            'Biblioteca',
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
                                ? 'Buscando «${filter.query}»'
                                : '${tree.unitCount} unidades · '
                                      '${tree.categoryCount} categorías · '
                                      '${tree.topicCount} temas',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: didactaMuted,
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
                    _PreviewPicker(session: session),
                    const SizedBox(width: 8),
                  ],
                  _LanguagePicker(session: session),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (!narrow) ...[
                    _LibraryMenus(filter: filter, onFilter: onFilter),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: _SearchField(
                      controller: search,
                      focus: searchFocus,
                      onChanged: onSearchChanged,
                    ),
                  ),
                  if (narrow) ...[
                    const SizedBox(width: 4),
                    _LibraryMenus(
                      filter: filter,
                      onFilter: onFilter,
                      compact: true,
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
                _ActiveFilters(filter: filter, onFilter: onFilter),
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
    this.compact = false,
  });

  final LibraryFilter filter;
  final ValueChanged<LibraryFilter> onFilter;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return MenuAnchor(
        builder: (context, controller, child) => IconButton(
          tooltip: 'Ver y filtrar',
          icon: Badge(
            isLabelVisible: filter.isNarrowed,
            child: const Icon(Icons.tune, size: 20),
          ),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
        menuChildren: [
          ..._blockItems(),
          const Divider(height: 1),
          ..._statusItems(),
          const Divider(height: 1),
          ..._kindItems(),
          const Divider(height: 1),
          ..._sortItems(),
          const Divider(height: 1),
          ..._extraItems(),
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
          menuChildren: [
            ..._statusItems(),
            const Divider(height: 1),
            ..._extraItems(),
          ],
          child: const Text('Traducción'),
        ),
        SubmenuButton(menuChildren: _kindItems(), child: const Text('Tipo')),
        SubmenuButton(menuChildren: _sortItems(), child: const Text('Orden')),
      ],
    );
  }

  List<Widget> _blockItems() => [
    _check(
      'Todo',
      filter.block == null,
      () => onFilter(filter.copyWith(clearBlock: true)),
    ),
    _check(
      'Teoría',
      filter.block == 'theory',
      () => onFilter(filter.copyWith(block: 'theory')),
    ),
    _check(
      'Problemas',
      filter.block == 'problems',
      () => onFilter(filter.copyWith(block: 'problems')),
    ),
  ];

  List<Widget> _statusItems() => [
    for (final (status, label) in const [
      (StatusFilter.any, 'Cualquier estado'),
      (StatusFilter.present, 'Existe en este idioma'),
      (StatusFilter.missing, 'Falta en este idioma'),
      (StatusFilter.needsWork, 'Por revisar o desactualizada'),
    ])
      _check(
        label,
        filter.status == status,
        () => onFilter(filter.copyWith(status: status)),
      ),
  ];

  List<Widget> _kindItems() => [
    _check(
      'Cualquier tipo',
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
        leadingIcon: Dot(colour: kindColour(kind)),
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

  List<Widget> _sortItems() => [
    for (final (sort, label) in const [
      (LibrarySort.path, 'Por ruta'),
      (LibrarySort.title, 'Por título'),
      (LibrarySort.usage, 'Más usadas primero'),
      (LibrarySort.needsWork, 'Por traducir primero'),
    ])
      _check(
        label,
        filter.sort == sort,
        () => onFilter(filter.copyWith(sort: sort)),
      ),
  ];

  List<Widget> _extraItems() => [
    _check(
      'Solo las que no usa ninguna asignatura',
      filter.unusedOnly,
      () => onFilter(filter.copyWith(unusedOnly: !filter.unusedOnly)),
    ),
    if (filter.isNarrowed)
      MenuItemButton(
        leadingIcon: const Icon(Icons.filter_alt_off_outlined, size: 15),
        onPressed: () => onFilter(
          LibraryFilter(language: filter.language, sort: filter.sort),
        ),
        child: const Text('Quitar los filtros'),
      ),
  ];

  Widget _check(String label, bool on, VoidCallback onPressed) =>
      MenuItemButton(
        leadingIcon: Icon(
          on ? Icons.check : null,
          size: 15,
          color: didactaAccentDark,
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
  });

  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(7),
      borderSide: const BorderSide(color: didactaRule),
    );
    return TextField(
      controller: controller,
      focusNode: focus,
      style: const TextStyle(fontSize: 13.5),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        hintText: 'Buscar por título, ruta o etiqueta…',
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 16),
                tooltip: 'Limpiar',
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
  Widget build(BuildContext context) {
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
        message: 'Qué versión se abre al ojear una lección',
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
                  ? didactaAccentDark
                  : didactaMuted,
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
    final languages = session.catalogue.languages;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: didactaRule),
        borderRadius: BorderRadius.circular(7),
        color: Colors.white,
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
          color: selected ? didactaAccentDark : Colors.transparent,
          borderRadius: radius,
        ),
        child: Text(
          code,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : didactaMuted,
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
          label: 'Biblioteca',
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
              color: last ? didactaInk : didactaAccentDark,
            ),
          ),
        ),
      ),
      if (!last) const Icon(Icons.chevron_right, size: 15, color: didactaMuted),
    ],
  );
}

/// Los filtros puestos, como fichas que se quitan de un toque.
///
/// Un filtro activo que no se ve es la forma más rápida de que alguien crea
/// que le falta material.
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.filter, required this.onFilter});

  final LibraryFilter filter;
  final ValueChanged<LibraryFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (filter.block != null)
        _Chip(
          label: filter.block == 'problems' ? 'problemas' : 'teoría',
          onRemove: () => onFilter(filter.copyWith(clearBlock: true)),
        ),
      if (filter.kind != null)
        _Chip(
          label: kindName(filter.kind!),
          colour: kindColour(filter.kind!),
          onRemove: () => onFilter(filter.copyWith(clearKind: true)),
        ),
      if (filter.category != null)
        _Chip(
          label: humaniseSlug(filter.category!),
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
            StatusFilter.present => 'existe en ${filter.language}',
            StatusFilter.missing => 'falta en ${filter.language}',
            StatusFilter.needsWork => 'por revisar',
            StatusFilter.any => '',
          },
          onRemove: () => onFilter(filter.copyWith(status: StatusFilter.any)),
        ),
      if (filter.unusedOnly)
        _Chip(
          label: 'sin usar en ninguna asignatura',
          onRemove: () => onFilter(filter.copyWith(unusedOnly: false)),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 5, runSpacing: 5, children: chips);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onRemove, this.colour});

  final String label;
  final VoidCallback onRemove;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final tone = colour ?? didactaAccentDark;
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
            Icon(Icons.close, size: 13, color: tone),
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
    required this.onPath,
    required this.onFilter,
  });

  final LibraryTree tree;
  final BrowsePath path;
  final String language;
  final LibraryFilter filter;
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

/// La primera columna: el filtro de área y las categorías.
class _CategoryColumn extends StatelessWidget {
  const _CategoryColumn({
    required this.tree,
    required this.path,
    required this.language,
    required this.filter,
    required this.onPath,
    required this.onFilter,
  });

  final LibraryTree tree;
  final BrowsePath path;
  final String language;
  final LibraryFilter filter;
  final ValueChanged<BrowsePath> onPath;
  final ValueChanged<LibraryFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: didactaPanel,
      child: Column(
        children: [
          _AreaFilter(filter: filter, onFilter: onFilter),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _ColumnHeader(
                  label: '${tree.categoryCount} categorías',
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

/// Teoría, problemas o las dos.
///
/// Un filtro y no un nivel del árbol: la teoría de espacios normados y sus
/// ejercicios son la misma asignatura, y separarlos obliga a mirar en dos
/// sitios lo que se prepara junto. Pero seguir queriendo ver solo las hojas
/// de problemas es razonable, y para eso está aquí.
class _AreaFilter extends StatelessWidget {
  const _AreaFilter({required this.filter, required this.onFilter});

  final LibraryFilter filter;
  final ValueChanged<LibraryFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: didactaRule)),
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
            color: didactaPanel,
            border: Border.all(color: didactaRule),
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
                child: _AreaTab(
                  label: 'Todo',
                  selected: filter.block == null,
                  onTap: () => onFilter(filter.copyWith(clearBlock: true)),
                ),
              ),
              Flexible(
                child: _AreaTab(
                  label: 'Teoría',
                  selected: filter.block == 'theory',
                  onTap: () => onFilter(filter.copyWith(block: 'theory')),
                ),
              ),
              Flexible(
                child: _AreaTab(
                  label: 'Problemas',
                  selected: filter.block == 'problems',
                  onTap: () => onFilter(filter.copyWith(block: 'problems')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AreaTab extends StatelessWidget {
  const _AreaTab({
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
            ? didactaCard
            : (hovering ? didactaHover : Colors.transparent),
        borderRadius: BorderRadius.circular(Radii.small),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: didactaInk.withValues(alpha: 0.08),
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
          color: selected ? didactaAccentDark : didactaMuted,
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
          ? didactaAccentDark.withValues(alpha: 0.08)
          : (hovering ? didactaHover : null),
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: didactaMuted,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: didactaMuted,
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
              ? didactaCard
              : (hovering ? didactaHover : Colors.transparent),
          border: Border(
            left: BorderSide(
              width: 3,
              color: selected
                  ? didactaAccentDark
                  : (hovering
                        ? didactaAccentDark.withValues(alpha: 0.35)
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
                  style: const TextStyle(fontSize: 11.5, color: didactaMuted),
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
      color: didactaSurface,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _ColumnHeader(
            label: '${category.topics.length} temas',
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
          color: selected ? didactaAccentDark.withValues(alpha: 0.08) : null,
          border: const Border(bottom: BorderSide(color: didactaRule)),
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
                        Dot(colour: kindColour(kind), size: 7),
                      const SizedBox(width: 6),
                      Text(
                        '${topic.count}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: didactaMuted,
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
              color: selected ? didactaAccentDark : didactaRule,
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
  });

  final CategoryNode category;
  final BrowsePath path;
  final String language;
  final ValueChanged<BrowsePath> onPath;

  @override
  Widget build(BuildContext context) {
    final topic = path.topic == null ? null : category.topic(path.topic!);
    final groups = topic == null ? category.topics : [topic];
    // Las etiquetas del sitio donde se está, no las del catálogo: dentro de
    // un tema lo que se quiere es su reparto, no las cuatrocientas que hay en
    // la biblioteca entera.
    final tags = topic == null ? category.tags : topic.tags;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        if (tags.isNotEmpty) ...[
          _TagFilter(
            tags: tags,
            selected: path.tag,
            onSelected: (tag) => onPath(path.withTag(tag)),
          ),
          const SizedBox(height: 6),
        ],
        for (final group in groups)
          if (_shown(group.units) case final shown when shown.isNotEmpty) ...[
            Padding(
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
                    '${shown.length} '
                    '${shown.length == 1 ? 'unidad' : 'unidades'}',
                    style: const TextStyle(fontSize: 11.5, color: didactaMuted),
                  ),
                ],
              ),
            ),
            for (final unit in shown) UnitCard(unit: unit, language: language),
            const SizedBox(height: 16),
          ],
      ],
    );
  }

  List<Unit> _shown(List<Unit> units) => path.tag == null
      ? units
      : [
          for (final unit in units)
            if (unit.tags.contains(path.tag)) unit,
        ];
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
        const Padding(
          padding: EdgeInsets.only(right: 3, bottom: 1),
          child: Text(
            'Etiquetas',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: didactaMuted,
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
    final repoColour = watchSession(context).colourOf(unit.repo);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Hoverable(
        onTap: () => context.go(Routes.unit(unit.path)),
        builder: (context, hovering) => AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          decoration: BoxDecoration(
            color: didactaCard,
            // Al pasar por encima: el borde se tiñe del verde de la casa y
            // aparece una sombra muy corta. Es lo que hace que una rejilla de
            // tarjetas se sienta viva sin que las miles de filas de las
            // listas lleven sombra, que sería ruido.
            border: Border.all(
              color: hovering ? didactaAccentDark : didactaRule,
              width: hovering ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(Radii.card),
            boxShadow: hovering
                ? [
                    BoxShadow(
                      color: didactaInk.withValues(alpha: 0.07),
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
                    child: Dot(colour: kindColour(unit.kind)),
                  ),
                  const SizedBox(width: 8),
                  // El repositorio del que sale, cuando hay más de uno: dos
                  // pueden tener la misma ruta y son cosas distintas.
                  if (repoColour != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 3, right: 6),
                      child: Container(
                        width: 3,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Color(repoColour),
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
                        color: fallback ? didactaMuted : null,
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
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        size: 15,
                        color: didactaEx,
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
                      color: kindColour(unit.kind),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  for (final code in unit.statuses.keys)
                    StatusBadge(language: code, status: unit.statusIn(code)),
                  if (unit.usedBy.isEmpty)
                    const Text(
                      'sin usar',
                      style: TextStyle(fontSize: 11, color: didactaEx),
                    )
                  else
                    Tooltip(
                      message: unit.usedBy
                          .map((use) => use.toString())
                          .join('\n'),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.link, size: 12, color: didactaMuted),
                          const SizedBox(width: 2),
                          Text(
                            '${unit.usedBy.length}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: didactaMuted,
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
  });

  final LibraryTree tree;
  final String language;
  final ValueChanged<BrowsePath> onPath;

  @override
  Widget build(BuildContext context) {
    final all = tree.categories;
    final whole = TranslationProgress.of(tree.byPath.values, language);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Tarjetas de unos 280 px: dos columnas en un portátil, cuatro en un
        // monitor, una en una ventana estrecha.
        final columns = (constraints.maxWidth / 280).floor().clamp(1, 4);
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          children: [
            const Text(
              'Dónde está el material',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              'Las categorías de mayor a menor. La barra de cada una es el '
              'estado del ${languageName(language)}.',
              style: const TextStyle(fontSize: 12.5, color: didactaMuted),
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: didactaRule),
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
                      '· ${category.topics.length} temas'
                      '${category.problems > 0 ? ' · ${category.problems} probl.' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: didactaMuted),
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
  static const Color track = Color(0xFFDCE0E4);

  @override
  Widget build(BuildContext context) {
    if (progress.total == 0) return SizedBox(height: height);
    return Tooltip(
      message:
          '${progress.done} al día · ${progress.needsWork} por revisar · '
          '${progress.missing} sin escribir',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Container(
          height: height,
          color: track,
          child: Row(
            children: [
              if (progress.done > 0)
                Expanded(
                  flex: progress.done,
                  child: const ColoredBox(color: didactaAccentDark),
                ),
              if (progress.needsWork > 0)
                Expanded(
                  flex: progress.needsWork,
                  child: const ColoredBox(color: didactaEx),
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
      _key(didactaAccentDark, '${progress.done} al día'),
      _key(didactaEx, '${progress.needsWork} por revisar'),
      _key(ProgressBar.track, '${progress.missing} sin escribir'),
    ],
  );

  Widget _key(Color colour, String label) => Row(
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
      Text(label, style: const TextStyle(fontSize: 11.5, color: didactaMuted)),
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
    required this.onFilter,
  });

  final LibraryFilter filter;
  final List<Unit> units;
  final ValueChanged<LibraryFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final found = filter.apply(units);
    final facets = LibraryFacets.of(units, filter);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Column(
          children: [
            Container(
              width: double.infinity,
              color: didactaPanel,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: Text(
                found.isEmpty
                    ? 'Nada coincide'
                    : '${found.length} '
                          '${found.length == 1 ? 'unidad' : 'unidades'} '
                          'de ${facets.total}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: didactaMuted,
                  fontWeight: FontWeight.w600,
                ),
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
                        onChanged: onFilter,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                  ],
                  Expanded(
                    child: UnitList(units: found, filter: filter),
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
