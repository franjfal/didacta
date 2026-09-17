/// El material con el que se pintan las capturas de la documentación.
///
/// Existe porque las capturas salían **con cuatro unidades**. El fixture de
/// los tests es el correcto para lo que hace --datos incómodos a propósito: una
/// traducción que falta, una referencia rota, un problema con un aviso-- y para
/// un test cuatro unidades bastan. Para una captura no: una biblioteca con
/// cuatro filas y el resto en blanco enseña una aplicación vacía, y quien la
/// mira concluye lo que parece.
///
/// Así que esto monta un repositorio **con el tamaño de uno de verdad**: seis
/// materias, cuarenta y tantas unidades, tres asignaturas con sus cursos y sus
/// temas, y los idiomas en todos los estados. La escala es la del material real
/// del que salió Didacta --2147 unidades en 51 categorías--, sólo que en
/// pequeño: lo justo para que una lista se vea como una lista.
///
/// **Los casos incómodos se conservan**, y eso no es un descuido: una
/// referencia rota, una traducción desactualizada y una unidad que no usa
/// nadie salen en las capturas porque salen en la pantalla de cualquiera, y una
/// documentación que sólo enseña el día bueno no prepara para el día malo.
library;

import 'package:didacta_app/model/catalogue.dart';

import '../test/fixture.dart';

/// Una materia: su nombre en la taxonomía y sus temas.
class _Area {
  const _Area(this.category, this.topics);

  final String category;
  final Map<String, List<String>> topics;
}

/// Lo que hay escrito, por materia y tema.
///
/// Títulos de verdad y no `Unidad 1`: en una captura, un listado de títulos
/// genéricos se lee como una maqueta, que es justo lo que no es.
const List<_Area> _areas = [
  _Area('analysis', {
    'normed': [
      'Espacios normados',
      'La norma del supremo',
      'Espacios de Banach',
      'Aplicaciones lineales continuas',
      'El teorema de Hahn-Banach',
    ],
    'series': [
      'Series numéricas',
      'Criterio de comparación',
      'Criterio integral',
      'Convergencia absoluta',
    ],
    'sequences': [
      'Sucesiones de funciones',
      'Convergencia puntual',
      'Convergencia uniforme',
      'El criterio de Weierstrass',
    ],
    'measure': [
      'Medida exterior',
      'Conjuntos medibles',
      'La integral de Lebesgue',
    ],
  }),
  _Area('algebra', {
    'matrices': [
      'Matrices y operaciones',
      'Rango de una matriz',
      'Determinantes',
      'Matriz inversa',
    ],
    'vector-spaces': [
      'Espacios vectoriales',
      'Bases y dimensión',
      'Subespacios',
    ],
    'diagonalization': [
      'Valores propios',
      'Diagonalización',
      'El teorema espectral',
    ],
  }),
  _Area('topology', {
    'metric': ['Espacios métricos', 'Bolas y entornos', 'Sucesiones de Cauchy'],
    'compactness': ['Compacidad', 'El teorema de Heine-Borel'],
    'connectedness': ['Conexión', 'Componentes conexas'],
  }),
  _Area('probability', {
    'variables': [
      'Variables aleatorias',
      'Función de distribución',
      'Esperanza y varianza',
    ],
    'limits': [
      'La ley de los grandes números',
      'El teorema central del límite',
    ],
  }),
  _Area('geometry', {
    'conics': ['Cónicas', 'Clasificación de cónicas'],
    'quadrics': ['Cuádricas'],
  }),
  _Area('numerical', {
    'roots': ['El método de Newton', 'Bisección'],
    'integration': ['Fórmulas de cuadratura', 'La regla de Simpson'],
  }),
];

/// Los problemas, que van en su propio árbol.
const Map<String, List<String>> _problems = {
  'analysis/normed': ['Ejercicios de normas', 'Problemas de Banach'],
  'analysis/series': ['Convergencia de series', 'Series de términos positivos'],
  'algebra/matrices': ['Cálculo de rangos', 'Sistemas lineales'],
  'algebra/diagonalization': ['Diagonalizar una matriz'],
  'topology/metric': ['Distancias y bolas'],
  'probability/variables': ['Variables discretas'],
};

/// El estado de los idiomas de una unidad, repartido de forma realista.
///
/// Ni todo traducido --que enseñaría una pantalla de traducción vacía-- ni
/// todo por traducir. Se decide por el índice, no al azar: una captura que
/// cambia cada vez que se genera no se puede comparar con la anterior.
Map<String, dynamic> _languages(int index) {
  const source = {'status': 'source', 'exists': true};
  const translated = {'status': 'translated', 'exists': true};
  const outdated = {'status': 'outdated', 'exists': true};
  const missing = {'status': 'missing', 'exists': false};
  return switch (index % 5) {
    0 => {'es': source, 'va': translated, 'en': translated},
    1 => {'es': source, 'va': translated, 'en': missing},
    2 => {'es': source, 'va': outdated, 'en': missing},
    3 => {'es': source, 'va': missing, 'en': missing},
    _ => {'es': source, 'va': translated, 'en': missing},
  };
}

