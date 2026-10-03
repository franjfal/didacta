/// Editar el material: los metadatos que discrepan entre repositorios, los
/// idiomas de cada uno, los títulos, las titulaciones, los bloques, los
/// snippets, las plantillas de compilación y el estado de cada traducción.
///
/// Era una parte de la sesión --casi un tercio--. Aparte porque son
/// operaciones que escriben ficheros del material y recargan el catálogo, y de
/// la sesión solo necesitan lo que cualquier pantalla le pide: el catálogo,
/// las pasarelas de cada repositorio y el motor. La sesión las sigue
/// ofreciendo con los mismos nombres.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../data/diagnostics.dart';
import '../data/content_gateway.dart';
import '../data/indenter.dart';
import '../data/template_store.dart';
import '../model/catalogue.dart';
import '../model/composition_file.dart';
import '../model/degrees_file.dart';
import '../model/file_history.dart' show FileCommit;
import '../model/latex_snippets.dart';
import '../model/snippets_file.dart';
import '../model/source_hash.dart';
import '../model/taxonomy_file.dart';
import '../model/templates_file.dart';
import '../model/themes_file.dart';
import '../model/translation_run.dart';
import '../model/yaml_patch.dart';

import 'session.dart';
import '../l10n/tr.dart';

class CatalogueEditor {
  CatalogueEditor(this.session, {required this.onChanged});

  final Session session;

  /// Avisar a quien mira: la sesión, que avisa a las pantallas.
  final VoidCallback onChanged;

  // -- metadatos que discrepan entre repositorios -------------------------

  /// Iguala un campo de una asignatura en todos los repositorios.
  ///
  /// Escribe [value] en el `course.yaml` de cada repositorio que diga otra
  /// cosa, y no toca los que ya coinciden ni los que no lo declaran: rellenar
  /// lo que falta es otra decisión.
  ///
  /// Por líneas, con [YamlPatch], como el resto de ediciones de YAML aquí:
  /// un `course.yaml` lleva comentarios y `# TODO` que dicen qué falta por
  /// rellenar, y volver a serializarlo se los lleva por delante.
  ///
  /// Un commit por repositorio, porque son historiales distintos. Devuelve en
  /// cuántos se escribió.
  Future<int> resolveMetadata({
    required MetadataConflict conflict,
    required String value,
  }) async {
    final path = conflict.path;
    if (path == null) {
      throw ArgumentError(
        tr('no sé dónde se escribe «{0}»', [conflict.fieldLabel]),
      );
    }
    final where = 'courses/${conflict.course}/course.yaml';
    var written = 0;

    for (final entry in conflict.values.entries) {
      if (entry.value == value) continue;
      final gateway = session.gatewayFor(entry.key);
      if (!gateway.canWrite) continue;

      final file = await gateway.read(where);
      final patch = YamlPatch(file.text);
      if (conflict.field == 'idiomas') {
        patch.setFlowList(path, [
          for (final code in value.split(',')) code.trim(),
        ]);
      } else {
        patch.setScalar(path, value);
      }
      if (patch.result == file.text) continue;

      await gateway.save(
        path: where,
        text: patch.result,
        sha: file.sha,
        message: tr('Igualar {0} de {1}', [
          conflict.fieldLabel,
          conflict.course,
        ]),
      );
      written += 1;
    }
    if (written > 0) await session.reloadCatalogue();
    return written;
  }

  /// Cambia a qué idiomas se da una asignatura.
  ///
  /// En **todos** los repositorios que la declaran, no solo en uno. Una
  /// asignatura partida tiene un `course.yaml` en cada uno y los dos han de
  /// decir lo mismo: escribir en uno solo convierte el cambio en una
  /// discrepancia de metadatos que hay que resolver a mano después, y deja al
  /// otro repositorio pidiendo traducciones que ya no se quieren.
  ///
  /// Un repositorio de solo lectura se salta en silencio. No es un fallo --se
  /// puede mirar material de otra persona-- pero sí queda la asignatura
  /// diciendo dos cosas, y de eso ya avisa la sección de discrepancias.
  ///
  /// Quitar un idioma no borra nada: los `.tex` que hubiera siguen donde
  /// estaban, simplemente dejan de pedirse. Volver a activarlo los recupera.
  ///
  /// Devuelve en cuántos repositorios se escribió.
  Future<int> setCourseLanguages({
    required String course,
    required List<String> languages,
  }) async {
    if (languages.isEmpty) {
      throw ArgumentError(tr('una asignatura tiene que darse en algún idioma'));
    }
    final entry = session.courseById(course);
    if (entry == null) {
      throw ArgumentError(tr('no existe la asignatura {0}', [course]));
    }

    final where = 'courses/$course/course.yaml';
    // El orden es el del catálogo, no el de los clics: así el fichero sale
    // igual se marque como se marque, y no hay diffs que solo mueven códigos.
    final options =
        session.catalogueOrNull?.languageOptions ?? const <LanguageOption>[];
    final ordered = <String>[
      for (final option in options)
        if (languages.contains(option.code)) option.code,
      // Lo que se pide y el índice no conoce se escribe igual, al final: con
      // un índice viejo, ordenar no puede ser motivo para perder un idioma.
      for (final code in languages)
        if (!options.any((o) => o.code == code)) code,
    ];
    final written = <String>[];

    for (final repo in entry.sources.keys) {
      final gateway = session.gatewayFor(repo);
      if (!gateway.canWrite) continue;

      // Lo que se pide, cruzado con lo que **este** repositorio mantiene.
      //
      // Escribir la lista entera en todos era lo que se hacía, y produce un
      // `course.yaml` que el motor rechaza: una asignatura no puede darse en
      // un idioma que su repositorio no traduce, porque no habría dónde poner
      // su `.tex`. Rechazada, la asignatura desaparece del catálogo con un
      // error, así que el fallo no se veía al guardar sino al volver a
      // indexar. Repartida entre dos repositorios, cada uno declara lo suyo y
      // la unión de los dos es en lo que se da --que es como la lee el
      // catálogo--.
      final keeps = session.catalogueOrNull?.languagesOf(repo) ?? ordered;
      // Lo que este `course.yaml` ya dice pasa igual, lo entienda el índice o
      // no: puede estar viejo, y una lista que no se reconoce se conserva en
      // lugar de podarse. Quitar un idioma es una decisión, y esta pantalla
      // no la ha tomado.
      final already = entry.sources[repo]?.languages ?? const <String>[];
      final mine = [
        for (final code in ordered)
          if (keeps.contains(code) || already.contains(code)) code,
      ];
      // Ninguno: este repositorio no mantiene nada de lo que se ha pedido.
      // Escribir una lista vacía sería peor que no escribir --el motor la lee
      // como «los del repositorio», o sea justo lo contrario-- así que se
      // deja como está y lo dice quien llama contando los que se tocaron.
      if (mine.isEmpty) continue;

      final file = await gateway.read(where);
      final patch = YamlPatch(file.text);
      patch.setFlowList(const ['languages'], mine);
      if (patch.result == file.text) continue;

      await gateway.save(
        path: where,
        text: patch.result,
        sha: file.sha,
        message: tr('Idiomas de {0}: {1}', [course, mine.join(', ')]),
      );
      written.add(repo);
    }
    if (written.isNotEmpty) await session.reloadCatalogue();
    return written.length;
  }

  // -- los idiomas de un repositorio --------------------------------------

  /// Las asignaturas de [repo] que se dan en [code].
  ///
  /// Lo que hay que mirar antes de quitar un idioma del repositorio: el motor
  /// rechaza un `course.yaml` que declare uno que su repositorio no mantiene,
  /// y una asignatura rechazada no sale en el catálogo. Quitarlo sin mirar es
  /// hacer desaparecer material de la biblioteca.
  List<Course> coursesUsing(String repo, String code) => [
    for (final course in session.catalogueOrNull?.courses ?? const <Course>[])
      if (course.sources[repo]?.languages.contains(code) ?? false) course,
  ];

