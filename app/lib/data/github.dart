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
  const GitHubException(this.message);

  final String message;

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
}

/// El sign in por device flow.
class GitHubAuth {
  GitHubAuth({required this.clientId, http.Client? client})
    : _client = client ?? http.Client();

  /// El de la OAuth App. Público por definición: va en el binario.
  final String clientId;

  final http.Client _client;

  static const String _codeUrl = 'https://github.com/login/device/code';
  static const String _tokenUrl = 'https://github.com/login/oauth/access_token';

  /// `repo` y nada más: leer y escribir repositorios, que es lo que la
  /// aplicación hace. Sin `delete_repo`, sin `admin`, sin `user`.
  static const String scope = 'repo';

  /// Pide el código que se le enseña a la persona.
  Future<DeviceCode> start() async {
    final response = await _client.post(
      Uri.parse(_codeUrl),
      headers: const {'Accept': 'application/json'},
      body: {'client_id': clientId, 'scope': scope},
    );
    final json = _json(response.body);
    final error = json['error'];
    if (error != null) {
      throw GitHubException(
        'GitHub no acepta este Client ID ($error). Compruébalo en Ajustes: '
        'tiene que ser el de una OAuth App con «Device flow» activado.',
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
  ///
  /// Respeta el ritmo que pide GitHub, incluido el `slow_down`: preguntar más
  /// deprisa de lo que dice es cómo se acaba bloqueado a mitad de un sign in.
  Future<String> waitForToken(
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
      if (token != null && token.isNotEmpty) return token;

      switch (json['error']) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          interval += const Duration(seconds: 5);
          continue;
        case 'expired_token':
          throw const GitHubException(
            'El código ha caducado. Vuelve a empezar.',
          );
        case 'access_denied':
          throw const GitHubException('Se ha denegado el acceso desde GitHub.');
        default:
          throw GitHubException('GitHub respondió ${json['error']}');
      }
    }
    throw const GitHubException('El código ha caducado. Vuelve a empezar.');
  }

  void close() => _client.close();

  Map<String, dynamic> _json(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    throw const GitHubException('GitHub devolvió algo que no se entiende.');
  }
}

/// Lo que se le pregunta a GitHub una vez dentro.
class GitHubApi {
  GitHubApi({required this.token, http.Client? client})
    : _client = client ?? http.Client();

  final String token;
  final http.Client _client;

  static const String _base = 'https://api.github.com';

  Map<String, String> get _headers => {
    'Accept': 'application/vnd.github+json',
    'Authorization': 'Bearer $token',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  Future<GitHubUser> me() async {
    final response = await _client.get(
      Uri.parse('$_base/user'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw GitHubException(
        'GitHub no reconoce la sesión (${response.statusCode}). '
        'Vuelve a entrar.',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return GitHubUser(
      login: json['login'] as String? ?? '',
      name: json['name'] as String?,
      email: json['email'] as String?,
    );
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
          'No se pudieron listar los repositorios (${response.statusCode}).',
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

  void close() => _client.close();
}
