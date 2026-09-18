/// Lo que Didacta necesita tener instalado, y cómo se consigue en cada sistema.
///
/// Didacta no es un programa aislado: para traer el material llama a `git`,
/// para saber qué componer llama al motor --que es Python-- y para componerlo
/// llama a `latexmk`. Tres programas de terceros que la aplicación no lleva
/// dentro y que en una máquina recién estrenada no tienen por qué estar.
///
/// Lo que hacía antes era decirlo tarde y de uno en uno: se descubría que
/// faltaba LaTeX al pulsar compilar, y que faltaba git al intentar abrir el
/// primer repositorio. Cada fallo por separado, con su mensaje, en la pantalla
/// donde molestaba. Aquí está la lista entera y en un sitio, para poder
/// enseñarla completa **antes** de que nadie tropiece con ella.
///
/// Tres decisiones que explican la forma de este fichero:
///
/// **Es Dart puro.** Ni `dart:io` ni widgets: [Host] se pasa, no se pregunta.
/// Así la tabla de qué se instala dónde se prueba sin tener esa máquina
/// delante, que es la única forma de probar la rama de Windows desde un Mac.
///
/// **Cada herramienta lleva su plan y su plan B.** Un [InstallPlan] es lo que
/// Didacta puede intentar; [Tool.guide] y [InstallPlan.manualSteps] son lo que
/// queda cuando no se puede, que es la mitad de los casos reales --hace falta
/// la contraseña de administrador, no hay gestor de paquetes, la máquina es
/// de la universidad--. Un asistente que solo sabe el camino feliz deja tirado
/// justo a quien más lo necesita.
///
/// **LaTeX se elige, no se impone.** Las demás herramientas tienen una versión
/// buena y ya está; con TeX no: entre TinyTeX --100 MB-- y MacTeX --6 GB-- hay
/// una decisión real que depende del disco que tenga cada uno y de si va a
/// necesitar paquetes raros. Por eso [latexOptions] devuelve una lista y la
/// interfaz pregunta.
library;

/// Sobre qué sistema se está decidiendo.
///
/// Un enum y no `Platform.isMacOS` porque este fichero no importa `dart:io`:
/// quien construye la lista pasa el suyo, y un test pasa los tres.
enum Host {
  macos,
  windows,
  linux;

  String get name => switch (this) {
    Host.macos => 'macOS',
    Host.windows => 'Windows',
    Host.linux => 'Linux',
  };
}

/// Cuál de las herramientas.
enum ToolId {
  /// `git`: traer el material y guardar cada cambio.
  git,

  /// `python3`: lo que ejecuta el motor.
  python,

  /// `latexmk` y la distribución de TeX que lo trae.
  latex,

  /// El motor de Didacta, que es un clon de este repositorio.
  engine,
}

/// Una de las cosas que tienen que estar para que Didacta funcione entera.
class Tool {
  const Tool({
    required this.id,
    required this.name,
    required this.what,
    required this.executables,
    required this.guide,
    required this.missing,
    this.onlyToCompile = true,
    this.versionArguments = const ['--version'],
  });

  final ToolId id;

  /// Como se llama para quien lo lee: «Git», «Python 3».
  final String name;

  /// Para qué la usa Didacta, en una frase. Se enseña siempre, esté o no:
  /// una lista de requisitos sin el porqué de cada uno es una lista de
  /// obstáculos.
  final String what;

  /// Los nombres del ejecutable, en orden de preferencia.
  ///
  /// Varios porque Python no se llama igual en los tres sistemas: `python3`
  /// en Unix, y en Windows `python` o el lanzador `py`.
  final List<String> executables;

  /// Qué se le pregunta para que diga su versión.
  final List<String> versionArguments;

  /// La página oficial. Es el último recurso del modal: cuando nada de lo
  /// que Didacta sabe hacer funciona, lo honesto es mandar a la fuente.
  final String guide;

  /// Qué se pierde faltando ésta, dicho de ésta y no en general.
  ///
  /// Una frase por herramienta y no una compartida, porque lo que se pierde
  /// **es distinto** en cada caso: sin git no hay nada que abrir, y sin LaTeX
  /// se trabaja igual y solo falta el PDF. Una lista de cuatro avisos
  /// idénticos no dice cuál de los cuatro es el urgente.
  final String missing;