  /// Cambia a qué idiomas traduce un repositorio, en su `didacta.yaml`.
  ///
  /// Es la lista de la que cuelga todo lo demás: una asignatura solo puede
  /// declararse en uno de estos, y una unidad solo tiene hueco de traducción
  /// en uno de estos. Por eso quitar uno que está en uso **no se hace**: se
  /// lanza diciendo qué asignaturas lo usan, y se quita antes de ellas.
  ///
  /// El idioma de referencia sigue a la lista: si se queda fuera, pasa a ser
  /// el primero de los que quedan. Dejarlo apuntando a un idioma que ya no
  /// está hace que el motor no pueda ni leer el fichero.
  ///
  /// Al terminar se regenera el índice de ese repositorio, a la fuerza y sin
  /// esperar a que el disco avise. La lista de idiomas sale en el índice, así
  /// que hasta regenerarlo la interfaz seguiría ofreciendo la de antes; y a la
  /// fuerza porque quien acaba de marcar una casilla espera verla aplicada, no
  /// que se compruebe si hacía falta.
  ///
  /// Solo el suyo: regenerar los de al lado son segundos por nada.
  Future<void> setRepoLanguages({
    required String repo,
    required List<String> languages,
  }) async {
    if (languages.isEmpty) {
      throw ArgumentError(
        tr('un repositorio tiene que traducir a algún idioma'),
      );
    }
    final gateway = session.gatewayFor(repo);
    if (!gateway.canWrite) {
      throw ArgumentError(tr('no se puede escribir en {0}', [repo]));
    }

    final before =
        session.catalogueOrNull?.languagesOf(repo) ?? const <String>[];
    for (final code in before) {
      if (languages.contains(code)) continue;
      final using = coursesUsing(repo, code);
      if (using.isEmpty) continue;
      throw ArgumentError(
        tr(
          'no se puede quitar {0} de {1}: se dan en ese idioma '
          '{2}',
          [
            code,
            repo,
            using.map((course) => course.title(session.language)).join(', '),
          ],
        ),
      );
    }

    // En el orden del registro, por lo mismo que en una asignatura: el
    // fichero sale igual se marque como se marque.
    final ordered = [
      for (final option in session.namedLanguages(languages)) option.code,
    ];

    const where = 'didacta.yaml';
    final file = await gateway.read(where);
    final patch = YamlPatch(file.text)
      ..setFlowList(const ['languages'], ordered);

    // El de referencia, si se ha quedado fuera. Se escribe aunque no estuviera
    // declarado: el motor lo deduce del primero de la lista, así que callarse
    // aquí cambiaría el idioma de referencia del repositorio de rebote.
    final reference = patch.scalar(const ['default_language']);
    if (reference != null && !ordered.contains(reference)) {
      patch.setScalar(const ['default_language'], ordered.first);
    }

    if (patch.result != file.text) {
      await gateway.save(
        path: where,
        text: patch.result,
        sha: file.sha,
        message: tr('Idiomas de {0}: {1}', [repo, ordered.join(', ')]),
      );
    }

    await session.refreshIndex(force: true, only: repo);
    await session.reloadCatalogue();
  }

  // -- los títulos, en todos los idiomas ----------------------------------

  /// Cambia el título de una asignatura, en todos los idiomas a la vez.
  ///
  /// En todos los repositorios que la declaran, por lo mismo que los idiomas:
  /// una asignatura partida tiene un `course.yaml` en cada uno y si dicen
  /// cosas distintas el título que se enseña depende de en qué orden se
  /// abrieron los repositorios.
  ///
  /// Un idioma vacío borra ese título. No se escribe cadena vacía --sería un
  /// título de verdad, y saldría en el PDF-- sino que se quita la línea.
  Future<int> setCourseTitles({
    required String course,
    required Map<String, String> titles,
  }) async {
    final entry = session.courseById(course);
    if (entry == null) {
      throw ArgumentError(tr('no existe la asignatura {0}', [course]));
    }
    if (titles.values.every((value) => value.trim().isEmpty)) {
      throw ArgumentError(
        tr('una asignatura sin título se enseñaría por su id'),
      );
    }

    final where = 'courses/$course/course.yaml';
    final written = <String>[];
    for (final repo in entry.sources.keys) {
      final gateway = session.gatewayFor(repo);
      if (!gateway.canWrite) continue;

      final file = await gateway.read(where);
      final patch = YamlPatch(file.text);
      for (final item in titles.entries) {
        final value = item.value.trim();
        if (value.isEmpty) {
          patch.remove(['title', item.key]);
        } else {
          patch.setScalar(['title', item.key], value);
        }
      }
      if (patch.result == file.text) continue;

      await gateway.save(
        path: where,
        text: patch.result,
        sha: file.sha,
        message: tr('Título de {0}', [course]),
      );
      written.add(repo);
    }
    if (written.isNotEmpty) await session.reloadCatalogue();
    return written.length;
  }

  /// Cambia el título de un tema, en el repositorio que lo declara.
  ///
  /// En ese y en ninguno más: un tema lo declara **uno** --los demás solo lo
  /// nombran desde sus documentos-- así que aquí no hay nada que hacer
  /// converger. Esa asimetría es lo que permite que quien no tenga el
  /// repositorio que declara el tema siga viendo todo su material.
  Future<void> setThemeTitles({
    required String repo,
    required String course,
    required String year,
    required String id,
    required Map<String, String> titles,
  }) async {
    final where = 'courses/$course/$year/themes.yaml';
    final gateway = session.gatewayFor(repo);
    final file = await gateway.read(where);
    final themes = ThemesFile(file.text)..setTitles(id, titles);
    if (themes.text == file.text) return;

    await gateway.save(
      path: where,
      text: themes.text,
      sha: file.sha,
      message: tr('Título del tema {0} en {1} {2}', [id, course, year]),
    );
    await session.reloadCatalogue();
  }

  /// Cambia el título de un documento, en el `year.yaml` donde vive.
  ///
  /// En el suyo y solo el suyo: un documento está en un repositorio, y su
  /// composición --qué unidades lleva-- también, que es la regla que sostiene
  /// que esto funcione con varios repositorios abiertos.
  Future<void> setDocumentTitles({
    required String repo,
    required String course,
    required String year,
    required String id,
    required Map<String, String> titles,
  }) async {
    final where = 'courses/$course/$year/year.yaml';
    final gateway = session.gatewayFor(repo);
    final file = await gateway.read(where);
    final composition = CompositionFile(file.text)
      ..setDocumentTitles(id, titles);
    if (composition.text == file.text) return;

    await gateway.save(
      path: where,
      text: composition.text,
      sha: file.sha,
      message: tr('Título de {0} en {1} {2}', [id, course, year]),
    );
    await session.reloadCatalogue();
  }

  // -- las titulaciones ---------------------------------------------------

  /// Cambia a qué grado pertenece una asignatura.
  ///
  /// En todos los repositorios que la declaran, por lo mismo que los idiomas:
  /// si dicen cosas distintas, la asignatura sale en un grado o en otro según
  /// en qué orden se abrieron los repositorios.
  ///
  /// [degree] vacío la deja sin grado, que es un estado legítimo: no todo lo
  /// que se da pertenece a una titulación, y obligar a elegir una inventaría
  /// grados para no dejar huecos.
  Future<int> setCourseDegree({
    required String course,
    required String? degree,
  }) async {
    final entry = session.courseById(course);
    if (entry == null) {
      throw ArgumentError(tr('no existe la asignatura {0}', [course]));
    }

    final where = 'courses/$course/course.yaml';
    final written = <String>[];
    for (final repo in entry.sources.keys) {
      final gateway = session.gatewayFor(repo);
      if (!gateway.canWrite) continue;

      final file = await gateway.read(where);
      final patch = YamlPatch(file.text);
      if ((degree ?? '').isEmpty) {
        patch.remove(const ['degree_id']);
      } else {
        patch.setScalar(const ['degree_id'], degree!);
      }
      if (patch.result == file.text) continue;

      await gateway.save(
        path: where,
        text: patch.result,
        sha: file.sha,
        message: (degree ?? '').isEmpty
            ? tr('Quitar el grado de {0}', [course])
            : tr('Grado de {0}: {1}', [course, degree]),
      );
      written.add(repo);
    }
    if (written.isNotEmpty) await session.reloadCatalogue();
    return written.length;
  }

  /// Declara un grado nuevo en un repositorio.
  ///
  /// En **uno**, no en todos: un grado lo declara quien lo tenga y los demás
  /// lo nombran desde sus asignaturas. Declararlo en los dos no rompe nada
  /// --se fusionan por id-- pero es lo que hace que luego discrepen.
  Future<void> createDegree({
    required String repo,
    required String id,
    required Map<String, String> titles,
    String? institution,
  }) async {
    final gateway = session.gatewayFor(repo);
    if (!gateway.canWrite) {
      throw ArgumentError(tr('no se puede escribir en {0}', [repo]));
    }
    const where = 'degrees.yaml';

    String text;
    // Vacío cuando el fichero no existe todavía: es lo que la pasarela
    // entiende por «no había nada aquí».
    var sha = '';
    try {
      final file = await gateway.read(where);
      text = file.text;
      sha = file.sha;
    } on ContentException catch (error) {
      if (error.kind != ContentFailure.missing) rethrow;
      // Se crea con sus comentarios, que explican por qué un grado que nadie
      // declara no rompe nada.
      text = emptyDegreesYaml;
    }

    final degrees = DegreesFile(text)
      ..add(
        id: id,
        titles: titles,
        institution: institution,
        languages: session.catalogueOrNull?.languages ?? const ['es'],
      );

    await gateway.save(
      path: where,
      text: degrees.text,
      sha: sha,
      message: tr('Declarar el grado {0}', [id]),
    );
    await session.reloadCatalogue();
  }