/// Las unidades del repositorio de las capturas.
List<Map<String, dynamic>> screenshotUnits() {
  final units = <Map<String, dynamic>>[];
  var index = 0;

  for (final area in _areas) {
    for (final entry in area.topics.entries) {
      for (final title in entry.value) {
        final slug = _slug(title);
        units.add(
          unitJson(
            path: 'content/${area.category}/${entry.key}/$slug',
            category: area.category,
            topic: entry.key,
            title: {'es': title},
            languages: _languages(index),
            tags: _tagsFor(area.category),
            // Una de cada cuatro no la usa nadie: es lo que pasa de verdad
            // --material que existe y este año no se da-- y es media pantalla
            // de la biblioteca.
            usedBy: index % 4 == 3
                ? const <Map<String, String>>[]
                : [
                    {
                      'course': index.isEven ? 'am-iii' : 'al-i',
                      'year': '2025-2026',
                      'document': 'tema-${(index % 4) + 1}',
                    },
                  ],
          ),
        );
        index += 1;
      }
    }
  }

  for (final entry in _problems.entries) {
    for (final title in entry.value) {
      final parts = entry.key.split('/');
      units.add(
        unitJson(
          path: 'problems/${entry.key}/${_slug(title)}',
          area: 'problems',
          kind: 'problem',
          category: parts.first,
          topic: parts.last,
          title: {'es': title},
          languages: _languages(index),
          tags: const ['ejercicios'],
          usedBy: [
            {'course': 'am-iii', 'year': '2025-2026', 'document': 'hoja-1'},
          ],
          // Un aviso del motor, que es algo que la pantalla enseña y que hay
          // que ver en la documentación antes que en el propio repositorio.
          warnings: index % 7 == 0
              ? const ['La figura `norma.pdf` no se encontró']
              : const <String>[],
        ),
      );
      index += 1;
    }
  }

  // Y las del fixture, que traen los casos incómodos con los que se prueba
  // todo lo demás: la unidad sin título en castellano y la referencia rota que
  // la composición enseña en rojo.
  units.addAll(defaultUnits());
  return units;
}

const Map<String, List<String>> _tags = {
  'analysis': ['norma', 'banach', 'convergencia'],
  'algebra': ['matrices', 'lineal'],
  'topology': ['métrica', 'compacidad'],
  'probability': ['distribución'],
  'geometry': ['cónicas'],
  'numerical': ['aproximación'],
};

List<String> _tagsFor(String category) => _tags[category] ?? const [];

String _slug(String title) => title
    .toLowerCase()
    .replaceAll(RegExp('[áà]'), 'a')
    .replaceAll(RegExp('[éè]'), 'e')
    .replaceAll(RegExp('[íì]'), 'i')
    .replaceAll(RegExp('[óò]'), 'o')
    .replaceAll(RegExp('[úù]'), 'u')
    .replaceAll('ñ', 'n')
    .replaceAll(RegExp('[^a-z0-9]+'), '-')
    .replaceAll(RegExp('^-|-\$'), '');

/// Las asignaturas, con sus cursos y sus temas.
List<Map<String, dynamic>> screenshotCourses() => [
  _course(
    id: 'am-iii',
    title: 'Análisis Matemático III',
    code: '34567',
    years: {
      '2025-2026': _year('analysis', const {
        'normed': 'Tema 1. Espacios normados',
        'series': 'Tema 2. Series',
        'sequences': 'Tema 3. Sucesiones de funciones',
        'measure': 'Tema 4. Medida e integración',
      }),
      '2024-2025': _year('analysis', const {
        'normed': 'Tema 1. Espacios normados',
        'series': 'Tema 2. Series',
      }),
    },
  ),
  _course(
    id: 'al-i',
    title: 'Álgebra Lineal I',
    code: '34120',
    years: {
      '2025-2026': _year('algebra', const {
        'matrices': 'Tema 1. Matrices',
        'vector-spaces': 'Tema 2. Espacios vectoriales',
        'diagonalization': 'Tema 3. Diagonalización',
      }),
    },
  ),
  _course(
    id: 'top',
    title: 'Topología',
    code: '34901',
    years: {
      '2025-2026': _year('topology', const {
        'metric': 'Tema 1. Espacios métricos',
        'compactness': 'Tema 2. Compacidad',
      }),
    },
  ),
];

Map<String, dynamic> _course({
  required String id,
  required String title,
  required String code,
  required Map<String, Map<String, dynamic>> years,
}) => {
  'id': id,
  'title': {'es': title},
  'language': 'es',
  'code': code,
  'teacher': 'Javier Falcó',
  'institution': 'Universitat de València',
  'years': years,
};

