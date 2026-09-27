/// Entrar en GitHub, y preguntarle lo que hace falta.
///
/// Sustituye a Firebase. La identidad ya no la da un servicio aparte que
/// después hay que traducir a permisos: **la da GitHub**, que es quien tiene
/// los repositorios y quien ya sabe quién puede escribir en cuál. Un permiso
/// deja de ser una línea en un `access.json` y pasa a ser lo que de verdad
/// era: acceso al repositorio.
///
/// El camino es el *device flow*, que es el que usan las herramientas de
/// terminal: la aplicación enseña un código corto, la persona lo mete en
/// github.com/login/device desde su navegador y autoriza allí. Se elige por
/// tres razones:
///
/// **No hay secreto que guardar.** Un `client_id` es público; una aplicación
/// de escritorio no puede esconder un `client_secret`, así que un flujo que lo
/// exija es un flujo que se está usando mal.
///
/// **No hace falta un servidor.** Nada de redirecciones ni de un callback que
/// atender: la aplicación pregunta cada pocos segundos si ya se ha autorizado.
///
/// **La contraseña no pasa por aquí.** Se teclea en github.com y en ningún
/// otro sitio, que es la única forma honesta de pedirla.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'diagnostics.dart';
import '../model/github_credential.dart';
import '../l10n/tr.dart';

/// Lo que GitHub devuelve para empezar: el código que se enseña y el que se
/// usa para preguntar si ya está.
class DeviceCode {
  const DeviceCode({
    required this.userCode,
    required this.deviceCode,
    required this.verificationUri,
    required this.interval,
    required this.expiresIn,
  });

  /// El que se lee en voz alta: `ABCD-1234`.
  final String userCode;

  /// El que se manda al preguntar. No se enseña.
  final String deviceCode;

  /// Dónde se mete el código.
  final String verificationUri;

  /// Cada cuántos segundos se puede preguntar, según GitHub.
  final int interval;

  final int expiresIn;
}

class GitHubException implements Exception {
  const GitHubException(this.message, {this.status});

  final String message;

  /// El código que devolvió GitHub, cuando la respuesta llegó a llegar.
  ///
  /// Null es que no hubo respuesta: sin red, DNS caído, el portal cautivo de
  /// un hotel. Esa distinción es la que decide si a alguien se le cierra la
  /// sesión, así que no puede quedarse en el texto del mensaje.
  final int? status;

  /// Si GitHub ha dicho que esta credencial ya no vale.
  ///
  /// Solo 401, «no te reconozco». Un 403 no habla de la credencial: es el
  /// límite de peticiones por hora, o una organización que pide SSO, o un
  /// repositorio al que esta cuenta no llega. Tratarlo como un 401 echaba de
  /// la aplicación --y borraba el token del llavero-- a quien solo había
  /// hecho demasiadas peticiones seguidas. Lo mismo para cualquier otra cosa,
  /// un 500 o no llegar: no dice nada de la credencial.
  bool get rejectsCredential => status == 401;

  @override
  String toString() => message;
}

/// Un repositorio tal como lo lista GitHub.
class GitHubRepo {
  const GitHubRepo({
    required this.owner,
    required this.name,
    required this.defaultBranch,
    required this.private,
    required this.canWrite,
  });

  final String owner;
  final String name;
  final String defaultBranch;
  final bool private;

  /// Si esta persona puede escribir en él. Se enseña, porque clonar uno donde
  /// no se puede empujar es trabajo que no sale de la máquina.
  final bool canWrite;

  String get id => '$owner/$name';
}

/// Quién ha entrado. El nombre y el correo son para firmar los commits.
class GitHubUser {
  const GitHubUser({required this.login, this.name, this.email});

  final String login;
  final String? name;
  final String? email;

  String get authorName => (name == null || name!.isEmpty) ? login : name!;

  /// El correo de los commits.
  ///
  /// GitHub oculta el de la cuenta cuando se pide privacidad, y entonces el
  /// que hay que usar es el `noreply` suyo: un commit con un correo inventado
  /// no se atribuye a nadie en su perfil.
  String get authorEmail => (email == null || email!.isEmpty)
      ? '$login@users.noreply.github.com'
      : email!;

  /// Para recordar quién entró entre arranques.
  ///
  /// No es un secreto --el nombre público de una cuenta-- así que no va al
  /// llavero: va con el resto de las preferencias. El secreto es el token, y
  /// ese sigue donde estaba.
  Map<String, dynamic> toJson() => {
    'login': login,
    if (name != null) 'name': name,
    if (email != null) 'email': email,
  };

  static GitHubUser? fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final login = json['login'] as String? ?? '';
      if (login.isEmpty) return null;
      return GitHubUser(
        login: login,
        name: json['name'] as String?,
        email: json['email'] as String?,
      );
    } catch (caught, trace) {
      Diagnostics.instance.note('github.fromJson', caught, trace);
      // Lo que no se puede leer es como si no estuviera: se vuelve a
      // preguntar a GitHub en cuanto haya red.
      return null;
    }
  }
}