  /// Deja de declarar un grado en un repositorio.
  ///
  /// Las asignaturas que lo nombran siguen nombrándolo: un grado que no
  /// declara nadie no agrupa, y sus asignaturas salen enteras. Por eso esto
  /// no puede perder material, y por eso «Grados» las sigue enseñando como
  /// nombradas y sin declarar.
  Future<void> undeclareDegree({
    required String repo,
    required String id,
  }) async {
    final gateway = session.gatewayFor(repo);
    if (!gateway.canWrite) {
      throw ArgumentError(tr('no se puede escribir en {0}', [repo]));
    }
    const where = 'degrees.yaml';
    final file = await gateway.read(where);
    final degrees = DegreesFile(file.text)..remove(id);
    if (degrees.text == file.text) return;

    await gateway.save(
      path: where,
      text: degrees.text,
      sha: file.sha,
      message: tr('Dejar de declarar el grado {0}', [id]),
    );
    await session.reloadCatalogue();
  }

  /// Cambia el título de un grado, en todos los idiomas a la vez.
  ///
  /// En los repositorios que lo declaran, que pueden ser varios: si lo
  /// declaran dos y solo se cambia en uno, la discrepancia aparece al momento.
  Future<int> setDegreeTitles({
    required String id,
    required Map<String, String> titles,
  }) async {
    final degree = session.catalogueOrNull?.degrees
        .where((entry) => entry.id == id)
        .firstOrNull;
    if (degree == null) {
      throw ArgumentError(tr('no se declara el grado {0}', [id]));
    }

    const where = 'degrees.yaml';
    final written = <String>[];
    for (final repo in degree.sources.keys) {
      final gateway = session.gatewayFor(repo);
      if (!gateway.canWrite) continue;

      final file = await gateway.read(where);
      final degrees = DegreesFile(file.text)..setTitles(id, titles);
      if (degrees.text == file.text) continue;

      await gateway.save(
        path: where,
        text: degrees.text,
        sha: file.sha,
        message: tr('Título del grado {0}', [id]),
      );
      written.add(repo);
    }
    if (written.isNotEmpty) await session.reloadCatalogue();
    return written.length;
  }

  // -- los bloques --------------------------------------------------------

  /// Declara un bloque en un repositorio.
  ///
  /// En **uno**. Declararlo en varios es corriente aquí, a diferencia de los
  /// grados --la teoría y los problemas repartidos necesitan los dos
  /// bloques-- pero se hace llamando a esto una vez por repositorio, para que
  /// cada uno sea su propio commit en su propio historial.
  ///
  /// El fichero se crea si no existía, con sus comentarios: son la única
  /// explicación de por qué un bloque que nadie declara no esconde nada.
  Future<void> declareBlock({
    required String repo,
    required String id,
    required Map<String, String> titles,
  }) async {
    final gateway = session.gatewayFor(repo);
    if (!gateway.canWrite) {
      throw ArgumentError(tr('no se puede escribir en {0}', [repo]));
    }
    const where = 'taxonomy.yaml';

    String text;
    // Vacío cuando el fichero no existe todavía: es lo que la pasarela
    // entiende por «no había nada aquí».
    var sha = '';
    try {
      final file = await gateway.read(where);
      text = file.text;
      sha = file.sha;
    } on ContentException catch (error) {
      if (error.kind != ContentFailure.missing) rethrow;
      text = emptyTaxonomyYaml;
    }

    final taxonomy = TaxonomyFile(text)
      ..addBlock(
        id: id,
        titles: titles,
        languages: session.catalogueOrNull?.languagesOf(repo) ?? const ['es'],
      );

    await gateway.save(
      path: where,
      text: taxonomy.text,
      sha: sha,
      message: tr('Declarar el bloque {0}', [id]),
    );
    await _reindexAfterTaxonomy(repo);
  }

  // -- categorías, temas y subtemas ---------------------------------------

  /// Declara un sitio de la biblioteca --una categoría, un tema o un
  /// subtema-- en **todos** los repositorios abiertos en los que se puede
  /// escribir, con lo que le falte por encima.
  ///
  /// En todos y no en uno: la teoría y los problemas de una asignatura viven
  /// en dos, y los dos tienen que enseñar las mismas columnas. Si un subtema
  /// nuevo se declarara solo en el de teoría, los problemas que se lleven a
  /// él saldrían en uno con nombre y en otro con el id. Un commit en cada uno,
  /// porque son historiales distintos.
  ///
  /// [titles] es el nombre por idioma del sitio nuevo. Los de los niveles de
  /// encima, si a algún repositorio le faltan, se copian de lo que ya
  /// declara el otro.
  ///
  /// Devuelve en cuántos repositorios se escribió.
  Future<int> declarePlace({
    required String key,
    required Map<String, String> titles,
  }) async {
    final catalogue = session.catalogueOrNull;
    final parts = key.split('/');
    final named = <String, Map<String, String>>{
      for (var depth = 1; depth < parts.length; depth += 1)
        parts.sublist(0, depth).join('/'):
            catalogue?.taxonomyTitles[parts.sublist(0, depth).join('/')] ??
            {'es': parts[depth - 1]},
      key: titles,
    };

    const where = 'taxonomy.yaml';
    final written = <String>[];
    for (final repo in session.workspace.repos) {
      if (!session.canWriteIn(repo.id)) continue;
      final gateway = session.gatewayFor(repo.id);
      if (!gateway.canWrite) continue;

      String text;
      var sha = '';
      try {
        final file = await gateway.read(where);
        text = file.text;
        sha = file.sha;
      } on ContentException catch (error) {
        if (error.kind != ContentFailure.missing) rethrow;
        text = emptyTaxonomyYaml;
      }
      final taxonomy = TaxonomyFile(text);
      final changed = taxonomy.declarePlace(
        key,
        titles: named,
        languages: catalogue?.languagesOf(repo.id) ?? const ['es'],
      );
      if (!changed) continue;

      await gateway.save(
        path: where,
        text: taxonomy.text,
        sha: sha,
        message: switch (parts.length) {
          1 => tr('Declarar la categoría {0}', [key]),
          2 => tr('Declarar el tema {0}', [key]),
          _ => tr('Declarar el subtema {0}', [key]),
        },
      );
      written.add(repo.id);
    }
    for (final repo in written) {
      await _reindexAfterTaxonomy(repo, reload: false);
    }
    if (written.isNotEmpty) await session.reloadCatalogue();
    return written.length;
  }

  /// Deja de declarar un bloque en un repositorio.
  ///
  /// Solo la declaración de ese repositorio: las lecciones que lo nombran
  /// siguen nombrándolo, y si no queda nadie que lo declare salen como
  /// huérfanas en «Entre repositorios». Quitarlo de todas partes y decidir
  /// qué pasa con sus lecciones es [removeBlock].
  Future<void> undeclareBlock({
    required String repo,
    required String id,
  }) async {
    final gateway = session.gatewayFor(repo);
    if (!gateway.canWrite) {
      throw ArgumentError(tr('no se puede escribir en {0}', [repo]));
    }
    const where = 'taxonomy.yaml';
    final file = await gateway.read(where);
    final taxonomy = TaxonomyFile(file.text)..removeBlock(id);
    if (taxonomy.text == file.text) return;

    await gateway.save(
      path: where,
      text: taxonomy.text,
      sha: file.sha,
      message: tr('Dejar de declarar el bloque {0}', [id]),
    );
    await _reindexAfterTaxonomy(repo);
  }

  /// Cambia el nombre de un bloque, en todos los idiomas a la vez.
  ///
  /// En los repositorios que lo declaran, que aquí suelen ser varios: si lo
  /// declaran dos y solo se cambia en uno, la discrepancia aparece al momento
  /// y la misma lección se ve bajo un nombre u otro según la máquina.
  ///
  /// Devuelve en cuántos se escribió.
  Future<int> setBlockTitles({
    required String id,
    required Map<String, String> titles,
  }) async {
    final block = session.catalogueOrNull?.blocks
        .where((entry) => entry.id == id)
        .firstOrNull;
    if (block == null) {
      throw ArgumentError(tr('no se declara el bloque {0}', [id]));
    }

    const where = 'taxonomy.yaml';
    final written = <String>[];
    for (final repo in block.sources.keys) {
      final gateway = session.gatewayFor(repo);
      if (!gateway.canWrite) continue;

      final file = await gateway.read(where);
      final taxonomy = TaxonomyFile(file.text)..setBlockTitles(id, titles);
      if (taxonomy.text == file.text) continue;

      await gateway.save(
        path: where,
        text: taxonomy.text,
        sha: file.sha,
        message: tr('Nombre del bloque {0}', [id]),
      );
      written.add(repo);
    }
    for (final repo in written) {
      await _reindexAfterTaxonomy(repo, reload: false);
    }
    if (written.isNotEmpty) await session.reloadCatalogue();
    return written.length;
  }

