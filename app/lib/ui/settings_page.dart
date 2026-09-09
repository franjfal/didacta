/// Access, session and diagnostics.
///
/// The screen where the two ways into the repository are made explicit,
/// because "where does my change go, and as whom" should be answerable in one
/// place rather than inferred.
///
/// The one thing this screen will not do is ask for a GitHub password. GitHub
/// removed password authentication for git in 2021, so it would not work — and
/// a form that asks for an account password in order to store it has the shape
/// of a phishing page even when the intent is honest. What it asks for is a
/// token scoped to one repository, and it checks against GitHub what that
/// token can actually do before storing it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/auth.dart';
import '../data/content_gateway.dart';
import '../data/repository_access.dart';
import '../router.dart';
import '../state/session.dart';
import 'shell.dart';
import 'theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = watchSession(context);

    return Column(
      children: [
        const PageHeader(
          title: 'Ajustes',
          subtitle: 'Quién eres, cómo se llega al contenido, y qué hay cargado',
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 28),
            children: [
              const SectionLabel('Cómo se llega al contenido'),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _GatewayCard(session: session),
              ),

              const SectionLabel('Sesión'),
              _SessionSection(session: session),

              const SectionLabel('Token del repositorio'),
              _TokenSection(session: session),

              const SectionLabel('Catálogo'),
              _CatalogueSection(session: session),
            ],
          ),
        ),
      ],
    );
  }
}

class _GatewayCard extends StatelessWidget {
  const _GatewayCard({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final gateway = session.gateway;
    final (title, explanation) = switch (gateway.kind) {
      GatewayKind.direct => (
          'Directo a GitHub',
          'Con un token guardado en el llavero de este equipo. Los commits '
              'van al repositorio sin pasar por la API.',
        ),
      GatewayKind.api => (
          'A través de la API',
          'La identidad la da Firebase y los permisos los decide access.json, '
              'que vive en el repositorio de contenido. El token de GitHub lo '
              'tiene el Worker: esta aplicación nunca lo ve.',
        ),
      GatewayKind.none => (
          'Sin acceso de escritura',
          'Solo se puede leer el catálogo. Añade un token más abajo, o '
              'compila la aplicación con --dart-define=DIDACTA_API.',
        ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: gateway.canWrite
                        ? didactaAccentDark.withValues(alpha: 0.12)
                        : didactaPanel,
                    border: Border.all(
                        color: gateway.canWrite
                            ? didactaAccentDark
                            : didactaRule),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    gateway.canWrite ? 'lectura y escritura' : 'solo lectura',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color:
                          gateway.canWrite ? didactaAccentDark : didactaMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(explanation,
                style: const TextStyle(fontSize: 12.5, height: 1.4)),
            const SizedBox(height: 8),
            Text(gateway.describe(),
                style: const TextStyle(
                    fontSize: 11.5, color: didactaMuted, height: 1.3)),
          ],
        ),
      ),
    );
  }
}

class _SessionSection extends StatefulWidget {
  const _SessionSection({required this.session});

  final Session session;

  @override
  State<_SessionSection> createState() => _SessionSectionState();
}