/// El Client ID de la GitHub App de Didacta, con la que se entra por defecto
/// cuando existe. Vacío mientras no está registrada: entonces se entra con
/// la OAuth App de siempre. Ver «La GitHub App» en `docs/DISTRIBUTION.md`.
const String didactaAppClientId = String.fromEnvironment(
  'DIDACTA_GITHUB_APP_CLIENT',
  defaultValue: '',
);

/// Su nombre corto en GitHub: el de `github.com/apps/<nombre>`, que es donde
/// se eligen los repositorios a los que llega.
const String didactaAppSlug = String.fromEnvironment(
  'DIDACTA_GITHUB_APP_SLUG',
  defaultValue: 'didacta-app',
);

/// Si [clientId] es el de una GitHub App y no el de una OAuth App.
bool isGitHubAppClientId(String clientId) => clientId.trim().startsWith('Iv');

/// Dónde se elige, en GitHub, a qué repositorios llega la App de [slug]:
/// instalarla por primera vez o cambiar los que ya tiene.
String githubAppInstallUrl(String slug) =>
    'https://github.com/apps/$slug/installations/new';

/// El sign in por device flow.
class GitHubAuth {
  GitHubAuth({required this.clientId, http.Client? client})
    : _client = LoggedClient(client ?? http.Client());

  /// El de la OAuth App, o el de la GitHub App. Público por definición: va
  /// en el binario.
  final String clientId;

  /// Si es el de una GitHub App: sus Client ID empiezan por `Iv` (`Iv1.…`,
  /// `Iv23li…`), los de una OAuth App por `Ov`. Con una App no se piden
  /// permisos al entrar --son los de la App, los mismos para todos-- y el
  /// token caduca y se renueva.
  bool get isApp => isGitHubAppClientId(clientId);

  final http.Client _client;

  static const String _codeUrl = 'https://github.com/login/device/code';
  static const String _tokenUrl = 'https://github.com/login/oauth/access_token';

  /// `repo` y `workflow`: leer y escribir repositorios, que es lo que la
  /// aplicación hace, y poder escribir en `.github/workflows/`. Sin
  /// `delete_repo`, sin `admin`, sin `user`.
  ///
  /// `workflow` porque GitHub **rechaza el envío** de un commit que toca un
  /// workflow si el token no lo tiene, aunque tenga `repo`: el ejemplo trae
  /// el de la web del curso, y el CI del material es un workflow. Con solo
  /// `repo`, el primer envío del ejemplo fallaba contra GitHub --no contra
  /// las pruebas, que envían a un repositorio del disco--.
  static const String scope = 'repo workflow';

  /// Pide el código que se le enseña a la persona.
  Future<DeviceCode> start() async {
    final response = await _client.post(
      Uri.parse(_codeUrl),
      headers: const {'Accept': 'application/json'},
      body: {'client_id': clientId, if (!isApp) 'scope': scope},
    );
    final json = _json(response.body);
    final error = json['error'];
    if (error != null) {
      throw GitHubException(
        tr(
          'GitHub no acepta este Client ID ({0}). Compruébalo en Ajustes: '
          'tiene que ser el de una GitHub App o una OAuth App con «Device '
          'flow» activado.',
          [error],
        ),
      );
    }
    return DeviceCode(
      userCode: json['user_code'] as String? ?? '',
      deviceCode: json['device_code'] as String? ?? '',
      verificationUri:
          json['verification_uri'] as String? ??
          'https://github.com/login/device',
      interval: (json['interval'] as num?)?.toInt() ?? 5,
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 900,
    );
  }

  /// Pregunta hasta que la persona autoriza, y devuelve el token.
  Future<String> waitForToken(
    DeviceCode code, {
    Future<void> Function(Duration)? sleep,
    DateTime Function()? now,
  }) async => (await waitForCredential(code, sleep: sleep, now: now)).token;