  /// Quita un bloque de todos los repositorios que lo declaren.
  ///
  /// Con [moveTo], sus lecciones se mueven antes a ese otro bloque; sin él,
  /// se quedan nombrándolo y salen como huérfanas. Las dos cosas son
  /// legítimas y por eso se pregunta: lo que no puede pasar es que noventa
  /// lecciones se queden clasificadas en ninguna parte sin que nadie lo haya
  /// decidido.
  ///
  /// **Primero se mueven y después se quita la declaración.** Al revés, entre
  /// una cosa y la otra el repositorio queda un momento con lecciones
  /// huérfanas, y si algo falla a mitad se queda así.
  ///
  /// Un repositorio de solo lectura se salta en silencio, y entonces el
  /// bloque sigue existiendo por él. No es un fallo --se puede mirar material
  /// de otra persona-- y la pantalla lo dice antes de pulsar.
  ///
  /// Devuelve cuántas lecciones se movieron.
  Future<int> removeBlock({required String id, String? moveTo}) async {
    final block = session.catalogueOrNull?.blocks
        .where((entry) => entry.id == id)
        .firstOrNull;
    if (block == null) {
      throw ArgumentError(tr('no se declara el bloque {0}', [id]));
    }
    if (moveTo == id) {
      throw ArgumentError(tr('un bloque no se puede mover a sí mismo'));
    }

    var moved = 0;
    if (moveTo != null) {
      moved = await moveUnitsBetweenBlocks(from: id, to: moveTo);
    }

    const where = 'taxonomy.yaml';
    final written = <String>[];
    for (final repo in block.sources.keys) {
      final gateway = session.gatewayFor(repo);
      if (!gateway.canWrite) continue;

      final file = await gateway.read(where);
      final taxonomy = TaxonomyFile(file.text);
      if (!taxonomy.blockIds.contains(id)) continue;
      taxonomy.removeBlock(id);

      await gateway.save(
        path: where,
        text: taxonomy.text,
        sha: file.sha,
        message: moveTo == null
            ? tr('Quitar el bloque {0}', [id])
            : tr('Quitar el bloque {0}, con sus lecciones a {1}', [id, moveTo]),
      );
      written.add(repo);
    }
    for (final repo in written) {
      await _reindexAfterTaxonomy(repo, reload: false);
    }
    await session.reloadCatalogue();
    return moved;
  }

  /// Mueve de bloque todas las lecciones que nombren [from].
  ///
  /// Un commit por repositorio y no uno por lección: mover noventa lecciones
  /// es **un** cambio --una decisión, una frase que la explica-- y noventa
  /// commits seguidos que dicen lo mismo dejan el historial sin servir para
  /// ver qué cambió de verdad.
  ///
  /// Devuelve cuántas se movieron.
  Future<int> moveUnitsBetweenBlocks({
    required String from,
    required String to,
  }) async {
    final units = session.catalogueOrNull?.unitsInBlock(from) ?? const <Unit>[];
    if (units.isEmpty) return 0;

    final byRepo = <String, List<Unit>>{};
    for (final unit in units) {
      byRepo.putIfAbsent(unit.repo, () => []).add(unit);
    }

    var moved = 0;
    for (final entry in byRepo.entries) {
      final gateway = session.gatewayFor(entry.key);
      if (!gateway.canWrite) continue;

      final files = <({String path, String text, String sha})>[];
      for (final unit in entry.value) {
        final where = unit.metadataPath;
        final file = await gateway.read(where);
        final patch = YamlPatch(file.text)..setScalar(const ['block'], to);
        if (patch.result == file.text) continue;
        files.add((path: where, text: patch.result, sha: file.sha));
      }
      if (files.isEmpty) continue;

      await gateway.saveAll(
        files: files,
        message: files.length == 1
            ? tr('Mover una lección de {0} a {1}', [from, to])
            : tr('Mover {0} lecciones de {1} a {2}', [files.length, from, to]),
      );
      moved += files.length;
    }
    if (moved > 0) await session.reloadCatalogue();
    return moved;
  }

  /// Cambia el bloque de una lección, en su `unit.yaml`.
  ///
  /// En el suyo y solo el suyo: una lección vive en un repositorio, y a qué
  /// parte de la asignatura pertenece lo dice ella.
  Future<void> setUnitBlock({
    required String repo,
    required String path,
    required String block,
  }) async {
    final where = '$path/unit.yaml';
    final gateway = session.gatewayFor(repo);
    final file = await gateway.read(where);
    final patch = YamlPatch(file.text)..setScalar(const ['block'], block);
    if (patch.result == file.text) return;

    await gateway.save(
      path: where,
      text: patch.result,
      sha: file.sha,
      message: tr('Bloque de {0}: {1}', [path, block]),
    );
    await session.reloadCatalogue();
  }

  /// Con qué plantillas se compila un bloque, por defecto.
  ///
  /// En todos los repositorios que lo declaran, por lo mismo que el nombre:
  /// si dicen cosas distintas, lo que sale de compilar depende de en qué
  /// orden se abrieron -- y eso se descubre cuando falta media clase.
  ///
  /// Lista vacía es «todas las activas», que es un estado legítimo y el que
  /// tiene un bloque recién declarado.
  Future<int> setBlockTemplates({
    required String id,
    required List<String> templates,
  }) async {
    final block = session.catalogueOrNull?.blocks
        .where((entry) => entry.id == id)
        .firstOrNull;
    if (block == null) {
      throw ArgumentError(tr('no se declara el bloque {0}', [id]));
    }

    const where = 'taxonomy.yaml';
    final written = <String>[];
    for (final repo in block.sources.keys) {
      final gateway = session.gatewayFor(repo);
      if (!gateway.canWrite) continue;

      final file = await gateway.read(where);
      final taxonomy = TaxonomyFile(file.text)
        ..setBlockTemplates(id, templates);
      if (taxonomy.text == file.text) continue;

      await gateway.save(
        path: where,
        text: taxonomy.text,
        sha: file.sha,
        message: tr('Plantillas del bloque {0}', [id]),
      );
      written.add(repo);
    }
    for (final repo in written) {
      await _reindexAfterTaxonomy(repo, reload: false);
    }
    if (written.isNotEmpty) await session.reloadCatalogue();
    return written.length;
  }

  // -- los snippets ---------------------------------------------------------
  //
  // Lo que la barra del editor envuelve, repositorio a repositorio. Se
  // declaran en el `snippets.yaml` de cada uno, y el mismo id en dos es el
  // mismo snippet: guardar uno escribe en todos los repositorios elegidos y
  // lo quita de los demás. Ver `model/latex_snippets.dart`.

  /// Dónde vive la lista de snippets de un repositorio.
  static const String snippetsPath = 'snippets.yaml';

  /// Los repositorios abiertos, en el orden en que se abrieron: el orden en
  /// que se cosen sus listas y en que se enseñan en el gestor.
  ///
  /// Dentro de esta clase se pregunta a la sesión (`session.snippetRepos`) y
  /// no aquí: quien la extiende para una prueba cambia los repositorios ahí.
  List<String> get snippetRepos => [
    for (final repo in session.openedWorkspace.repos) repo.id,
  ];

  /// Lo que ofrece la barra en el repositorio [repo].
  List<LatexSnippet> snippetsIn(String? repo) =>
      session.catalogueOrNull?.snippetsIn(repo) ?? didactaSnippets;

  /// Todos los snippets de los repositorios abiertos, con dónde está cada uno.
  List<SnippetEntry> get snippetLibrary =>
      session.catalogueOrNull?.snippetLibrary(session.snippetRepos) ??
      [
        for (final snippet in didactaSnippets)
          SnippetEntry(id: snippet.id, byRepo: const {}, base: snippet.base),
      ];

  /// Los snippets que dos repositorios declaran distinto.
  List<SnippetConflict> get snippetConflicts =>
      session.catalogueOrNull?.snippetConflicts(session.snippetRepos) ??
      const [];

