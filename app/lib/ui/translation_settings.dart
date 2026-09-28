/// Las credenciales de traducción automática.
///
/// Aquí y no en un repositorio: son configuración privada de esta máquina, no
/// contenido. La distinción manda sobre todo lo que hace este fichero. Lo que
/// sí es contenido --a qué idiomas se traduce cada asignatura, la memoria
/// terminológica, las decisiones-- vive en el repositorio y se comparte; una
/// clave de API no sale del llavero del sistema.
///
/// La clave no se vuelve a enseñar después de guardarla. Se dice que hay una y
/// se enseñan sus últimos cuatro caracteres, lo justo para reconocer cuál de
/// las tuyas pusiste; para cambiarla se escribe otra. Un campo que devuelve la
/// clave entera es una clave en una captura de pantalla.
///
/// Y hay un botón de probar, porque una credencial mal puesta no se nota hasta
/// que alguien manda cincuenta unidades a traducir y vuelven todas con un 401.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/translation_secrets.dart';
import '../data/translator.dart';
import '../data/translator_http.dart';
import '../model/translation.dart';
import 'problem.dart';
import 'theme.dart';
import '../l10n/tr.dart';

class TranslationSection extends StatelessWidget {
  const TranslationSection({super.key, required this.secrets});

  final TranslationSecrets secrets;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                'Para traducir automáticamente hace falta una cuenta en Google o '
                'en Azure, o encender Apertium, que es gratuito. Basta con uno; '
                'con varios puestos, se elige al traducir.',
              ),
              style: TextStyle(fontSize: 12.5, height: 1.45),
            ),
            const SizedBox(height: 6),
            if (!secrets.canStoreSafely)
              Note(
                tr(
                  'Aquí no hay dónde guardar una clave de forma segura. Usa la '
                  'aplicación de escritorio.',
                ),
                tone: context.palette.ex,
              )
            else
              Note(
                tr(
                  'Se guardan en el llavero del sistema, en esta máquina. No '
                  'entran en ningún repositorio, ni en git, ni en las copias '
                  'que exportes: son configuración tuya, no contenido.',
                ),
              ),
            const SizedBox(height: 10),
            for (final provider in TranslationProvider.values)
              if (provider == TranslationProvider.apertium)
                _ApertiumCard(secrets: secrets)
              else
                _ProviderCard(provider: provider, secrets: secrets),
          ],
        ),
      ),
    ),
  );
}

class _ProviderCard extends StatefulWidget {
  const _ProviderCard({required this.provider, required this.secrets});

  final TranslationProvider provider;
  final TranslationSecrets secrets;