class _SessionSectionState extends State<_SessionSection> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _problem;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Session get session => widget.session;

  Future<void> _run(Future<void> Function() action, {String? notice}) async {
    setState(() {
      _busy = true;
      _problem = null;
      _notice = null;
    });
    try {
      await action();
      if (mounted) setState(() => _notice = notice);
    } on AuthException catch (error) {
      if (mounted) setState(() => _problem = error.message);
    } catch (error) {
      if (mounted) setState(() => _problem = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authorisation = session.authorisation;

    if (authorisation.signedIn) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        authorisation.email ?? 'sesión iniciada',
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w500),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _run(session.signOut),
                      child: const Text('Salir'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Pill(
                      authorisation.role == null
                          ? 'sin rol en access.json'
                          : 'rol: ${authorisation.role}',
                      colour: authorisation.role == null
                          ? didactaEx
                          : didactaAccentDark,
                    ),
                    const SizedBox(width: 6),
                    _Pill(
                      authorisation.emailVerified
                          ? 'correo verificado'
                          : 'correo sin verificar',
                      colour: authorisation.emailVerified
                          ? didactaAccentDark
                          : didactaTeacher,
                    ),
                  ],
                ),
                if (!authorisation.emailVerified) ...[
                  const SizedBox(height: 10),
                  const Note(
                    'La API rechaza escrituras desde una dirección sin '
                    'verificar, porque una dirección sin verificar la puede '
                    'reclamar cualquiera — incluida una que esté en '
                    'access.json.',
                    tone: didactaTeacher,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.mail_outline, size: 15),
                    label: const Text('Reenviar la verificación'),
                    onPressed: _busy
                        ? null
                        : () => _run(session.auth.resendVerification,
                            notice: 'Correo de verificación enviado.'),
                  ),
                ],
                if (authorisation.role == null) ...[
                  const SizedBox(height: 10),
                  Note(
                    'Firebase te reconoce, pero ${authorisation.email ?? "esta "
                        "dirección"} no está en access.json, así que solo '
                    'puedes leer lo público. Quien tenga el rol de owner '
                    'puede añadirte con un commit a ese fichero.',
                  ),
                ],
                if (_notice != null) ...[
                  const SizedBox(height: 10),
                  Note(_notice!, tone: didactaAccentDark),
                ],
                if (_problem != null) ...[
                  const SizedBox(height: 10),
                  Note(_problem!, tone: didactaTeacher),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sin sesión. Puedes leer el catálogo público; para editar '
                'hace falta identificarse.',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.login, size: 16),
                label: const Text('Entrar con Google'),
                onPressed:
                    _busy ? null : () => _run(session.auth.signInWithGoogle),
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              TextField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Correo'),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Contraseña'),
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _signIn(),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton(
                    onPressed: _busy ? null : _signIn,
                    child: const Text('Entrar'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                              () => session.auth
                                  .sendPasswordReset(_email.text),
                              notice: 'Si esa dirección tiene cuenta, le '
                                  'llegará un correo para cambiar la '
                                  'contraseña.',
                            ),
                    child: const Text('He olvidado la contraseña'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                              () => session.auth.createAccount(
                                  _email.text, _password.text),
                              notice: 'Cuenta creada. Verifica el correo '
                                  'antes de intentar editar.',
                            ),
                    child: const Text('Crear cuenta'),
                  ),
                ],
              ),
              if (_notice != null) ...[
                const SizedBox(height: 10),
                Note(_notice!, tone: didactaAccentDark),
              ],
              if (_problem != null) ...[
                const SizedBox(height: 10),
                Note(_problem!, tone: didactaTeacher),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _signIn() => _run(
      () => session.auth.signInWithPassword(_email.text, _password.text));
}

class _TokenSection extends StatefulWidget {
  const _TokenSection({required this.session});

  final Session session;

  @override
  State<_TokenSection> createState() => _TokenSectionState();
}

class _TokenSectionState extends State<_TokenSection> {
  final _token = TextEditingController();
  bool _busy = false;
  TokenCheck? _check;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Session get session => widget.session;