  /// Guarda [snippet] en los repositorios [repos] y lo quita de los demás.
  ///
  /// Uno de serie que no cambia nada se escribe como `- id: …`; uno propio,
  /// entero --ver [LatexSnippet.toDeclaration]--. En un repositorio que no
  /// tenía `snippets.yaml`, el fichero nuevo empieza con la lista de serie
  /// escrita: sin fichero ofrecía esos, y añadir uno propio no puede
  /// quitarlos.
  ///
  /// Los repositorios en los que no se puede escribir se saltan, y el gestor
  /// ya lo dice antes de pulsar. Devuelve en cuántos se escribió.
  Future<int> saveSnippet(
    LatexSnippet snippet, {
    required Set<String> repos,
  }) async {
    final declaration = snippet.toDeclaration();
    final order = [for (final entry in snippetLibrary) entry.id];
    final written = <String>[];
    for (final repo in session.snippetRepos) {
      final wanted = repos.contains(repo);
      // Donde ya está y dice lo mismo, no se toca: reescribir la entrada
      // borraría cómo la dejó quien la escribió a mano, para no cambiar nada.
      final there = snippetsIn(repo).where((s) => s.id == snippet.id);
      if (wanted && there.isNotEmpty && there.first.sameAs(snippet)) continue;
      final changed = await _editSnippets(
        repo,
        wanted
            ? tr('Snippet «{0}»', [snippet.label])
            : tr('Quitar el snippet «{0}»', [snippet.label]),
        (file) {
          if (!wanted) {
            if (!file.has(snippet.id)) return;
            file.remove(snippet.id);
            return;
          }
          file.put(declaration, after: _snippetBefore(order, snippet.id, file));
        },
        // Quitarlo de un repositorio que no lo tiene no es motivo para
        // escribirle un fichero.
        onlyIfDeclares: !wanted && !_offers(repo, snippet.id),
      );
      if (changed) written.add(repo);
    }
    await _afterSnippets(written);
    return written.length;
  }

  /// Quita un snippet de todos los repositorios en que se pueda escribir.
  Future<int> removeSnippet(LatexSnippet snippet) =>
      saveSnippet(snippet, repos: const {});

  /// Ordena los snippets de cada repositorio como [order].
  ///
  /// Un orden para todos, el de la biblioteca: cada repositorio se queda con
  /// los suyos en ese orden. Uno sin fichero solo se escribe si su orden
  /// cambia de verdad.
  Future<int> reorderSnippets(List<String> order) async {
    final written = <String>[];
    for (final repo in session.snippetRepos) {
      final mine = [for (final s in snippetsIn(repo)) s.id];
      final sorted = [
        for (final id in order)
          if (mine.contains(id)) id,
        for (final id in mine)
          if (!order.contains(id)) id,
      ];
      if (_sameOrder(mine, sorted)) continue;
      final changed = await _editSnippets(
        repo,
        tr('Ordenar los snippets'),
        (file) => file.reorder(order),
      );
      if (changed) written.add(repo);
    }
    await _afterSnippets(written);
    return written.length;
  }

  /// Iguala un snippet que no coincide: lo que dice [repo], en los demás que
  /// lo tienen.
  Future<int> useSnippetFrom({required String id, required String repo}) async {
    final source = snippetsIn(repo).where((s) => s.id == id).firstOrNull;
    if (source == null) {
      throw ArgumentError(tr('{0} no tiene el snippet {1}', [repo, id]));
    }
    final entry = snippetLibrary.where((e) => e.id == id).firstOrNull;
    final written = <String>[];
    for (final other in entry?.byRepo.keys ?? const <String>[]) {
      if (other == repo) continue;
      final changed = await _editSnippets(
        other,
        tr('Igualar el snippet «{0}»', [source.label]),
        (file) => file.put(source.toDeclaration()),
      );
      if (changed) written.add(other);
    }
    await _afterSnippets(written);
    return written.length;
  }

  /// Compila el snippet tal como está en la pantalla, sin guardarlo.
  ///
  /// En [repo] --o en el primero que haya-- porque el motor necesita un
  /// repositorio donde dejar el PDF. En [language], o en el de trabajo: una
  /// caja con el título traducido se mira idioma a idioma. Null si aquí no
  /// se puede compilar: en la web, o sin motor.
  Future<SnippetPreview?> previewSnippet(
    LatexSnippet snippet, {
    String profile = 'notes',
    String? language,
    String? repo,
    void Function(String line)? onOutput,
  }) async {
    final where = repo ?? session.snippetRepos.firstOrNull;
    final compiler = session.liveCompiler(repo: where);
    if (compiler == null) return null;
    final out = await compiler.run(
      [
        'snippet-preview',
        '--definition-text',
        snippet.definition,
        '--body-text',
        snippet.previewBody,
        '-p',
        profile,
        '-l',
        language ?? session.language,
        '--json',
      ],
      allowFailure: true,
      onOutput: onOutput,
    );
    try {
      return SnippetPreview.fromJson(
        (jsonDecode(out) as Map).cast<String, dynamic>(),
      );
    } on FormatException {
      return SnippetPreview(
        ok: false,
        engineFailed: true,
        errors: [
          out.trim().isEmpty ? tr('El motor no ha contestado.') : out.trim(),
        ],
      );
    }
  }

  /// Si la barra de [repo] ofrece [id] hoy, con fichero o sin él.
  bool _offers(String repo, String id) =>
      snippetsIn(repo).any((snippet) => snippet.id == id);

  /// Detrás de cuál va uno nuevo en [file]: el que tiene delante en el orden
  /// de la biblioteca y ya está en el fichero.
  String? _snippetBefore(List<String> order, String id, SnippetsFile file) {
    final at = order.indexOf(id);
    for (var i = (at < 0 ? order.length : at) - 1; i >= 0; i -= 1) {
      if (file.has(order[i])) return order[i];
    }
    return null;
  }

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Lee, cambia y guarda el `snippets.yaml` de [repo]. Si no existe, empieza
  /// con la lista de serie escrita.
  ///
  /// Devuelve si se escribió algo. Un repositorio de solo lectura no se
  /// toca; con [onlyIfDeclares], tampoco uno que no tiene fichero.
  Future<bool> _editSnippets(
    String repo,
    String message,
    void Function(SnippetsFile file) edit, {
    bool onlyIfDeclares = false,
  }) async {
    final gateway = session.gatewayFor(repo);
    if (!gateway.canWrite) return false;
    String? before;
    var sha = '';
    try {
      final file = await gateway.read(snippetsPath);
      before = file.text;
      sha = file.sha;
    } on ContentException catch (error) {
      if (error.kind != ContentFailure.missing) rethrow;
    }
    if (before == null && onlyIfDeclares) return false;
    final file = before == null
        ? SnippetsFile.withDefaults()
        : SnippetsFile(before);
    edit(file);
    if (file.text == before) return false;
    // Sin fichero y con el cambio, lo mismo que sin fichero: los de serie tal
    // cual. Escribirlo sería un commit que no dice nada.
    if (before == null && file.text == SnippetsFile.withDefaults().text) {
      return false;
    }
    await gateway.save(
      path: snippetsPath,
      text: file.text,
      sha: sha,
      message: message,
    );
    return true;
  }

  /// Vuelve a indexar lo escrito, para que la barra lo vea ya.
  Future<void> _afterSnippets(List<String> written) async {
    for (final repo in written) {
      await _reindexAfterTaxonomy(repo, reload: false);
    }
    if (written.isNotEmpty) await session.reloadCatalogue();
  }

  // -- las plantillas de compilación --------------------------------------

  /// El «repositorio» que es la carpeta del programa.
  ///
  /// Un id que ningún repositorio puede tener --lleva una arroba-- para poder
  /// usar los mismos métodos con las dos cosas. Una plantilla guardada aquí no
  /// viaja con ningún material y **no la protege nadie**: ver [TemplateStore].
  static const String programTemplates = '@programa';

  /// Dónde se puede guardar una plantilla: los repositorios en los que se
  /// puede escribir, y la carpeta del programa si la hay.
  List<String> get templateHomes => [
    for (final repo in session.openedWorkspace.repos)
      if (session.canWriteIn(repo.id)) repo.id,
    if (session.templateStore != null) programTemplates,
  ];

  /// Cómo se llama cada uno de esos sitios, para una lista.
  String templateHomeLabel(String home) => home == programTemplates
      ? tr('En el programa (sin copia de seguridad)')
      : (session.workspace.byId(home)?.label ?? home);

  /// Leer un fichero de plantillas, venga de donde venga.
  Future<String> _readTemplateFile(String home, String path) async {
    if (home == programTemplates) {
      final store = session.templateStore;
      if (store == null) throw ArgumentError(tr('no hay carpeta del programa'));
      return store.read(path);
    }
    try {
      final file = await session.gatewayFor(home).read(path);
      return file.text;
    } on ContentException catch (error) {
      if (error.kind == ContentFailure.missing) return '';
      rethrow;
    }
  }