  @override
  State<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<_ProviderCard> {
  final _key = TextEditingController();
  final _region = TextEditingController();
  final _endpoint = TextEditingController();

  /// Lo que hay guardado. Solo para poder decir que hay algo y enseñar su
  /// pista: el valor de la clave no vuelve a los campos.
  Credentials _stored = const Credentials();
  bool _loaded = false;
  bool _busy = false;
  ProviderCheck? _result;

  bool get _azure => widget.provider == TranslationProvider.azure;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final stored = await widget.secrets.read(widget.provider);
    if (!mounted) return;
    setState(() {
      _stored = stored;
      // La región y el endpoint sí vuelven: no son secretos, y tener que
      // reescribir `westeurope` cada vez que se cambia la clave es un paso
      // de más que además se equivoca.
      _region.text = stored.region;
      _endpoint.text = stored.endpoint;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _key.dispose();
    _region.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  /// Lo que hay ahora mismo entre lo guardado y lo escrito.
  Credentials get _current => Credentials(
    key: _key.text.trim().isEmpty ? _stored.key : _key.text.trim(),
    region: _region.text.trim(),
    endpoint: _endpoint.text.trim(),
  );

  @override
  Widget build(BuildContext context) {
    final id = widget.provider.id;
    final missing = _current.missing(widget.provider);

    return Container(
      key: Key('translation-$id'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border.all(color: context.palette.rule),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.provider.label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_loaded && !_stored.isEmpty)
                Text(
                  tr('guardada {0}', [_stored.hint]),
                  key: Key('translation-$id-stored'),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.palette.muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: Key('translation-$id-key'),
            controller: _key,
            obscureText: true,
            enabled: widget.secrets.canStoreSafely,
            onChanged: (_) => setState(() => _result = null),
            decoration: InputDecoration(
              labelText: tr('Clave de API'),
              isDense: true,
              hintText: _stored.isEmpty
                  ? null
                  : tr('Hay una guardada. Escribe otra para cambiarla.'),
            ),
          ),
          if (_azure) ...[
            const SizedBox(height: 8),
            TextField(
              key: Key('translation-$id-region'),
              controller: _region,
              enabled: widget.secrets.canStoreSafely,
              onChanged: (_) => setState(() => _result = null),
              decoration: InputDecoration(
                labelText: tr('Región'),
                hintText: 'westeurope',
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            key: Key('translation-$id-endpoint'),
            controller: _endpoint,
            enabled: widget.secrets.canStoreSafely,
            onChanged: (_) => setState(() => _result = null),
            decoration: InputDecoration(
              labelText: tr('Endpoint (opcional)'),
              hintText: tr('Solo si usas un recurso privado'),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (_result != null)
                Expanded(
                  child: Text(
                    _result!.message,
                    key: Key('translation-$id-result'),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: _result!.ok
                          ? context.palette.accentDark
                          : context.palette.ex,
                    ),
                  ),
                )
              else if (missing != null && !_current.isEmpty)
                Expanded(
                  child: Text(
                    missing,
                    style: TextStyle(fontSize: 11.5, color: context.palette.ex),
                  ),
                )
              else
                const Spacer(),
              if (!_stored.isEmpty)
                TextButton(
                  key: Key('translation-$id-clear'),
                  onPressed: _busy ? null : _clear,
                  child: Text(tr('Quitar')),
                ),
              TextButton(
                key: Key('translation-$id-test'),
                onPressed: _busy || !_current.complete(widget.provider)
                    ? null
                    : _test,
                child: Text(tr('Probar')),
              ),
              const SizedBox(width: 4),
              FilledButton(
                key: Key('translation-$id-save'),
                onPressed:
                    _busy ||
                        !widget.secrets.canStoreSafely ||
                        !_current.complete(widget.provider)
                    ? null
                    : _save,
                child: Text(tr('Guardar')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.secrets.write(widget.provider, _current);
      _key.clear();
      await _load();
      messenger.showSnackBar(
        SnackBar(content: Text(tr('{0}: guardada.', [widget.provider.label]))),
      );
    } catch (error) {
      showProblemIn(messenger, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    await widget.secrets.clear(widget.provider);
    _key.clear();
    await _load();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = null;
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(tr('{0}: quitada del llavero.', [widget.provider.label])),
      ),
    );
  }

  /// Prueba la credencial que hay delante, sin guardarla.
  ///
  /// Sin guardarla a propósito: probar una clave que acabas de pegar y que
  /// resulta estar mal no tiene por qué dejarla puesta.
  Future<void> _test() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final translator = translatorFor(widget.provider, _current);
    final result =
        await translator?.check() ??
        ProviderCheck(ok: false, message: tr('Falta algo por rellenar.'));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
  }
}

/// Apertium: sin clave, así que es un interruptor.
///
/// Apagado de salida, como todo lo opcional: manda el texto a un servidor
/// público, y eso lo decide quien traduce. Encendido, es la forma de sacar
/// valenciano de verdad --«seua», «duració»-- y no catalán central, que es
/// lo que dan Google y Azure; y no cuesta nada.
class _ApertiumCard extends StatefulWidget {
  const _ApertiumCard({required this.secrets});

  final TranslationSecrets secrets;

  @override
  State<_ApertiumCard> createState() => _ApertiumCardState();
}

class _ApertiumCardState extends State<_ApertiumCard> {
  static const TranslationProvider _provider = TranslationProvider.apertium;
  final _endpoint = TextEditingController();
  bool _on = false;
  bool _loaded = false;
  bool _busy = false;
  ProviderCheck? _result;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final stored = await widget.secrets.read(_provider);
    if (!mounted) return;
    setState(() {
      _on = stored.complete(_provider);
      _endpoint.text = stored.endpoint;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _endpoint.dispose();
    super.dispose();
  }

  Credentials get _current =>
      Credentials(key: 'on', endpoint: _endpoint.text.trim());

  Future<void> _set(bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      if (on) {
        await widget.secrets.write(_provider, _current);
      } else {
        await widget.secrets.clear(_provider);
      }
      await _load();
    } catch (error) {
      showProblemIn(messenger, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final result =
        await translatorFor(_provider, _current)?.check() ??
        ProviderCheck(ok: false, message: tr('No se ha podido probar.'));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    key: const Key('translation-apertium'),
    padding: const EdgeInsets.only(bottom: 10),
    // Un Material y no un Container con color: el interruptor pinta su
    // fondo y su onda en el Material que tenga debajo.
    child: Material(
      color: context.palette.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.palette.rule),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const Key('translation-apertium-on'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _on,
              onChanged: !_loaded || _busy || !widget.secrets.canStoreSafely
                  ? null
                  : _set,
              title: Text(
                tr('Traducir el valenciano con Apertium'),
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                tr(
                  'Gratuito y sin clave, y con la variante valenciana: «seua», '
                  '«duració». Traduce menos idiomas que los otros dos --el '
                  'castellano, el valenciano, el catalán, el gallego, el inglés, el '
                  'francés, el italiano y el portugués, en unos pares--, y el texto '
                  'va a su servidor público.',
                ),
                style: TextStyle(fontSize: 11.5, height: 1.4),
              ),
            ),
            if (_on) ...[
              const SizedBox(height: 4),
              TextField(
                key: const Key('translation-apertium-endpoint'),
                controller: _endpoint,
                onChanged: (_) => setState(() => _result = null),
                onSubmitted: (_) => _set(true),
                decoration: InputDecoration(
                  labelText: tr('Servidor (opcional)'),
                  hintText: tr('https://apertium.org/apy, o el tuyo'),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  Expanded(
                    child: _result == null
                        ? const SizedBox.shrink()
                        : Text(
                            _result!.message,
                            key: const Key('translation-apertium-result'),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: _result!.ok
                                  ? context.palette.accentDark
                                  : context.palette.ex,
                            ),
                          ),
                  ),
                  TextButton(
                    key: const Key('translation-apertium-save'),
                    onPressed: _busy ? null : () => _set(true),
                    child: Text(tr('Guardar el servidor')),
                  ),
                  TextButton(
                    key: const Key('translation-apertium-test'),
                    onPressed: _busy ? null : _test,
                    child: Text(tr('Probar')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
