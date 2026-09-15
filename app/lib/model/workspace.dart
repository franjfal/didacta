/// Los repositorios con los que se está trabajando.
///
/// El cambio que esto trae: Didacta deja de ser «un repositorio de contenido»
/// para ser **varios a la vez**. Un profesor tiene el suyo, comparte otro con
/// un departamento y da clase en una asignatura que se arma con los dos, así
/// que la biblioteca, las asignaturas y los años tienen que verse juntos
/// aunque vivan en carpetas distintas del disco.
///
/// Tres reglas que dan forma a todo lo demás:
///
/// **Un fichero es de un repositorio y de uno solo.** Un documento se compila
/// contra la raíz del suyo y referencia unidades suyas. Lo que se mezcla es la
/// asignatura: los temas de un año pueden venir de dos repositorios, y ahí sí
/// se juntan las listas.
///
/// **Quien no tenga uno de los repositorios ve el resto.** No hay nada que
/// falle por eso: lo que se carga es lo que hay, y lo que falta sencillamente
/// no aparece. Es lo que hace que compartir una asignatura no obligue a
/// compartir todo lo demás.
///
/// **Cada repositorio tiene un color.** Con dos abiertos, «¿esto dónde se está
/// guardando?» es la pregunta que más se hace, y contestarla con un color en
/// la fila es más barato que leer una ruta.
library;

import 'dart:convert';

/// Un repositorio de contenido, y dónde está su clon.
class ContentRepo {
  const ContentRepo({
    required this.owner,
    required this.name,
    required this.directory,
    this.branch = 'main',
    this.colour = 0,
  });

  factory ContentRepo.fromJson(Map<String, dynamic> json) => ContentRepo(
    owner: json['owner'] as String? ?? '',
    name: json['name'] as String? ?? '',
    directory: json['directory'] as String? ?? '',
    branch: json['branch'] as String? ?? 'main',
    colour: (json['colour'] as num?)?.toInt() ?? 0,
  );

  final String owner;
  final String name;

  /// El clon en este ordenador. Cada repositorio, su carpeta.
  final String directory;

  final String branch;

  /// El color con el que se marca en la interfaz, en ARGB.
  final int colour;

  /// `owner/name`, que es como lo nombra GitHub y como se identifica aquí.
  String get id => '$owner/$name';

  /// Lo que se lee en una etiqueta: el nombre basta, el dueño estorba.
  String get label => name;

  Map<String, dynamic> toJson() => {
    'owner': owner,
    'name': name,
    'directory': directory,
    'branch': branch,
    'colour': colour,
  };

  ContentRepo copyWith({String? directory, String? branch, int? colour}) =>
      ContentRepo(
        owner: owner,
        name: name,
        directory: directory ?? this.directory,
        branch: branch ?? this.branch,
        colour: colour ?? this.colour,
      );
}

/// De qué repositorio es un clon, leyendo su remoto.
///
/// `https://github.com/franjfal/didacta_db.git`, `git@github.com:x/y.git` y
/// `/ruta/a/x/y.git` dicen lo mismo de tres formas. Se saca `owner/name` de
/// las tres porque las tres existen en máquinas de verdad: una clonada por
/// HTTPS, otra por SSH y la de un test.
({String owner, String name})? repoFromRemote(String? url) {
  if (url == null) return null;
  var text = url.trim();
  if (text.isEmpty) return null;
  if (text.endsWith('/')) text = text.substring(0, text.length - 1);
  if (text.endsWith('.git')) text = text.substring(0, text.length - 4);
  // `git@github.com:owner/name` tiene los dos puntos donde una URL tendría
  // una barra.
  text = text.replaceFirst(RegExp(r'^[^/]*:(?!//)'), '');
  final parts = text.split('/')..removeWhere((each) => each.isEmpty);
  if (parts.isEmpty) return null;
  if (parts.length == 1) return (owner: '', name: parts.single);
  return (owner: parts[parts.length - 2], name: parts.last);
}

/// Los colores que se reparten a los repositorios.
///
/// Los de Didacta, no una paleta nueva: son los mismos que distinguen un
/// teorema de un ejemplo en el PDF, así que la aplicación sigue teniendo un
/// solo vocabulario de color.
const List<int> repoColours = [
  0xFF346E34, // accent
  0xFF2D5FA0, // thm
  0xFFBE8237, // ex
  0xFFAA4B4B, // teacher
  0xFF1E8C96, // ques
  0xFF8C5A96, // cor
  0xFF646EAF, // algo
  0xFF3C876E, // prop
];

/// Los repositorios abiertos, en orden.
class Workspace {
  const Workspace(this.repos);

  const Workspace.empty() : repos = const [];

  factory Workspace.fromJson(String source) {
    if (source.trim().isEmpty) return const Workspace.empty();
    final decoded = jsonDecode(source);
    if (decoded is! List) return const Workspace.empty();
    return Workspace([
      for (final item in decoded)
        if (item is Map) ContentRepo.fromJson(item.cast<String, dynamic>()),
    ]);
  }

  final List<ContentRepo> repos;

  bool get isEmpty => repos.isEmpty;
  bool get isNotEmpty => repos.isNotEmpty;

  /// Si hay más de uno, hay preguntas que hacer --dónde se crea un fichero--
  /// y colores que enseñar. Con uno solo, la aplicación se ve como siempre.
  bool get isMultiple => repos.length > 1;

  ContentRepo? byId(String id) {
    for (final repo in repos) {
      if (repo.id == id) return repo;
    }
    return null;
  }

  /// La carpeta del clon de un repositorio, o null si no está abierto.
  String? directoryOf(String id) => byId(id)?.directory;

  String toJson() => jsonEncode([for (final repo in repos) repo.toJson()]);

  Workspace with_(ContentRepo repo) {
    final rest = [
      for (final each in repos)
        if (each.id != repo.id) each,
    ];
    return Workspace([...rest, repo]);
  }

  Workspace without(String id) => Workspace([
    for (final repo in repos)
      if (repo.id != id) repo,
  ]);

  Workspace recoloured(String id, int colour) => Workspace([
    for (final repo in repos)
      if (repo.id == id) repo.copyWith(colour: colour) else repo,
  ]);

  /// El primer color que no esté cogido, para el que se añade ahora.
  ///
  /// Se reparten en orden y se reutiliza el primero cuando se acaban: dos
  /// repositorios del mismo color es peor que ninguno, pero solo pasa a
  /// partir de nueve abiertos a la vez.
  int nextColour() {
    final taken = {for (final repo in repos) repo.colour};
    for (final colour in repoColours) {
      if (!taken.contains(colour)) return colour;
    }
    return repoColours[repos.length % repoColours.length];
  }
}