  /// Escribirlo. En un repositorio es un commit; en la carpeta del programa,
  /// un fichero y nada más -- ahí no hay historial que consultar, y por eso
  /// la pantalla insiste en las copias.
  Future<void> _writeTemplateFile(
    String home,
    String path,
    String text,
    String message,
  ) async {
    if (home == programTemplates) {
      final store = session.templateStore;
      if (store == null) throw ArgumentError(tr('no hay carpeta del programa'));
      await store.write(path, text);
      return;
    }
    final gateway = session.gatewayFor(home);
    if (!gateway.canWrite) {
      throw ArgumentError(tr('no se puede escribir en {0}', [home]));
    }
    var sha = '';
    try {
      final file = await gateway.read(path);
      if (file.text == text) return;
      sha = file.sha;
    } on ContentException catch (error) {
      if (error.kind != ContentFailure.missing) rethrow;
    }
    await gateway.save(path: path, text: text, sha: sha, message: message);
  }

  /// Volver a mirar después de escribir plantillas.
  Future<void> _afterTemplates(String home) async {
    if (home == programTemplates) {
      await session.loadStoredTemplates();
      return;
    }
    await _reindexAfterTaxonomy(home);
  }

  /// Declara una plantilla en un repositorio.
  ///
  /// Uno basta para usarla en todos: los demás repositorios la nombran sin
  /// declararla, que es lo que permite que el bloque de teoría se compile con
  /// una plantilla del de problemas. Tenerla **también** en otro --para que
  /// viaje con ese material, o para que no dependa de tener el primero
  /// abierto-- es [addTemplateTo], que la copia tal como está.
  Future<void> declareTemplate({
    required String repo,
    required String id,
    required Map<String, String> titles,
    required String documentClass,
    String classOptions = '',
    Map<String, String> axes = const {},
    String preamble = '',
    bool active = true,
  }) async {
    const where = 'templates.yaml';
    final current = await _readTemplateFile(repo, where);
    final catalogue = session.catalogueOrNull;
    final languages = catalogue?.languagesOf(repo) ?? const <String>['es'];
    final templates = TemplatesFile(
      current.isEmpty ? emptyTemplatesYaml : current,
    );
    // La primera que se declara, con las de serie. En cuanto hay alguna
    // declarada valen solo las declaradas --es lo que deja elegir cuáles se
    // ofrecen--, así que escribir solo la nueva dejaba sin compilar todo lo
    // que usaba las de serie, sin decir nada. Se escriben también, tal como
    // son, y la que no se quiera se apaga.
    void addNew() => templates.add(
      id: id,
      titles: titles,
      documentClass: documentClass,
      classOptions: classOptions,
      axes: axes,
      languages: languages,
    );
    final first = catalogue != null && catalogue.templates.isEmpty;
    if (first) {
      for (final profile in catalogue.profiles) {
        // La que se está editando, en su sitio: el orden es el que se
        // ofrece.
        if (profile.id == id) {
          addNew();
          continue;
        }
        if (templates.ids.contains(profile.id)) continue;
        templates.add(
          id: profile.id,
          titles: {
            if (profile.label.isNotEmpty) 'es': profile.label,
            ...profile.labels,
          },
          documentClass: profile.documentClass,
          classOptions: profile.classOptions,
          axes: profile.axes,
          languages: languages,
        );
      }
    }
    if (!templates.ids.contains(id)) addNew();
    if (!active) templates.setActive(id, false);

    await _writeTemplateFile(
      repo,
      where,
      templates.text,
      first && catalogue.profiles.isNotEmpty
          ? tr('Declarar la plantilla {0}, con las de serie', [id])
          : tr('Declarar la plantilla {0}', [id]),
    );
    // El preámbulo va aparte y solo si lo hay: una plantilla sin cabecera
    // propia se comporta exactamente como la salida de serie, que es el punto
    // de partida razonable.
    if (preamble.trim().isNotEmpty) {
      await setTemplatePreamble(repo: repo, id: id, text: preamble);
    }
    await _afterTemplates(repo);
  }

  /// Declara también en [repo] una plantilla que ya está en otro sitio.
  ///
  /// Copiada entera --nombre, clase, ejes, si está encendida y su cabecera--
  /// para que los dos digan lo mismo desde el primer día. A partir de ahí
  /// cada edición se escribe en todos los que la declaran, y si alguna vez
  /// discrepan lo dice «Entre repositorios».
  ///
  /// Con una de las que trae Didacta es lo mismo que editarla aquí: se
  /// escribe con su id y desde entonces manda la del repositorio.
  Future<void> addTemplateTo({required String repo, required String id}) async {
    final template = session.catalogueOrNull?.templateNamed(id);
    if (template == null) {
      throw ArgumentError(tr('no hay ninguna plantilla {0}', [id]));
    }
    if (template.sources.containsKey(repo)) return;

    // La cabecera del primero que la tenga: es un fichero aparte, y sin ella
    // la copia compilaría distinto que el original.
    var preamble = '';
    if (template.hasPreamble) {
      for (final from in template.sources.keys) {
        preamble = await templatePreamble(repo: from, id: id);
        if (preamble.trim().isNotEmpty) break;
      }
    }
    await declareTemplate(
      repo: repo,
      id: id,
      titles: template.titles,
      documentClass: template.documentClass,
      classOptions: template.classOptions,
      axes: template.axes,
      preamble: preamble,
      active: template.active,
    );
  }

  /// Deja de declarar una plantilla en [repo], y solo ahí.
  ///
  /// Los demás que la declaran siguen igual, así que lo que la nombra se
  /// sigue compilando. Su cabecera se queda en el repositorio, por lo mismo
  /// que en [removeTemplate].
  Future<void> removeTemplateFrom({
    required String repo,
    required String id,
  }) async {
    const where = 'templates.yaml';
    final current = await _readTemplateFile(repo, where);
    if (current.isEmpty) return;
    final templates = TemplatesFile(current);
    if (!templates.ids.contains(id)) return;
    templates.remove(id);
    await _writeTemplateFile(
      repo,
      where,
      templates.text,
      tr('Quitar la plantilla {0}', [id]),
    );
    await _afterTemplates(repo);
  }

  /// Compila [unit] con una plantilla tal como está en la pantalla, sin
  /// guardarla.
  ///
  /// Con su mismo id, así que si ya existe se ve la versión editada y no la
  /// guardada. En el repositorio de la lección, que es donde el motor la
  /// encuentra. Null si aquí no se puede compilar: en la web, o sin motor.
  Future<SnippetPreview?> previewTemplate({
    required Unit unit,
    required String id,
    required String documentClass,
    String classOptions = '',
    Map<String, String> axes = const {},
    String preamble = '',
    void Function(String line)? onOutput,
  }) async {
    final compiler = session.liveCompiler(repo: unit.repo);
    if (compiler == null) return null;
    final language = unit.statuses.containsKey(session.language)
        ? session.language
        : null;
    final out = await compiler.run(
      [
        'template-preview',
        unit.path,
        if (id.trim().isNotEmpty) ...['--id', id.trim()],
        '--class',
        documentClass,
        if (classOptions.trim().isNotEmpty) ...['--options', classOptions],
        for (final entry in axes.entries) ...[
          '--axis',
          '${entry.key}=${entry.value}',
        ],
        if (preamble.trim().isNotEmpty) ...['--preamble-text', preamble],
        if (language != null) ...['-l', language],
        '--json',
      ],
      allowFailure: true,
      onOutput: onOutput,
    );
    try {
      return SnippetPreview.fromJson(
        (jsonDecode(out) as Map).cast<String, dynamic>(),
      );
    } on FormatException {
      return SnippetPreview(
        ok: false,
        engineFailed: true,
        errors: [
          out.trim().isEmpty ? tr('El motor no ha contestado.') : out.trim(),
        ],
      );
    }
  }

  /// Cambia el nombre de una plantilla, en todos los idiomas a la vez.
  Future<int> setTemplateTitles({
    required String id,
    required Map<String, String> titles,
  }) => _writeTemplate(
    id: id,
    message: tr('Nombre de la plantilla {0}', [id]),
    edit: (file) => file.setTitles(id, titles),
  );

  /// Enciende o apaga una plantilla.
  ///
  /// Apagada queda declarada y fuera de lo que se compila. No se borra: lo
  /// que se quiere guardar de una versión que este curso no se da es
  /// justamente su preámbulo.
  Future<int> setTemplateActive({required String id, required bool active}) =>
      _writeTemplate(
        id: id,
        message: active
            ? tr('Encender la plantilla {0}', [id])
            : tr('Apagar la plantilla {0}', [id]),
        edit: (file) => file.setActive(id, active),
      );

  /// Cambia qué produce una plantilla: la clase, sus opciones y los ejes.
  Future<int> setTemplateShape({
    required String id,
    required String documentClass,
    required String classOptions,
    required Map<String, String> axes,
  }) => _writeTemplate(
    id: id,
    message: tr('Salida de la plantilla {0}', [id]),
    edit: (file) {
      file.setField(id, 'class', documentClass.trim());
      file.setField(
        id,
        'options',
        classOptions.trim().isEmpty ? null : classOptions.trim(),
      );
      file.setAxes(id, axes);
    },
  );