  /// Pregunta hasta que la persona autoriza, y devuelve la credencial: con el
  /// de renovar y cuándo caduca cada uno, si es de una GitHub App.
  ///
  /// Respeta el ritmo que pide GitHub, incluido el `slow_down`: preguntar más
  /// deprisa de lo que dice es cómo se acaba bloqueado a mitad de un sign in.
  Future<GitHubCredential> waitForCredential(
    DeviceCode code, {
    Future<void> Function(Duration)? sleep,
    DateTime Function()? now,
  }) async {
    final wait = sleep ?? Future<void>.delayed;
    final clock = now ?? DateTime.now;
    final deadline = clock().add(Duration(seconds: code.expiresIn));
    var interval = Duration(seconds: code.interval);

    while (clock().isBefore(deadline)) {
      await wait(interval);
      final response = await _client.post(
        Uri.parse(_tokenUrl),
        headers: const {'Accept': 'application/json'},
        body: {
          'client_id': clientId,
          'device_code': code.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
      );
      final json = _json(response.body);
      final token = json['access_token'] as String?;
      if (token != null && token.isNotEmpty) {
        return GitHubCredential.fromResponse(
          json,
          now: clock(),
          clientId: clientId,
        );
      }

      switch (json['error']) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          interval += const Duration(seconds: 5);
          continue;
        case 'expired_token':
          throw GitHubException(tr('El código ha caducado. Vuelve a empezar.'));
        case 'access_denied':
          throw GitHubException(tr('Se ha denegado el acceso desde GitHub.'));
        default:
          throw GitHubException(tr('GitHub respondió {0}', [json['error']]));
      }
    }
    throw GitHubException(tr('El código ha caducado. Vuelve a empezar.'));
  }

  /// Pide una credencial nueva con la de renovar, sin que nadie vuelva a
  /// entrar. Sin client secret: con el device flow GitHub no lo pide.
  ///
  /// Si GitHub dice que la de renovar ya no vale --seis meses sin usarla, o
  /// revocada--, lanza con `status: 401`, que es lo que cierra la sesión.
  /// Sin red, lanza sin `status`: se vuelve a intentar más tarde.
  Future<GitHubCredential> refresh(
    String refreshToken, {
    DateTime Function()? now,
  }) async {
    final response = await _client.post(
      Uri.parse(_tokenUrl),
      headers: const {'Accept': 'application/json'},
      body: {
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );
    final json = _json(response.body);
    final token = json['access_token'] as String?;
    if (token != null && token.isNotEmpty) {
      return GitHubCredential.fromResponse(
        json,
        now: (now ?? DateTime.now)(),
        clientId: clientId,
      );
    }
    final error = json['error'];
    if (error == 'bad_refresh_token' ||
        error == 'incorrect_client_credentials' ||
        response.statusCode == 401) {
      throw GitHubException(
        tr('La sesión de GitHub ha caducado: vuelve a entrar.'),
        status: 401,
      );
    }
    throw GitHubException(
      tr('GitHub no ha renovado la sesión ({0}).', [
        error ?? response.statusCode,
      ]),
      status: response.statusCode,
    );
  }

  void close() => _client.close();

  Map<String, dynamic> _json(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (caught, trace) {
      Diagnostics.instance.note('github._json', caught, trace);
    }
    throw GitHubException(tr('GitHub devolvió algo que no se entiende.'));
  }
}

/// Lo que se le pregunta a GitHub una vez dentro.
class GitHubApi {
  GitHubApi({required this.token, http.Client? client})
    : _client = LoggedClient(client ?? http.Client());

  final String token;
  final http.Client _client;

  static const String _base = 'https://api.github.com';

  Map<String, String> get _headers => {
    'Accept': 'application/vnd.github+json',
    'Authorization': tr('Bearer {0}', [token]),
    'X-GitHub-Api-Version': '2022-11-28',
  };