  /// Si faltando se puede seguir trabajando.
  ///
  /// Casi todas son `true`: sin LaTeX se escribe, se organiza y se traduce;
  /// lo único que no sale es el PDF. `git` es la excepción, y por eso se
  /// dice distinto: sin él no hay ni material que abrir.
  final bool onlyToCompile;
}

/// Las cuatro, en el orden en que hay que resolverlas.
///
/// El orden no es estético: el motor se descarga **con git**, así que una
/// lista que pusiera el motor antes ofrecería un botón que no puede funcionar
/// todavía.
const List<Tool> didactaTools = [
  Tool(
    id: ToolId.git,
    name: 'Git',
    what:
        'Trae el material de GitHub y guarda cada cambio con tu nombre. Es lo '
        'que hace que puedas ver cómo estaba un fichero el mes pasado.',
    executables: ['git'],
    guide: 'https://git-scm.com/downloads',
    missing:
        'No está, y sin git no hay nada que abrir: el material vive en '
        'repositorios y traerlos es lo que hace git.',
    onlyToCompile: false,
  ),
  Tool(
    id: ToolId.python,
    name: 'Python 3',
    what:
        'El motor de Didacta está escrito en Python. No hace falta saber '
        'Python ni instalar nada más: el motor no tiene dependencias.',
    executables: ['python3', 'python', 'py'],
    guide: 'https://www.python.org/downloads/',
    missing:
        'No está, así que el motor no puede arrancar y no habrá PDF. '
        'Escribir y organizar el material sigue funcionando.',
  ),
  Tool(
    id: ToolId.latex,
    name: 'LaTeX',
    what:
        'El que convierte el texto en un PDF con las fórmulas bien puestas. '
        'Didacta llama a `latexmk`, que viene en cualquier distribución de '
        'TeX.',
    executables: ['latexmk'],
    guide: 'https://tug.org/texlive/',
    missing:
        'No está. Se puede escribir, organizar y traducir igual; lo único '
        'que no saldrá es el PDF.',
  ),
  Tool(
    id: ToolId.engine,
    name: 'El motor de Didacta',
    what:
        'Lee tus repositorios y le dice a LaTeX qué componer: qué lecciones '
        'lleva cada documento, en qué orden y con qué plantilla.',
    executables: ['didacta'],
    guide: 'https://github.com/franjfal/didacta',
    missing:
        'No está. LaTeX solo no sabría por dónde empezar, así que tampoco '
        'habrá PDF. Lo descarga Didacta: son unos megas.',
  ),
];

Tool toolById(ToolId id) => didactaTools.firstWhere((tool) => tool.id == id);

/// De qué manera se instala algo.
///
/// La distinción que importa no es técnica: es **quién termina el trabajo**.
/// [own] y [command] los termina Didacta; [script] e [installer] los empieza
/// Didacta y los acaba otro programa --el instalador de Apple, el de MiKTeX--
/// en su propia ventana; [manual] no lo empieza nadie y solo quedan las
/// instrucciones. La interfaz dice una cosa distinta en cada caso, porque una
/// barra de progreso que se queda quieta esperando a una ventana que está
/// detrás es la peor forma de contarlo.
enum InstallKind {
  /// Lo hace Didacta con lo que ya sabe hacer. Solo el motor.
  own,

  /// Una orden que Didacta lanza y espera: `brew install git`.
  command,

  /// Un guion que se descarga y se ejecuta. TinyTeX es esto.
  script,

  /// Un instalador que se descarga y se abre. Sigue fuera de Didacta.
  installer,

  /// Aquí no se puede. Quedan las instrucciones.
  manual,
}

/// Un intento de instalación: qué se lanza, qué avisa y qué queda si falla.
class InstallPlan {
  const InstallPlan({
    required this.kind,
    required this.label,
    required this.explains,
    this.program,
    this.arguments = const [],
    this.url,
    this.filename,
    this.needs,
    this.handsOver = false,
    this.texPackages = false,
    this.manualSteps = const [],
  });

  /// El plan que no hace nada: solo instrucciones.
  const InstallPlan.manual({
    required this.label,
    required this.explains,
    this.manualSteps = const [],
  }) : kind = InstallKind.manual,
       program = null,
       arguments = const [],
       url = null,
       filename = null,
       needs = null,
       handsOver = false,
       texPackages = false;