  /// Quita una plantilla de los repositorios que la declaran.
  ///
  /// El `templates/<id>.tex` se queda donde está, y eso es deliberado: es
  /// LaTeX que alguien escribió, y borrarlo de paso al quitar una línea de
  /// una lista sería la clase de ayuda que nadie pidió. Volver a declararla
  /// con el mismo id lo recupera entero.
  Future<int> removeTemplate({required String id}) => _writeTemplate(
    id: id,
    message: tr('Quitar la plantilla {0}', [id]),
    edit: (file) => file.remove(id),
  );

  /// Escribe en el `templates.yaml` de cada repositorio que declare [id].
  Future<int> _writeTemplate({
    required String id,
    required String message,
    required void Function(TemplatesFile file) edit,
  }) async {
    final template = session.catalogueOrNull?.templates
        .where((entry) => entry.id == id)
        .firstOrNull;
    if (template == null) {
      throw ArgumentError(tr('no se declara la plantilla {0}', [id]));
    }

    const where = 'templates.yaml';
    final written = <String>[];
    for (final repo in template.sources.keys) {
      if (repo != programTemplates && !session.gatewayFor(repo).canWrite) {
        continue;
      }

      final current = await _readTemplateFile(repo, where);
      if (current.isEmpty) continue;
      final templates = TemplatesFile(current);
      edit(templates);
      if (templates.text == current) continue;

      await _writeTemplateFile(repo, where, templates.text, message);
      written.add(repo);
    }
    for (final repo in written) {
      if (repo == programTemplates) continue;
      await _reindexAfterTaxonomy(repo, reload: false);
    }
    if (written.isNotEmpty) {
      await session.reloadCatalogue();
      if (written.contains(programTemplates)) {
        await session.loadStoredTemplates();
      }
    }
    return written.length;
  }

  /// El preámbulo de una plantilla, tal como está escrito.
  ///
  /// Cadena vacía cuando no tiene: una plantilla sin cabecera propia no es un
  /// error, es la que se comporta como la salida de serie.
  Future<String> templatePreamble({required String repo, required String id}) =>
      _readTemplateFile(repo, 'templates/$id.tex');

  /// Escribe el preámbulo de una plantilla en todos los sitios que la
  /// declaran y se pueden escribir.
  ///
  /// Como el nombre o los ejes: la misma plantilla en dos repositorios con
  /// dos cabeceras es dos PDF distintos con el mismo nombre. Devuelve en
  /// cuántos se escribió.
  Future<int> setTemplatePreambleEverywhere({
    required String id,
    required String text,
  }) async {
    final template = session.catalogueOrNull?.templateNamed(id);
    var written = 0;
    for (final repo in template?.sources.keys ?? const <String>[]) {
      if (repo != programTemplates && !session.canWriteIn(repo)) continue;
      await setTemplatePreamble(repo: repo, id: id, text: text);
      written += 1;
    }
    return written;
  }

  /// Escribe el preámbulo de una plantilla.
  ///
  /// Vacío borra el fichero de hecho --se deja en blanco-- en lugar de
  /// quitarlo: un fichero que desaparece y vuelve en cada edición llena el
  /// historial de ruido, y uno vacío es exactamente lo que dice.
  Future<void> setTemplatePreamble({
    required String repo,
    required String id,
    required String text,
  }) async {
    await _writeTemplateFile(
      repo,
      'templates/$id.tex',
      text,
      tr('Cabecera de la plantilla {0}', [id]),
    );
    // Sin reindexar: el preámbulo no sale en el índice --lo lee LaTeX al
    // compilar-- así que regenerarlo costaría tres segundos para no cambiar
    // una línea de lo que la pantalla enseña.
    await session.reloadCatalogue();
  }

  /// Con qué plantillas se compila una lección.
  ///
  /// Lista vacía la devuelve a lo que diga su bloque, que es el estado
  /// normal: elegir aquí es apartarse, y hay que poder dejar de apartarse.
  Future<void> setUnitTemplates({
    required String repo,
    required String path,
    required List<String> templates,
  }) async {
    final where = '$path/unit.yaml';
    final gateway = session.gatewayFor(repo);
    final file = await gateway.read(where);
    final patch = YamlPatch(file.text);
    if (templates.isEmpty) {
      patch.remove(const ['templates']);
    } else {
      patch.setFlowList(const ['templates'], templates);
    }
    if (patch.result == file.text) return;

    await gateway.save(
      path: where,
      text: patch.result,
      sha: file.sha,
      message: templates.isEmpty
          ? tr('Plantillas de {0}: las del bloque', [path])
          : tr('Plantillas de {0}', [path]),
    );
    await session.reloadCatalogue();
  }

  /// Con qué plantillas se compila un documento.
  ///
  /// En su `year.yaml`, que es donde vive el documento. Lista vacía lo
  /// devuelve a lo que digan los bloques de las lecciones que compone.
  Future<void> setDocumentTemplates({
    required String repo,
    required String course,
    required String year,
    required String id,
    required List<String> templates,
  }) async {
    final where = 'courses/$course/$year/year.yaml';
    final gateway = session.gatewayFor(repo);
    final file = await gateway.read(where);
    final composition = CompositionFile(file.text)
      ..setDocumentTemplates(id, templates);
    if (composition.text == file.text) return;

    await gateway.save(
      path: where,
      text: composition.text,
      sha: file.sha,
      message: templates.isEmpty
          ? tr('Plantillas de {0}: las de sus bloques', [id])
          : tr('Plantillas de {0} en {1} {2}', [id, course, year]),
    );
    await session.reloadCatalogue();
  }

  /// Regenerar el índice después de tocar `taxonomy.yaml`.
  ///
  /// Hace falta y no basta con releer: los bloques declarados salen en el
  /// **manifiesto**, no en los ficheros de unidades, así que hasta que el
  /// motor no lo vuelve a escribir la aplicación sigue leyendo los de antes
  /// -- y quien acaba de crear un bloque no lo vería hasta reiniciar.
  ///
  /// A la fuerza, porque la comprobación de si el índice está viejo mira
  /// fechas y recuentos, y aquí ya sabemos que lo está.
  Future<void> _reindexAfterTaxonomy(String repo, {bool reload = true}) async {
    await session.refreshIndex(force: true, only: repo);
    if (reload) await session.reloadCatalogue();
  }

  /// Cambia el estado declarado de una unidad en un idioma.
  ///
  /// Es lo que cierra el ciclo de traducir: una máquina deja un borrador, una
  /// persona lo lee, y aquí dice que ya está. Sin esto el borrador se queda
  /// en la lista para siempre y la lista deja de significar nada.
  ///
  /// Solo los declarables. «No existe» y «desactualizada» los calcula el
  /// motor --el primero de que el fichero esté, el segundo comparando con el
  /// original-- y escribirlos garantizaría que se queden obsoletos: bastaría
  /// con volver a tocar el original.
  /// Enciende o apaga la sangría automática de un idioma de una unidad.
  ///
  /// Se guarda en el `unit.yaml`, al lado del estado, porque es una propiedad
  /// del fichero y no de quien lo edita: si una tabla alineada a mano hay que
  /// dejarla quieta, hay que dejarla quieta también cuando la abra otra
  /// persona en otro ordenador.
  ///
  /// Por idioma. La versión castellana de una unidad puede ser un bloque
  /// generado por otra herramienta que no conviene tocar mientras la inglesa
  /// se escribe a mano y agradece la sangría.
  /// El `.tex` con la sangría puesta, antes de escribirlo.
  ///
  /// Un método y no una llamada suelta a [beautifyLatex] porque **qué
  /// indentador hay** es cosa del entorno: en escritorio se busca
  /// `latexindent` en el disco, y una prueba de widgets con el reloj falso no
  /// puede esperar a un proceso de verdad. Sobrescribiéndolo, una prueba usa
  /// el indentador propio, que es Dart puro y contesta en el acto.
  Future<String> tidyLatex(String text) =>
      beautifyLatex(text, texPath: session.texPath);

  Future<void> setUnitIndent({
    required Unit unit,
    required String language,
    required bool on,
  }) async {
    final gateway = session.gatewayFor(unit.repo);
    if (!gateway.canWrite) {
      throw ArgumentError(tr('no se puede escribir en {0}', [unit.repo]));
    }

    final where = '${unit.path}/unit.yaml';
    String text;
    var sha = '';
    try {
      final file = await gateway.read(where);
      text = file.text;
      sha = file.sha;
    } on ContentException catch (error) {
      if (error.kind != ContentFailure.missing) rethrow;
      text = '# Metadatos de la unidad.\nlanguages:\n';
    }

    // Se escribe también el `true`, aunque sea el valor por defecto: quien
    // apagó esto y volvió a encenderlo quiere ver en el fichero que está
    // encendido a propósito, y el motor lee las dos cosas igual.
    final patch = YamlPatch(text)
      ..setFlagInFlowMap(['languages', language], 'indent', on);
    if (patch.result == text) return;

    await gateway.save(
      path: where,
      text: patch.result,
      sha: sha,
      message: tr(
        '{0} la sangría de {1} en '
        '«{2}»',
        [
          on ? tr('Activar') : tr('Desactivar'),
          language,
          unit.title(unit.reference),
        ],
      ),
    );
    await session.reloadCatalogue();
  }