  Future<GitHubUser> me() async {
    final response = await _client.get(
      Uri.parse('$_base/user'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw GitHubException(
        tr(
          'GitHub no reconoce la sesión ({0}). '
          'Vuelve a entrar.',
          [response.statusCode],
        ),
        status: response.statusCode,
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return GitHubUser(
      login: json['login'] as String? ?? '',
      name: json['name'] as String?,
      email: json['email'] as String?,
    );
  }

  /// Los permisos del token, como los dice GitHub en `X-OAuth-Scopes`.
  ///
  /// Null cuando GitHub no los dice, que es lo que pasa con los tokens que no
  /// son de una OAuth App --los de una GitHub App, los de grano fino--: esos
  /// no tienen permisos por nombre, y lo que dejan hacer se ve al hacerlo.
  Future<Set<String>?> scopes() async {
    final response = await _client.get(
      Uri.parse('$_base/user'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw GitHubException(
        tr(
          'GitHub no reconoce la sesión ({0}). '
          'Vuelve a entrar.',
          [response.statusCode],
        ),
        status: response.statusCode,
      );
    }
    final header = response.headers['x-oauth-scopes'];
    if (header == null) return null;
    return {
      for (final scope in header.split(','))
        if (scope.trim().isNotEmpty) scope.trim(),
    };
  }

  /// Los repositorios a los que esta persona llega, los suyos y los que le
  /// han compartido.
  Future<List<GitHubRepo>> repositories() async {
    final found = <GitHubRepo>[];
    for (var page = 1; page <= 5; page += 1) {
      final response = await _client.get(
        Uri.parse(
          '$_base/user/repos?per_page=100&page=$page&sort=updated'
          '&affiliation=owner,collaborator,organization_member',
        ),
        headers: _headers,
      );
      if (response.statusCode != 200) {
        throw GitHubException(
          tr('No se pudieron listar los repositorios ({0}).', [
            response.statusCode,
          ]),
        );
      }
      final list = jsonDecode(response.body) as List;
      for (final item in list) {
        final json = (item as Map).cast<String, dynamic>();
        final permissions = (json['permissions'] as Map?) ?? const {};
        found.add(
          GitHubRepo(
            owner: ((json['owner'] as Map?)?['login'] as String?) ?? '',
            name: json['name'] as String? ?? '',
            defaultBranch: json['default_branch'] as String? ?? 'main',
            private: json['private'] as bool? ?? false,
            canWrite:
                (permissions['push'] as bool?) ??
                (permissions['admin'] as bool?) ??
                false,
          ),
        );
      }
      if (list.length < 100) break;
    }
    return found;
  }

  /// Si esta cuenta llega a este repositorio, y con qué permiso.
  ///
  /// Null es que no llega. **GitHub contesta 404 y no 403** a un repositorio
  /// privado que no puedes ver: no te dice ni que existe, que es lo correcto
  /// --enterarte de que existe ya sería información-- y lo que significa aquí
  /// es lo mismo en los dos casos: esa carpeta no se puede añadir.
  ///
  /// Se pregunta por el par exacto que dice el remoto del clon y no se busca
  /// en la lista de repositorios: `user/repos` pagina, tarda, y con doscientos
  /// repositorios la respuesta a «¿llego a este?» no puede depender de haber
  /// recorrido todos.
  Future<GitHubRepo?> repository(String owner, String name) async {
    final response = await _client.get(
      Uri.parse('$_base/repos/$owner/$name'),
      headers: _headers,
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw GitHubException(
        tr('GitHub no contestó sobre {0}/{1} ({2}).', [
          owner,
          name,
          response.statusCode,
        ]),
        status: response.statusCode,
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final permissions = (json['permissions'] as Map?) ?? const {};
    return GitHubRepo(
      owner: ((json['owner'] as Map?)?['login'] as String?) ?? owner,
      name: json['name'] as String? ?? name,
      defaultBranch: json['default_branch'] as String? ?? 'main',
      private: json['private'] as bool? ?? false,
      canWrite:
          (permissions['push'] as bool?) ??
          (permissions['admin'] as bool?) ??
          false,
    );
  }

  /// Si un repositorio es de contenido de Didacta.
  ///
  /// Se mira si tiene `didacta.yaml` en la raíz, que es lo mismo que mira el
  /// motor para saber dónde empieza un repositorio. Así la lista que se
  /// ofrece no son los doscientos repositorios de alguien, sino los que esto
  /// sabe abrir.
  Future<bool> isContentRepo(String owner, String name) async {
    final response = await _client.get(
      Uri.parse('$_base/repos/$owner/$name/contents/didacta.yaml'),
      headers: _headers,
    );
    return response.statusCode == 200;
  }

  /// Crea un repositorio vacío en la cuenta de quien ha entrado.
  ///
  /// Vacío de verdad --sin `auto_init`, sin README ni licencia de GitHub--
  /// porque el primer commit lo hace Didacta con sus ficheros, y uno de
  /// GitHub delante obligaría a mezclar dos historias. Si el nombre ya está
  /// cogido, GitHub contesta 422 y eso sale en [GitHubException.status].
  Future<GitHubRepo> createRepository({
    required String name,
    String description = '',
    bool private = true,
  }) async {
    final response = await _client.post(
      Uri.parse('$_base/user/repos'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'description': description,
        'private': private,
        'auto_init': false,
      }),
    );
    if (response.statusCode != 201) {
      throw GitHubException(
        response.statusCode == 422
            ? tr('Ya tienes un repositorio que se llama {0}.', [name])
            : tr('GitHub no dejó crear {0} ({1}).', [
                name,
                response.statusCode,
              ]),
        status: response.statusCode,
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return GitHubRepo(
      owner: ((json['owner'] as Map?)?['login'] as String?) ?? '',
      name: json['name'] as String? ?? name,
      defaultBranch: json['default_branch'] as String? ?? 'main',
      private: json['private'] as bool? ?? private,
      canWrite: true,
    );
  }

  void close() => _client.close();
}

/// Un cliente que apunta en el registro lo que GitHub contesta cuando no es
/// un sí: el código, el método y la ruta, nunca la cabecera ni el cuerpo.
class LoggedClient extends http.BaseClient {
  LoggedClient(this.inner);

  final http.Client inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    if (response.statusCode >= 300) {
      Diagnostics.instance.github(
        method: request.method,
        path: request.url.path,
        status: response.statusCode,
      );
    }
    return response;
  }

  @override
  void close() => inner.close();
}