  final InstallKind kind;

  /// Lo que pone el botón: «Instalar con Homebrew».
  final String label;

  /// Qué va a pasar al pulsarlo, en una frase. Se enseña **antes**, no
  /// después: descargar seis gigas o abrir una ventana que pide la
  /// contraseña de administrador son cosas que hay que saber antes de
  /// aceptar, no mientras ocurren.
  final String explains;

  /// El programa, cuando el plan es [InstallKind.command].
  final String? program;
  final List<String> arguments;

  /// De dónde se descarga, para [InstallKind.script] e [InstallKind.installer].
  ///
  /// Siempre `https` y siempre de la fuente oficial --CTAN, tinytex.yihui.org--
  /// y la interfaz la enseña entera antes de descargar nada. Que se vea de
  /// dónde viene un ejecutable que se va a lanzar no es un detalle.
  final String? url;

  /// Con qué nombre se guarda lo descargado. Importa en Windows, donde la
  /// extensión decide si algo se puede ejecutar.
  final String? filename;

  /// Qué programa hace falta para que este plan sea posible: `brew`, `winget`.
  ///
  /// Null cuando no depende de nada. Quien elige el plan prueba los
  /// candidatos en orden y se queda con el primero cuyo [needs] esté; así la
  /// máquina con Homebrew usa Homebrew y la que no, el instalador de Apple,
  /// sin preguntarle nada a nadie.
  final String? needs;

  /// Si al terminar la orden el trabajo sigue en otra ventana.
  ///
  /// `xcode-select --install` vuelve en un segundo y deja el instalador de
  /// Apple abierto; decir «instalado» ahí sería mentir.
  final bool handsOver;

  /// Si después hay que pedirle a `tlmgr` los paquetes que Didacta usa.
  ///
  /// Solo para las distribuciones mínimas que se instalan sin administrador
  /// --TinyTeX--: las grandes ya los traen, y en las que viven bajo `/usr`
  /// `tlmgr install` pediría la contraseña que precisamente estábamos
  /// evitando.
  final bool texPackages;

  /// Qué hacer a mano. Va en el modal cuando el plan falla, y **es el plan
  /// entero** cuando [kind] es [InstallKind.manual].
  final List<String> manualSteps;

  bool get automatic => kind != InstallKind.manual;
}

/// Los paquetes de CTAN que el preámbulo de Didacta pide.
///
/// Sale de los `\RequirePackage` de `latex/didacta*.sty` traducidos a nombres
/// de paquete de TeX Live; `tlmgr` resuelve las dependencias de cada uno, así
/// que esto son los de primer nivel y no el cierre completo.
///
/// Se usa **solo** después de instalar una distribución mínima. Que a alguno
/// le falle el nombre no rompe la instalación: se anota y se sigue, porque el
/// log de LaTeX dirá con nombre y apellido lo que falte el día que falte.
const List<String> didactaTexPackages = [
  'latexmk',
  'beamer',
  'pgf',
  'pgfplots',
  'tcolorbox',
  'mathtools',
  'amsmath',
  'amscls',
  'amsfonts',
  'jknapltx',
  'tools',
  'graphics',
  'booktabs',
  'multirow',
  'makecell',
  'caption',
  'csquotes',
  'enumitem',
  'environ',
  'etoolbox',
  'fancyhdr',
  'geometry',
  'titlesec',
  'wrapfig',
  'xcolor',
  'hyperref',
  'import',
  'sansmath',
  'cm-super',
  'lm',
  // Los diez idiomas de `latex/lang/`: babel carga el suyo por nombre, y sin
  // el fichero del idioma la compilación para en seco aunque el texto sea
  // correcto.
  'babel',
  'babel-spanish',
  'babel-catalan',
  'babel-english',
  'babel-german',
  'babel-basque',
  'babel-french',
  'babel-galician',
  'babel-italian',
  'babel-portuges',
];

// ------------------------------------------------- de dónde sale cada cosa ---

const String _tinytexUnix = 'https://yihui.org/tinytex/install-bin-unix.sh';
const String _tinytexWindows =
    'https://yihui.org/tinytex/install-bin-windows.bat';