  @override
  Widget build(BuildContext context) {
    if (!session.canStoreToken) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Note(
          'Un navegador no puede guardar un token de forma segura: lo que la '
          'página puede leer, lo puede leer cualquiera con las herramientas '
          'de desarrollo abiertas, y un token de GitHub no está limitado a una '
          'pestaña. En web el acceso va por la API, que lo guarda ella. Esta '
          'opción existe en la versión de escritorio.',
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (session.hasStoredToken) ...[
                Row(
                  children: [
                    const Icon(Icons.vpn_key, size: 16,
                        color: didactaAccentDark),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Hay un token guardado en el llavero de este equipo.',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() => _busy = true);
                              await session.clearToken();
                              if (mounted) {
                                setState(() {
                                  _busy = false;
                                  _check = null;
                                });
                              }
                            },
                      child: const Text('Quitar'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'El token nunca se muestra, ni aquí ni en ningún sitio: '
                  'guardarlo y poder volver a leerlo en pantalla son cosas '
                  'distintas, y solo la primera hace falta.',
                  style: const TextStyle(fontSize: 11.5, color: didactaMuted),
                ),
              ] else ...[
                Text(
                  'Un token de permisos limitados a '
                  '${session.contentOwner}/${session.contentRepo} con '
                  '«Contents: Read and write». Se guarda en el llavero del '
                  'sistema y no sale de este equipo.',
                  style: const TextStyle(fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 10),
                _TokenHelp(
                  owner: session.contentOwner,
                  repo: session.contentRepo,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _token,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Token',
                    hintText: 'github_pat_…',
                  ),
                  onSubmitted: (_) => _verify(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton(
                      onPressed: _busy ? null : _verify,
                      child: Text(_busy ? 'Comprobando…' : 'Comprobar y guardar'),
                    ),
                  ],
                ),
              ],
              if (_check?.problem != null) ...[
                const SizedBox(height: 10),
                Note(_check!.problem!, tone: didactaTeacher),
              ],
              if (_check?.scopeWarning != null) ...[
                const SizedBox(height: 10),
                Note(_check!.scopeWarning!, tone: didactaEx),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Checks the token against GitHub before storing it.
  ///
  /// Deliberately not "store then find out": a token that can only read, or
  /// that does not reach the repository, otherwise fails at the moment
  /// somebody tries to save an edit.
  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _check = null;
    });
    final check = await GitHubDirect.check(
      owner: session.contentOwner,
      repo: session.contentRepo,
      token: _token.text,
    );
    if (!mounted) return;
    setState(() => _check = check);

    if (check.valid && check.canWrite) {
      await session.storeToken(_token.text);
      if (!mounted) return;
      _token.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Token guardado (${check.login}).')),
      );
    }
    if (mounted) setState(() => _busy = false);
  }
}

class _TokenHelp extends StatelessWidget {
  const _TokenHelp({required this.owner, required this.repo});

  final String owner;
  final String repo;

  @override
  Widget build(BuildContext context) {
    const url = 'https://github.com/settings/personal-access-tokens/new';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: didactaPanel,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Dónde se crea',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Row(
            children: [
              const Expanded(
                child: SelectableText(
                  url,
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
              IconButton(
                tooltip: 'Copiar la dirección',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.content_copy, size: 14),
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copiado.')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Repository access: solo $owner/$repo · Permissions → '
            'Contents: Read and write. Nada más: un token clásico con «repo» '
            'alcanza todos tus repositorios y aquí no hace falta ninguno más.',
            style: const TextStyle(fontSize: 11, height: 1.35,
                color: didactaMuted),
          ),
        ],
      ),
    );
  }
}

class _CatalogueSection extends StatelessWidget {
  const _CatalogueSection({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final catalogue = session.catalogue;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Fact('nombre', catalogue.name),
              _Fact('unidades', '${catalogue.units.length}'),
              _Fact('asignaturas', '${catalogue.courses.length}'),
              _Fact('perfiles de salida', '${catalogue.profiles.length}'),
              _Fact('idiomas', catalogue.languages.join(', ')),
              // Identifies the content this catalogue describes, so a stale
              // tab can be told from a current one without comparing records.
              _Fact('hash del contenido', catalogue.contentHash),
              _Fact('origen', session.catalogueSource.describe),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 15),
                    label: const Text('Recargar el catálogo'),
                    onPressed: session.reloadCatalogue,
                  ),
                ],
              ),
              if (catalogue.errors.isNotEmpty) ...[
                const SizedBox(height: 12),
                Note(
                  '${catalogue.errors.length} problema(s) al leer el '
                  'repositorio:\n${catalogue.errors.take(4).join("\n")}',
                  tone: didactaTeacher,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 132,
              child: Text(label,
                  style:
                      const TextStyle(fontSize: 11.5, color: didactaMuted)),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.colour});

  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.10),
          border: Border.all(color: colour),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10.5, color: colour, fontWeight: FontWeight.w600)),
      );
}
