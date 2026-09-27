/// La credencial de GitHub, tal como se guarda en el llavero.
///
/// Dos clases de credencial, y las dos siguen valiendo:
///
/// * **el token de una OAuth App** (`gho_…`), que es lo que guardaba Didacta
///   hasta ahora: no caduca y llega a todo lo que llega la cuenta, con el
///   permiso `repo`. Se guardaba como un texto suelto, y así se sigue leyendo;
/// * **el de una GitHub App** (`ghu_…`): llega solo a los repositorios en los
///   que se ha instalado la App --los que la persona elige en GitHub--, dura
///   ocho horas y trae otro, el de renovar (`ghr_…`), que dura seis meses y
///   sirve para pedir uno nuevo sin volver a entrar. Se guarda como JSON, con
///   cuándo caduca cada uno.
///
/// Lo que se hace con ella --pedir uno nuevo antes de que caduque-- está en
/// `state/auth_state.dart`; aquí solo está qué es y cómo se guarda.
library;

import 'dart:convert';

class GitHubCredential {
  const GitHubCredential({
    required this.token,
    this.refreshToken,
    this.expires,
    this.refreshExpires,
    this.clientId,
  });

  /// Lo que se guardó en el llavero: JSON, o el token suelto de antes.
  factory GitHubCredential.decode(String stored) {
    final text = stored.trim();
    if (text.startsWith('{')) {
      try {
        final json = (jsonDecode(text) as Map).cast<String, dynamic>();
        return GitHubCredential(
          token: json['token'] as String? ?? '',
          refreshToken: json['refresh'] as String?,
          expires: DateTime.tryParse(json['expires'] as String? ?? ''),
          refreshExpires: DateTime.tryParse(
            json['refreshExpires'] as String? ?? '',
          ),
          clientId: json['clientId'] as String?,
        );
      } on FormatException {
        // Un token que empieza por llave no existe; si no es JSON, es basura
        // y como token no valdrá: GitHub lo dirá.
      } on TypeError {
        // Lo mismo.
      }
    }
    return GitHubCredential(token: text);
  }

  /// Lo que devuelve GitHub al entrar o al renovar, leído a las [now].
  ///
  /// `expires_in` y `refresh_token_expires_in` son segundos desde ahora: se
  /// guardan como fechas, porque «dentro de ocho horas» no significa nada
  /// mañana.
  factory GitHubCredential.fromResponse(
    Map<String, dynamic> json, {
    required DateTime now,
    String? clientId,
  }) {
    int? seconds(String key) => (json[key] as num?)?.toInt();
    final expiresIn = seconds('expires_in');
    final refreshIn = seconds('refresh_token_expires_in');
    return GitHubCredential(
      token: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String?,
      expires: expiresIn == null ? null : now.add(Duration(seconds: expiresIn)),
      refreshExpires: refreshIn == null
          ? null
          : now.add(Duration(seconds: refreshIn)),
      clientId: clientId,
    );
  }

  /// El que va en cada petición y en cada `git push`.
  final String token;

  /// El de pedir uno nuevo, si la credencial caduca.
  final String? refreshToken;

  /// Cuándo deja de valer [token]. Null: no caduca.
  final DateTime? expires;

  /// Cuándo deja de valer [refreshToken].
  final DateTime? refreshExpires;

  /// Con qué App se pidió: se renueva con la misma, aunque entretanto se haya
  /// cambiado el Client ID en Ajustes.
  final String? clientId;

  /// Si caduca y se puede renovar sola.
  bool get renewable => expires != null && (refreshToken?.isNotEmpty ?? false);

  /// Si es de una GitHub App: solo llega a donde está instalada.
  bool get fromApp => token.startsWith('ghu_') || renewable;

  /// Con cuánto margen se renueva: lo bastante para que un envío que empieza
  /// justo antes no se quede a medias.
  static const Duration margin = Duration(minutes: 15);

  /// Si hay que renovarla ya: caduca dentro de [margin], o ya ha caducado.
  bool dueAt(DateTime now) {
    final end = expires;
    if (end == null || !renewable) return false;
    return !now.isBefore(end.subtract(margin));
  }

  /// Si el de renovar ya no vale: hay que volver a entrar.
  bool refreshExpiredAt(DateTime now) {
    final end = refreshExpires;
    return end != null && !now.isBefore(end);
  }

  /// Cuándo toca renovarla, o null si no caduca.
  DateTime? renewAt() => renewable ? expires!.subtract(margin) : null;

  /// Cómo se guarda. El token suelto, igual que antes, si no caduca: así una
  /// versión anterior de Didacta lo sigue leyendo.
  String encode() {
    if (!renewable) return token;
    return jsonEncode({
      'token': token,
      'refresh': refreshToken,
      'expires': expires!.toUtc().toIso8601String(),
      if (refreshExpires != null)
        'refreshExpires': refreshExpires!.toUtc().toIso8601String(),
      if (clientId != null) 'clientId': clientId,
    });
  }
}