/// Un curso académico: un tema por cada tema de la taxonomía, y una hoja de
/// problemas.
Map<String, dynamic> _year(String category, Map<String, String> topics) {
  final documents = <Map<String, dynamic>>[];
  var number = 1;

  for (final entry in topics.entries) {
    final units = [
      for (final area in _areas)
        if (area.category == category)
          for (final title in area.topics[entry.key] ?? const <String>[])
            '$category/${entry.key}/${_slug(title)}',
    ];
    documents.add({
      'id': 'tema-$number',
      'kind': 'theory',
      'language': 'es',
      'title': {'es': entry.value},
      'profiles': const ['slides', 'slides-flat', 'notes', 'notes-teacher'],
      'unitRefs': units,
      'structure': [
        {
          'section': {'es': entry.value.split('. ').last},
        },
        for (final unit in units) {'unit': unit},
        // Una que no resuelve, en el primer tema: una composición que se salta
        // lo que falta parece completa y compila corta, y eso se ve aquí.
        if (number == 1) {'unit': '$category/${entry.key}/no-existe'},
      ],
    });
    number += 1;
  }

  documents.add({
    'id': 'hoja-1',
    'kind': 'problems',
    'language': 'es',
    'title': const {'es': 'Hoja 1. Problemas'},
    'profiles': const ['problems', 'problems-answers', 'problems-teacher'],
    'unitRefs': [
      for (final entry in _problems.entries)
        if (entry.key.startsWith(category))
          for (final title in entry.value)
            'problems/${entry.key}/${_slug(title)}',
    ],
    'structure': [
      for (final entry in _problems.entries)
        if (entry.key.startsWith(category))
          for (final title in entry.value)
            {'problem': '${entry.key}/${_slug(title)}'},
    ],
  });

  return {
    'year': topics.isEmpty ? '' : '',
    'language': 'es',
    'group': 'A',
    'documents': documents,
  };
}

/// El catálogo entero de las capturas.
Catalogue screenshotCatalogue() {
  final courses = screenshotCourses();
  // El año lo lleva cada entrada del mapa, así que se rellena aquí: escribirlo
  // dos veces es la forma de que un día no coincidan.
  for (final course in courses) {
    final years = course['years'] as Map<String, dynamic>;
    for (final entry in years.entries) {
      (entry.value as Map<String, dynamic>)['year'] = entry.key;
    }
  }
  return catalogueWith(screenshotUnits(), courses: courses);
}

/// Lo que el editor enseña al abrir una unidad.
///
/// Una unidad de verdad y no una línea: la captura del editor es la que dice
/// qué se escribe con Didacta, y con `El contenido original en castellano.`
/// dentro no dice nada.
const String sampleTex = r'''
\begin{frame}
\didactatitle{Espacios normados}

La métrica usual en $\mathbb{R}$ es $d(x,y) = |x-y|$, y casi todo lo que se
demuestra con ella usa sólo tres propiedades.

\onlynotes{%
  La idea de esta lección es quedarse con esas tres y olvidarse del resto:
  lo que queda sirve en cualquier espacio vectorial.
}

\begin{definition}[Norma]
Sea $E$ un espacio vectorial sobre $\mathbb{K}$. Una \emph{norma} es una
aplicación $\|\cdot\| : E \to \mathbb{R}$ tal que, para todo $x, y \in E$
y todo $\lambda \in \mathbb{K}$:
\begin{enumerate}
  \item $\|x\| \ge 0$, y $\|x\| = 0$ si y sólo si $x = 0$;
  \item $\|\lambda x\| = |\lambda|\, \|x\|$;
  \item $\|x + y\| \le \|x\| + \|y\|$.
\end{enumerate}
\end{definition}

\pause

\begin{example}
En $\mathbb{R}^n$, las tres normas de siempre:
\[
  \|x\|_1 = \sum_{i=1}^n |x_i|, \qquad
  \|x\|_2 = \sqrt{\sum_{i=1}^n x_i^2}, \qquad
  \|x\|_\infty = \max_i |x_i|.
\]
\end{example}

\begin{teaching}[Ritmo]
Quince minutos. Detente en la homogeneidad: es donde se atascan, porque el
valor absoluto de $\lambda$ parece que sobra hasta que alguien prueba con
$\lambda = -1$.
\end{teaching}
\end{frame}
''';

/// Y el `unit.yaml` que le corresponde.
const String sampleYaml = '''
# Espacios normados
#
# Migrated from:
#   00classnotes/901Analysis/01Handouts/01-normed/00CAST-definicion.tex

id: analysis.normed.espacios-normados
kind: theory

title:
  es: Espacios normados
  va: Espais normats

category: analysis
topic: normed
tags: [norma, banach]

reference: es

languages:
  es: {status: source}
  va: {status: translated}

prerequisites:
  - analysis/metric/espacios-metricos

objectives:
  - Reconocer una norma
  - Distinguir norma de métrica

duration_minutes: 15
difficulty: 2
''';