const String _basicTex =
    'https://mirror.ctan.org/systems/mac/mactex/BasicTeX.pkg';
const String _macTex = 'https://mirror.ctan.org/systems/mac/mactex/MacTeX.pkg';
const String _texLiveWindows =
    'https://mirror.ctan.org/systems/texlive/tlnet/install-tl-windows.exe';

/// Los planes para una herramienta en un sistema, del mejor al peor.
///
/// Devuelve varios a propósito: quien instala prueba el primero cuyo
/// [InstallPlan.needs] esté en la máquina. El último de la lista es siempre
/// uno que no depende de nada --manual, si hace falta-- para que nunca se
/// acabe la lista sin tener nada que decir.
List<InstallPlan> plansFor(ToolId tool, Host host) => switch (tool) {
  ToolId.engine => const [
    InstallPlan(
      kind: InstallKind.own,
      label: 'Descargar el motor',
      explains:
          'Didacta clona su propio repositorio al lado de los tuyos. Son unos '
          'megas y no hace falta cuenta: es público.',
      manualSteps: [
        'git clone https://github.com/franjfal/didacta.git',
        'Y en Ajustes → Compilar, «Elegir el motor» y señalar esa carpeta.',
      ],
    ),
  ],
  ToolId.git => switch (host) {
    Host.macos => const [
      InstallPlan(
        kind: InstallKind.command,
        label: 'Instalar con Homebrew',
        explains: 'Homebrew descargará git e instalará en tu carpeta.',
        program: 'brew',
        arguments: ['install', 'git'],
        needs: 'brew',
        manualSteps: [
          'En el Terminal: brew install git',
          'O, sin Homebrew: xcode-select --install',
        ],
      ),
      InstallPlan(
        kind: InstallKind.command,
        label: 'Instalar las herramientas de Apple',
        explains:
            'Se abrirá el instalador de Apple: git y Python vienen en las '
            'Herramientas de Línea de Órdenes. Acepta ahí y vuelve a '
            'comprobar cuando termine.',
        program: 'xcode-select',
        arguments: ['--install'],
        handsOver: true,
        manualSteps: [
          'Abre el Terminal y escribe: xcode-select --install',
          'Acepta el instalador que aparece. Tarda unos minutos.',
        ],
      ),
    ],
    Host.windows => const [
      InstallPlan(
        kind: InstallKind.command,
        label: 'Instalar con winget',
        explains: 'Windows descargará e instalará Git para Windows.',
        program: 'winget',
        arguments: [
          'install',
          '--id',
          'Git.Git',
          '-e',
          '--source',
          'winget',
          '--accept-package-agreements',
          '--accept-source-agreements',
        ],
        needs: 'winget',
        manualSteps: [
          'En una consola: winget install --id Git.Git -e',
          'O descarga el instalador de git-scm.com/downloads/win',
        ],
      ),
      InstallPlan.manual(
        label: 'Descargar Git para Windows',
        explains:
            'Este Windows no tiene winget, así que la instalación es a mano.',
        manualSteps: [
          'Descarga el instalador de git-scm.com/downloads/win',
          'Ejecútalo y acepta las opciones por defecto.',
          'Cierra Didacta y vuelve a abrirla para que vea el PATH nuevo.',
        ],
      ),
    ],
    Host.linux => const [
      InstallPlan.manual(
        label: 'Instalarlo con tu gestor de paquetes',
        explains:
            'Instalar en Linux pide la contraseña de administrador, y eso se '
            'teclea en un terminal y no en una ventana de Didacta.',
        manualSteps: [
          'Debian o Ubuntu: sudo apt install git',
          'Fedora: sudo dnf install git',
          'Arch: sudo pacman -S git',
        ],
      ),
    ],
  },
  ToolId.python => switch (host) {
    Host.macos => const [
      InstallPlan(
        kind: InstallKind.command,
        label: 'Instalar con Homebrew',
        explains: 'Homebrew instalará la última versión estable de Python 3.',
        program: 'brew',
        arguments: ['install', 'python'],
        needs: 'brew',
        manualSteps: [
          'En el Terminal: brew install python',
          'O, sin Homebrew: xcode-select --install',
        ],
      ),
      InstallPlan(
        kind: InstallKind.command,
        label: 'Instalar las herramientas de Apple',
        explains:
            'Se abrirá el instalador de Apple: Python 3 viene en las '
            'Herramientas de Línea de Órdenes, junto con git.',
        program: 'xcode-select',
        arguments: ['--install'],
        handsOver: true,
        manualSteps: [
          'Abre el Terminal y escribe: xcode-select --install',
          'O descarga Python de python.org/downloads.',
        ],
      ),
    ],
    Host.windows => const [
      InstallPlan(
        kind: InstallKind.command,
        label: 'Instalar con winget',
        explains: 'Windows descargará e instalará Python 3.',
        program: 'winget',
        arguments: [
          'install',
          '--id',
          'Python.Python.3.12',
          '-e',
          '--source',
          'winget',
          '--accept-package-agreements',
          '--accept-source-agreements',
        ],
        needs: 'winget',
        manualSteps: [
          'En una consola: winget install --id Python.Python.3.12 -e',
          'O descarga Python 3 de python.org/downloads/windows, marcando '
              '«Add python.exe to PATH».',
        ],
      ),
      InstallPlan.manual(
        label: 'Descargar Python',
        explains:
            'Este Windows no tiene winget, así que la instalación es a mano.',
        manualSteps: [
          'Descarga Python 3 de python.org/downloads/windows',
          'En el instalador, marca «Add python.exe to PATH».',
          'Cierra Didacta y vuelve a abrirla.',
        ],
      ),
    ],
    Host.linux => const [
      InstallPlan.manual(
        label: 'Instalarlo con tu gestor de paquetes',
        explains:
            'Casi todas las distribuciones lo traen puesto; si no, lo instala '
            'el gestor de paquetes con la contraseña de administrador.',
        manualSteps: [
          'Debian o Ubuntu: sudo apt install python3',
          'Fedora: sudo dnf install python3',
          'Arch: sudo pacman -S python',
        ],
      ),
    ],
  },
  // LaTeX no tiene un plan: tiene un catálogo, y lo elige quien instala.
  // [latexOptions] es la lista, y cada opción trae el suyo.
  ToolId.latex => [for (final option in latexOptions(host)) option.plan],
};