  Future<void> setUnitStatus({
    required Unit unit,
    required String language,
    required String status,
  }) async {
    if (!declarableStatuses.contains(status)) {
      throw ArgumentError(
        tr('el estado «{0}» lo calcula el motor; no se puede declarar', [
          status,
        ]),
      );
    }
    final gateway = session.gatewayFor(unit.repo);
    if (!gateway.canWrite) {
      throw ArgumentError(tr('no se puede escribir en {0}', [unit.repo]));
    }

    // Con la huella del original de ahora, si es una traducción: marcarla
    // es decir «está al día con esto», y es lo que deja al motor saber que
    // se queda atrás cuando el original cambie.
    final patched = await _withStatus(
      gateway,
      unit,
      language,
      status,
      sourceHash: language == unit.reference
          ? null
          : await _referenceHash(gateway, unit),
    );
    if (patched == null) return;

    await gateway.save(
      path: patched.path,
      text: patched.text,
      sha: patched.sha,
      message: tr(
        'Marcar {0} de «{1}» '
        'como {2}',
        [
          language,
          unit.title(unit.reference),
          statusName(TranslationStatus.parse(status)),
        ],
      ),
    );
    await session.reloadCatalogue();
  }

  /// Da por revisada una traducción, con lo que se haya corregido, en **un**
  /// cambio.
  ///
  /// Revisar era dos: guardar lo corregido y después marcarla, cada uno con
  /// su commit --y entre los dos, el historial decía que la corrección era
  /// de una traducción sin revisar--. Aquí [text], si lo hay, y el estado con
  /// la huella del original de ahora van juntos. [sha] es el que tenía el
  /// fichero al abrirlo: si ha cambiado en el disco, no se escribe nada.
  ///
  /// Devuelve el `.tex` tal como quedó, para que el editor lo tenga.
  Future<ContentFile?> approveTranslation({
    required Unit unit,
    required String language,
    String? text,
    String sha = '',
  }) async {
    if (language == unit.reference) {
      throw ArgumentError(
        tr('el original no se revisa: es de donde se traduce'),
      );
    }
    final gateway = session.gatewayFor(unit.repo);
    if (!gateway.canWrite) {
      throw ArgumentError(tr('no se puede escribir en {0}', [unit.repo]));
    }
    final status = await _withStatus(
      gateway,
      unit,
      language,
      'reviewed',
      sourceHash: await _referenceHash(gateway, unit),
    );
    final files = [
      if (text != null) (path: unit.fileFor(language), text: text, sha: sha),
      ?status,
    ];
    if (files.isEmpty) return null;
    await gateway.saveAll(
      files: files,
      message: text == null
          ? tr('Revisar {0} de «{1}»', [language, unit.title(unit.reference)])
          : tr('Corregir y revisar {0} de «{1}»', [
              language,
              unit.title(unit.reference),
            ]),
    );
    ContentFile? written;
    try {
      written = await gateway.read(unit.fileFor(language));
    } catch (caught, trace) {
      Diagnostics.instance.note('session.approveTranslation', caught, trace);
      // Guardado está; lo que no se ha podido es releerlo.
    }
    // Y la memoria aprende de lo corregido: la frase arreglada al revisar
    // sale arreglada la próxima vez, en cualquier lección. Aparte, como
    // siempre la memoria, y sin que un fallo deshaga la revisión.
    if (text != null) {
      try {
        final original = (await gateway.read(
          unit.fileFor(unit.reference),
        )).text;
        final lessons = learnFromReview(
          original,
          text,
          unit: unit.path,
          by: session.auth.user?.login ?? '',
          when: DateTime.now(),
        );
        if (lessons.isNotEmpty) {
          await session.translations.remember(
            repo: unit.repo,
            from: unit.reference,
            to: language,
            learned: lessons,
            memory: await session.translationMemory(
              from: unit.reference,
              to: language,
            ),
          );
        }
      } catch (caught, trace) {
        Diagnostics.instance.note('session.approveTranslation', caught, trace);
        // Aprender es un extra: la revisión ya está guardada.
      }
    }
    await session.reloadCatalogue();
    return written;
  }

  /// El original tal como estaba cuando se tradujo o se revisó [language], y
  /// el commit que lo tenía así. Null si no se sabe.
  ///
  /// Una traducción desactualizada dice que el original ha cambiado, y lo
  /// que hace falta para ponerla al día es **qué** ha cambiado: una coma o un
  /// teorema nuevo. La huella que se guardó al revisar dice cuál era el
  /// original entonces; aquí se busca en su historial la versión con esa
  /// huella. No se sabe si no hay huella --lo traducido antes de que
  /// existieran--, si no hay clon --la web-- o si esa versión no llegó a
  /// guardarse en el historial.
  Future<({String text, FileCommit commit})?> originalAtReview(
    Unit unit,
    String language, {
    int depth = 200,
  }) async {
    final clone = session.cloneFor(unit.repo);
    if (clone == null) return null;
    String? hash;
    try {
      final yaml =
          (await session.gatewayFor(unit.repo).read('${unit.path}/unit.yaml'))
              .text;
      hash = declaredSourceHash(yaml, language);
    } catch (caught, trace) {
      Diagnostics.instance.note('session.originalAtReview', caught, trace);
      return null;
    }
    if (hash == null) return null;
    final path = unit.fileFor(unit.reference);
    try {
      for (final commit in await clone.history(path, limit: depth)) {
        final text = await clone.fileAt(sha: commit.sha, path: path);
        if (text != null && contentHash(text) == hash) {
          return (text: text, commit: commit);
        }
      }
    } catch (caught, trace) {
      Diagnostics.instance.note('session.originalAtReview', caught, trace);
      // Sin historial que leer, no se sabe.
    }
    return null;
  }

  /// La siguiente traducción sin revisar en [language], después de [after],
  /// en el orden de la lista de Traducción. Null si no queda ninguna.
  ///
  /// Solo donde se puede escribir: llevar a alguien a una que no puede
  /// aprobar es mandarle a leer para nada.
  Unit? nextToReview(String language, {String? after}) {
    final pending = [
      for (final unit in session.needingTranslation(language))
        if (unit.statusIn(language) == TranslationStatus.draft &&
            unit.reference != language &&
            session.canWriteIn(unit.repo))
          unit,
    ];
    if (pending.isEmpty) return null;
    final at = after == null
        ? -1
        : pending.indexWhere((unit) => unit.path == after);
    if (at < 0) {
      return pending.firstWhere(
        (unit) => unit.path != after,
        orElse: () => pending.first,
      );
    }
    final rest = [...pending.skip(at + 1), ...pending.take(at)];
    return rest.isEmpty ? null : rest.first;
  }

  /// La huella del original de [unit] tal como está, o null si no se puede
  /// leer. Ver `model/source_hash.dart`.
  Future<String?> _referenceHash(ContentGateway gateway, Unit unit) async {
    try {
      return contentHash(
        (await gateway.read(unit.fileFor(unit.reference))).text,
      );
    } catch (caught, trace) {
      Diagnostics.instance.note('session._referenceHash', caught, trace);
      return null;
    }
  }

  /// El `unit.yaml` de [unit] con el estado de [language] puesto a
  /// [status], listo para guardar. Null si ya lo tenía.
  ///
  /// Con [sourceHash], también la huella del original contra la que se
  /// tradujo o se revisó: la que deja al motor decir «desactualizada».
  Future<({String path, String text, String sha})?> _withStatus(
    ContentGateway gateway,
    Unit unit,
    String language,
    String status, {
    String? sourceHash,
  }) async {
    final where = '${unit.path}/unit.yaml';
    String text;
    var sha = '';
    try {
      final file = await gateway.read(where);
      text = file.text;
      sha = file.sha;
    } on ContentException catch (error) {
      if (error.kind != ContentFailure.missing) rethrow;
      // Una unidad migrada puede no tener metadatos todavía. Se crean con lo
      // único que se está diciendo; lo demás sigue deduciéndose del disco.
      text = '# Metadatos de la unidad.\nlanguages:\n';
    }

    final patch = YamlPatch(text)
      ..setInFlowMap(['languages', language], 'status', status);
    if (sourceHash != null) {
      patch.setInFlowMap(['languages', language], 'source_hash', sourceHash);
    }
    if (patch.result == text) return null;
    return (path: where, text: patch.result, sha: sha);
  }
}