/// Una distribución de TeX que se puede elegir.
class LatexOption {
  const LatexOption({
    required this.id,
    required this.name,
    required this.size,
    required this.what,
    required this.guide,
    required this.plan,
    this.needsAdmin = false,
    this.recommended = false,
  });

  final String id;
  final String name;

  /// Cuánto ocupa, dicho como se dice: «~100 MB», «~6 GB». Es el dato que
  /// de verdad decide, y va en la lista y no en la letra pequeña.
  final String size;

  /// Para quién es. Una frase por opción, porque «TeX Live» y «MacTeX» no
  /// le dicen nada a quien no sabe ya cuál quiere.
  final String what;

  final String guide;
  final InstallPlan plan;

  /// Si el instalador va a pedir la contraseña de administrador.
  ///
  /// Se avisa en la lista: es la diferencia entre que la instalación termine
  /// sola y que haya que estar delante, y en un ordenador de la universidad
  /// puede ser la diferencia entre poder y no poder.
  final bool needsAdmin;

  /// La que se ofrece marcada. La ligera que no pide administrador, porque
  /// es la que funciona en más sitios sin ayuda de nadie.
  final bool recommended;
}

/// Las distribuciones de TeX que se pueden elegir en este sistema.
///
/// La lista y el orden son los de `web/docs/empezar/latex.md`: primero la
/// ligera que no pide contraseña, después las completas.
List<LatexOption> latexOptions(Host host) => switch (host) {
  Host.macos => const [
    LatexOption(
      id: 'tinytex',
      name: 'TinyTeX',
      size: '~100 MB',
      what:
          'Lo justo para compilar, sin contraseña de administrador y en tu '
          'carpeta personal. Didacta le añade después los paquetes que usa.',
      guide: 'https://yihui.org/tinytex/',
      recommended: true,
      plan: InstallPlan(
        kind: InstallKind.script,
        label: 'Instalar TinyTeX',
        explains:
            'Se descarga el instalador oficial de TinyTeX y se ejecuta. '
            'Instala en ~/Library/TinyTeX y no pide contraseña. Después '
            'Didacta le pide a tlmgr los paquetes que el preámbulo necesita.',
        url: _tinytexUnix,
        filename: 'install-tinytex.sh',
        texPackages: true,
        manualSteps: [
          'En el Terminal: curl -sL https://yihui.org/tinytex/install-bin-unix.sh | sh',
          'Después: ~/Library/TinyTeX/bin/universal-darwin/tlmgr install latexmk beamer pgfplots tcolorbox',
        ],
      ),
    ),
    LatexOption(
      id: 'basictex',
      name: 'BasicTeX',
      size: '~100 MB',
      what:
          'La versión reducida de MacTeX, instalada en el sistema. Los '
          'paquetes que falten se añaden luego con `sudo tlmgr install`.',
      guide: 'https://tug.org/mactex/morepackages.html',
      needsAdmin: true,
      plan: InstallPlan(
        kind: InstallKind.installer,
        label: 'Descargar BasicTeX',
        explains:
            'Se descarga el paquete oficial de CTAN y se abre el instalador '
            'de macOS, que te pedirá la contraseña de administrador.',
        url: _basicTex,
        filename: 'BasicTeX.pkg',
        handsOver: true,
        manualSteps: [
          'Descarga BasicTeX.pkg de tug.org/mactex/morepackages.html',
          'Ábrelo y sigue el instalador.',
        ],
      ),
    ),
    LatexOption(
      id: 'mactex',
      name: 'MacTeX',
      size: '~6 GB',
      what:
          'TeX Live entera, con todo lo de CTAN. La que no te va a faltar '
          'nunca, si tienes el disco y la tarde.',
      guide: 'https://tug.org/mactex/',
      needsAdmin: true,
      plan: InstallPlan(
        kind: InstallKind.installer,
        label: 'Descargar MacTeX',
        explains:
            'Son unos 6 GB desde CTAN. Al terminar se abre el instalador de '
            'macOS, que te pedirá la contraseña de administrador.',
        url: _macTex,
        filename: 'MacTeX.pkg',
        handsOver: true,
        manualSteps: [
          'Descarga MacTeX.pkg de tug.org/mactex',
          'Ábrelo y sigue el instalador. Tarda un rato largo.',
        ],
      ),
    ),
  ],
  Host.windows => const [
    LatexOption(
      id: 'tinytex',
      name: 'TinyTeX',
      size: '~100 MB',
      what:
          'Lo justo para compilar, en tu carpeta de usuario y sin permisos de '
          'administrador.',
      guide: 'https://yihui.org/tinytex/',
      recommended: true,
      plan: InstallPlan(
        kind: InstallKind.script,
        label: 'Instalar TinyTeX',
        explains:
            'Se descarga el instalador oficial de TinyTeX y se ejecuta. '
            'Después Didacta le pide a tlmgr los paquetes que usa.',
        url: _tinytexWindows,
        filename: 'install-tinytex.bat',
        texPackages: true,
        manualSteps: [
          'Descarga yihui.org/tinytex/install-bin-windows.bat y ejecútalo.',
        ],
      ),
    ),
    LatexOption(
      id: 'miktex',
      name: 'MiKTeX',
      size: '~200 MB',
      what:
          'La de siempre en Windows. Instala cada paquete la primera vez que '
          'un documento lo pide, así que empieza pequeña y crece sola.',
      guide: 'https://miktex.org/download',
      plan: InstallPlan(
        kind: InstallKind.command,
        label: 'Instalar con winget',
        explains: 'Windows descargará e instalará MiKTeX.',
        program: 'winget',
        arguments: [
          'install',
          '--id',
          'MiKTeX.MiKTeX',
          '-e',
          '--source',
          'winget',
          '--accept-package-agreements',
          '--accept-source-agreements',
        ],
        needs: 'winget',
        manualSteps: [
          'Descarga el instalador básico de miktex.org/download',
          'Ejecútalo y acepta las opciones por defecto.',
        ],
      ),
    ),
    LatexOption(
      id: 'texlive',
      name: 'TeX Live',
      size: '~5 GB',
      what: 'TeX Live oficial, con su instalador gráfico. La completa.',
      guide: 'https://tug.org/texlive/windows.html',
      needsAdmin: true,
      plan: InstallPlan(
        kind: InstallKind.installer,
        label: 'Descargar TeX Live',
        explains:
            'Se descarga el instalador oficial de CTAN y se abre. La '
            'instalación se hace en su ventana y tarda un rato largo.',
        url: _texLiveWindows,
        filename: 'install-tl-windows.exe',
        handsOver: true,
        manualSteps: [
          'Descarga install-tl-windows.exe de tug.org/texlive/windows.html',
          'Ejecútalo y sigue el instalador.',
        ],
      ),
    ),
  ],
  Host.linux => const [
    LatexOption(
      id: 'tinytex',
      name: 'TinyTeX',
      size: '~100 MB',
      what:
          'Lo justo para compilar, en tu carpeta personal y sin sudo. La '
          'opción que funciona en una máquina donde no eres administrador.',
      guide: 'https://yihui.org/tinytex/',
      recommended: true,
      plan: InstallPlan(
        kind: InstallKind.script,
        label: 'Instalar TinyTeX',
        explains:
            'Se descarga el instalador oficial de TinyTeX y se ejecuta. '
            'Instala en ~/.TinyTeX y no pide sudo.',
        url: _tinytexUnix,
        filename: 'install-tinytex.sh',
        texPackages: true,
        manualSteps: [
          'En un terminal: curl -sL https://yihui.org/tinytex/install-bin-unix.sh | sh',
        ],
      ),
    ),
    LatexOption(
      id: 'distro',
      name: 'El TeX Live de tu distribución',
      size: '1-5 GB',
      what:
          'El que mantiene tu sistema, con sus actualizaciones. Pide la '
          'contraseña de administrador, así que se instala en un terminal.',
      guide: 'https://tug.org/texlive/quickinstall.html',
      needsAdmin: true,
      plan: InstallPlan.manual(
        label: 'Ver las órdenes',
        explains:
            'Instalar paquetes del sistema pide la contraseña de '
            'administrador, y eso se teclea en un terminal.',
        manualSteps: [
          'Debian o Ubuntu: sudo apt install texlive-latex-extra texlive-science latexmk',
          'Fedora: sudo dnf install texlive-scheme-medium latexmk',
          'Arch: sudo pacman -S texlive-latexextra texlive-binextra',
        ],
      ),
    ),
  ],
};

// ------------------------------------------------------- leer una versión ---

/// La versión que hay dentro de lo que contesta un `--version`.
///
/// Cada programa contesta a su manera --«git version 2.39.5», «Python 3.11.4»,
/// «Latexmk, John Collins, 2 January 2024. Version 4.83»-- así que se busca el
/// primer número con punto en la primera línea útil en lugar de escribir tres
/// expresiones regulares que caducan a la siguiente versión.
///
/// Devuelve null cuando no hay ningún número: eso también es información --el
/// programa contestó algo que no es una versión-- y fingir un «desconocida»
/// escondería que arrancó.
String? versionFrom(String output) {
  for (final line in output.split('\n')) {
    final match = RegExp(r'\d+(\.\d+)+').firstMatch(line);
    if (match != null) return match.group(0);
  }
  return null;
}

/// La versión mínima de Python que el motor pide.
///
/// 3.9 y no la última: el motor se escribió para funcionar sobre la Python
/// que trae cualquier máquina, incluida la de un runner de integración
/// continua o la de un ordenador de aula que no se actualiza desde 2021. Bajar
/// de ahí sí rompe --hay `dict | dict` y anotaciones diferidas por todo el
/// motor-- y decirlo ahora es mejor que un `SyntaxError` al compilar.
const String minimumPython = '3.9';

/// Si una versión leída llega al mínimo. Null --no se pudo leer-- pasa: negar
/// el paso por no haber sabido leer una cadena sería el peor de los errores.
bool meetsMinimum(String? version, String minimum) {
  if (version == null) return true;
  final found = version.split('.').map(int.tryParse).toList();
  final wanted = minimum.split('.').map(int.tryParse).toList();
  for (var i = 0; i < wanted.length; i += 1) {
    final a = i < found.length ? (found[i] ?? 0) : 0;
    final b = wanted[i] ?? 0;
    if (a != b) return a > b;
  }
  return true;
}
