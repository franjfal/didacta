/* El montaje de un vídeo, escrito en su guion.
 *
 * El A1 y el A2 tienen su propio `escenas.js`, escrito a mano. La mayoría de
 * los vídeos no lo necesitan: enseñan una pantalla de la aplicación y, al
 * decir una palabra, se acercan a una zona, la señalan o la pulsan. Eso se
 * escribe en el propio `guion.yaml`, junto a la frase, y lo pinta esto:
 *
 *     escenas:
 *       - id: buscar
 *         capitulo: Buscar
 *         pantalla: biblioteca            # la captura que se ve
 *         frases:
 *           - id: escribe
 *             texto: Escribe en el buscador y la lista se aplana.
 *             pasos:
 *               - {en: buscador, enfoca: buscador}
 *               - {en: buscador, pulsa: buscador}
 *               - {en: aplana, cambia: biblioteca-buscando}
 *               - {en: lista, resalta: resultados, etiqueta: Todo lo que lo nombra}
 *
 * Una escena sin pantalla puede ser un gráfico (`grafico:`, ver abajo). La
 * apertura y el cierre salen solos, iguales en todos los vídeos. Si un vídeo
 * necesita algo más, su `escenas.js` llama a `Recorrido.montar(E, G, D,
 * {escena: (ctx) => …})` y añade lo suyo.
 *
 * Como en el resto del estudio, ningún tiempo se escribe a mano: cada paso
 * cuelga de una palabra de su frase (`en:`), o de su principio o su final
 * (`al: fin`), con un ajuste fino si hace falta (`mas: 0.3`).
 */
(function () {
  'use strict';

  const COLORES = {
    verde: '#346e34',
    azul: '#2d5fa0',
    diapositivas: '#2d5fa0',
    apuntes: '#3c876e',
    profesor: '#aa4b4b',
    rojo: '#aa4b4b',
    ambar: '#be8237',
    gris: '#62697a',
  };
  const color = (c) => COLORES[c] || c || COLORES.verde;

  // Iconos sencillos, de trazo, para los gráficos.
  const TRAZO = (d) => `<svg viewBox="0 0 24 24" width="100%" height="100%" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
  const ICONOS = {
    diapositivas: TRAZO('<rect x="3" y="4" width="18" height="13" rx="2"/><path d="M10 8.5l4 2.5-4 2.5z" fill="currentColor"/><path d="M8 21h8"/>'),
    apuntes: TRAZO('<path d="M6 3h9l4 4v14H6z"/><path d="M9 11h7M9 15h7M9 7h3"/>'),
    profesor: TRAZO('<path d="M2 9l10-5 10 5-10 5z"/><path d="M6 11v5c3 2.5 9 2.5 12 0v-5"/>'),
    hoja: TRAZO('<path d="M9 6h11M9 12h11M9 18h11"/><circle cx="4.5" cy="6" r="1.2" fill="currentColor"/><circle cx="4.5" cy="12" r="1.2" fill="currentColor"/><circle cx="4.5" cy="18" r="1.2" fill="currentColor"/>'),
    examen: TRAZO('<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 12l3 3 5-6"/>'),
    libro: TRAZO('<path d="M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2z"/><path d="M4 19V5M8 7h7"/>'),
    carpeta: TRAZO('<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>'),
    leccion: TRAZO('<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 8h6M9 12h6M9 16h3"/>'),
    curso: TRAZO('<rect x="3" y="5" width="18" height="15" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>'),
    github: TRAZO('<path d="M9 19c-4 1.3-4-2-6-2.5M15 21v-3.4a3 3 0 0 0-.8-2.3c2.7-.3 5.6-1.3 5.6-6a4.7 4.7 0 0 0-1.3-3.2 4.3 4.3 0 0 0-.1-3.2s-1-.3-3.4 1.3a11.6 11.6 0 0 0-6 0C6.6 2.6 5.6 2.9 5.6 2.9a4.3 4.3 0 0 0-.1 3.2 4.7 4.7 0 0 0-1.3 3.2c0 4.6 2.8 5.6 5.5 6a3 3 0 0 0-.8 2.3V21"/>'),
    nube: TRAZO('<path d="M7 18a4.5 4.5 0 0 1-.6-9A6 6 0 0 1 18 8a4.5 4.5 0 0 1-.5 10z"/>'),
    ordenador: TRAZO('<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/>'),
    candado: TRAZO('<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>'),
    idioma: TRAZO('<path d="M4 5h9M8.5 3v2M6 5c.5 3 3 6 6 7M11 5c-.5 3-3 6-6 7"/><path d="M13 21l4-9 4 9M14.5 18h5"/>'),
    lupa: TRAZO('<circle cx="11" cy="11" r="6.5"/><path d="M16 16l5 5"/>'),
    reloj: TRAZO('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'),
    historial: TRAZO('<path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5M12 7v5l3 2"/>'),
    ok: TRAZO('<circle cx="12" cy="12" r="9"/><path d="M8 12.5l2.8 2.8L16 9.5"/>'),
    no: TRAZO('<circle cx="12" cy="12" r="9"/><path d="M9 9l6 6M15 9l-6 6"/>'),
    escudo: TRAZO('<path d="M12 2l8 3v6c0 5-3.4 9.4-8 11-4.6-1.6-8-6-8-11V5z"/><path d="M8.5 12l2.5 2.5 4.5-5"/>'),
    rayo: TRAZO('<path d="M13 2L4 14h7l-1 8 9-12h-7z"/>'),
    lapiz: TRAZO('<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="M13.5 6.5l4 4"/>'),
    enlace: TRAZO('<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>'),
    copia: TRAZO('<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>'),
    ojo: TRAZO('<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>'),
    filtro: TRAZO('<path d="M3 5h18l-7 8v6l-4-2v-4z"/>'),
    engranaje: TRAZO('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>'),
    flecha: TRAZO('<path d="M5 12h14M13 6l6 6-6 6"/>'),
    subir: TRAZO('<path d="M12 19V5M6 11l6-6 6 6"/>'),
    bajar: TRAZO('<path d="M12 5v14M6 13l6 6 6-6"/>'),
    papelera: TRAZO('<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>'),
    aviso: TRAZO('<path d="M12 3l10 18H2z"/><path d="M12 10v5M12 18v.5"/>'),
    persona: TRAZO('<circle cx="12" cy="8" r="4"/><path d="M4 21c1-4 4-6 8-6s7 2 8 6"/>'),
    grupo: TRAZO('<circle cx="9" cy="8" r="3.5"/><path d="M2 20c.8-3.3 3.3-5 7-5s6.2 1.7 7 5"/><circle cx="17" cy="9" r="2.8"/><path d="M17 14c2.6 0 4.3 1.3 5 4"/>'),
    teclado: TRAZO('<rect x="2" y="6" width="20" height="12" rx="2"/><path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M7 14h10"/>'),
    paleta: TRAZO('<path d="M12 3a9 9 0 1 0 0 18c1 0 1.5-.8 1.5-1.6 0-.9-.6-1.4-.6-2.3 0-1 .8-1.6 1.8-1.6H17a4 4 0 0 0 4-4c0-4.7-4-8.5-9-8.5z"/><circle cx="7.5" cy="11" r="1.1" fill="currentColor"/><circle cx="10" cy="7" r="1.1" fill="currentColor"/><circle cx="15" cy="7.5" r="1.1" fill="currentColor"/>'),
    zip: TRAZO('<path d="M6 3h9l4 4v14H6z"/><path d="M11 3v2M11 7v2M11 11v2M10 15h2v3h-2z"/>'),
    terminal: TRAZO('<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 9l3 3-3 3M13 15h4"/>'),
    ia: TRAZO('<path d="M12 3l1.8 4.7L18.5 9.5l-4.7 1.8L12 16l-1.8-4.7L5.5 9.5l4.7-1.8z"/><path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z"/>'),
    congelar: TRAZO('<path d="M12 2v20M4 6l16 12M20 6L4 18"/>'),
    moodle: TRAZO('<path d="M3 10l9-5 9 5-9 5z"/><path d="M7 12v4c3 2 7 2 10 0v-4M21 10v5"/>'),
  };
  const icono = (n) => ICONOS[n] || ICONOS.leccion;

  function montar(E, G, D, extra = {}) {
    const { W, H, nodo, anim, tarea, sonido } = E;
    const V = D.video;
    const guion = D.guion || { escenas: [] };
    const porId = {};
    for (const e of guion.escenas) {
      porId[e.id] = e;
      for (const f of e.frases) porId[`frase:${f.id}`] = f;
    }

    // -------------------------------------------------------- utilidades --

    const capa = (z = 10, padre) => nodo({ padre, clase: 'capa', estilo: { width: `${W}px`, height: `${H}px`, zIndex: z } });
    const visible = (n, ini, fin, entra = 0.45, sale = 0.4) =>
      anim(n, [
        [ini, { o: 0 }],
        [ini + entra, { o: 1 }, 'sale'],
        [fin - sale, { o: 1 }],
        [fin, { o: 0 }, 'suave'],
      ]);
    const entra = (n, t, o = {}) =>
      anim(n, [
        [t, { o: 0, y: o.dy ?? 36, blur: o.blur ?? 8, s: o.s ?? 1 }],
        [t + (o.dur ?? 0.65), { o: 1, y: 0, blur: 0, s: 1 }, o.curva || 'sale4'],
      ]);
    const sale = (n, t, o = {}) =>
      anim(n, [
        [t, { o: 1, y: 0, blur: 0 }],
        [t + (o.dur ?? 0.45), { o: 0, y: o.dy ?? -26, blur: o.blur ?? 6 }, 'entra'],
      ]);
    const centrado = (html, top, estilo = {}, padre, clase = '') =>
      nodo({ padre, clase, html, estilo: { position: 'absolute', left: 0, width: `${W}px`, top: `${top}px`, textAlign: 'center', ...estilo } });
    const union = (rs) => {
      const x = Math.min(...rs.map((r) => r.x));
      const y = Math.min(...rs.map((r) => r.y));
      return { x, y, w: Math.max(...rs.map((r) => r.x + r.w)) - x, h: Math.max(...rs.map((r) => r.y + r.h)) - y };
    };
    const lista = (v) => (v == null ? [] : Array.isArray(v) ? v : [v]);

    /** El segundo en que pasa un paso de una frase. */
    const cuando = (frase, p) => {
      const f = G.frase(frase.id);
      let t;
      if (p.en) t = G.palabra(frase.id, p.en, { fin: p.al === 'fin', n: p.n || 0 });
      else t = p.al === 'fin' ? f.fin : f.ini;
      return t + (p.mas || 0);
    };
    /** Hasta cuándo dura lo que un paso pone en pantalla. */
    const hastaDe = (escena, frase, p, t) => {
      const e = G.escena(escena.id);
      const f = G.frase(frase.id);
      if (p.hasta === 'escena') return e.fin - 0.3;
      if (p.hasta === 'grupo') return null;
      if (typeof p.hasta === 'number') return t + p.hasta;
      if (typeof p.hasta === 'string' && porId[`frase:${p.hasta}`]) return G.frase(p.hasta).fin + 0.2;
      return Math.min(f.fin + 0.35, e.fin - 0.2);
    };
    /** Una palabra en cualquiera de las frases de una escena. */
    const palabraEnEscena = (escena, palabra, o = {}) => {
      const sinTildes = (s) => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
      const frase = escena.frases.find((f) => sinTildes(f.texto).includes(sinTildes(palabra))) || escena.frases[0];
      return G.palabra(frase.id, palabra, o);
    };
    const tDe = (escena, item, porDefecto) => {
      if (item.en) return palabraEnEscena(escena, item.en) + (item.mas || 0);
      if (item.frase) return G.frase(item.frase).ini + (item.mas || 0);
      return porDefecto;
    };

    // ------------------------------------------------------------- fondo --

    nodo({ clase: 'fondo' });
    nodo({ clase: 'reticula' });
    for (const e of G.escenas) {
      if (!e.capitulo) continue;
      const chip = nodo({ clase: 'capitulo', html: `<span class="numero">${e.numero}</span>${e.capitulo}`, estilo: { left: '60px', top: '48px', zIndex: 50 } });
      const hasta = Math.min(e.ini + 3.4, e.fin - 0.3);
      anim(chip, [
        [e.ini + 0.1, { o: 0, x: -16 }],
        [e.ini + 0.6, { o: 1, x: 0 }, 'sale4'],
        [hasta, { o: 1, x: 0 }],
        [hasta + 0.5, { o: 0, x: -10 }, 'suave'],
      ]);
      sonido(e.ini, 'soplo', 0.8);
    }
    const progreso = nodo({ clase: 'progreso', estilo: { width: `${W}px`, zIndex: 60 } });
    tarea((t) => {
      progreso.style.transform = `scaleX(${Math.min(1, t / G.total)})`;
    });

    // ---------------------------------------------------------- apertura --

    function apertura(escena) {
      const a = G.escena(escena.id);
      const g = capa();
      const m = E.marca({ tam: 190, x: W / 2 - 95, y: 196, padre: g });
      m.baldosa.style.transformBox = 'fill-box';
      m.baldosa.style.transformOrigin = '50% 50%';
      anim(m.baldosa, [
        [a.ini + 0.1, { o: 0, s: 0.5 }],
        [a.ini + 0.75, { o: 1, s: 1 }, 'rebote'],
      ]);
      m.hojas.forEach((h, i) =>
        anim(h, [
          [a.ini + 0.35 + 0.1 * i, { o: 0, x: -8, y: 10 }],
          [a.ini + 0.85 + 0.1 * i, { o: 1, x: 0, y: 0 }, 'sale4'],
        ]),
      );
      const ante = centrado(`${V.codigo} · ${V.ruta}`, 452, {}, g, 'antetitulo');
      entra(ante, a.ini + 0.8, { dy: 16 });
      const largo = V.titulo.length;
      const tam = largo > 34 ? 76 : largo > 26 ? 90 : 112;
      const titulo = centrado('', 502 + (112 - tam) / 2, { fontSize: `${tam}px`, padding: '0 80px', boxSizing: 'border-box' }, g, 'titular');
      titulo.textContent = V.titulo;
      E.palabras(titulo, a.ini + 0.95, { paso: 0.08, dy: 40 });
      const sub = centrado(V.subtitulo || '', 650, { fontSize: '40px' }, g, 'entradilla');
      entra(sub, a.ini + 1.55, { dy: 20 });
      if (escena.promesa) {
        const p = escena.promesa;
        const chip = centrado(`<span class="chip" style="font-size:26px"><span class="punto"></span>${p.texto || p}</span>`, 758, {}, g);
        const t = p.en ? palabraEnEscena(escena, p.en) - 0.4 : a.ini + 2.4;
        entra(chip, t, { dy: 18, curva: 'rebote' });
      }
      sale(g, a.fin - 0.5, { dur: 0.5, dy: -30 });
    }

    // ------------------------------------------------------------ cierre --

    function cierre(escena) {
      const z = G.escena(escena.id);
      const g = capa();
      const m = E.marca({ tam: 150, x: W / 2 - 75, y: 200, padre: g });
      m.baldosa.style.transformBox = 'fill-box';
      m.baldosa.style.transformOrigin = '50% 50%';
      anim(m.baldosa, [[z.ini, { o: 0, s: 0.6 }], [z.ini + 0.6, { o: 1, s: 1 }, 'rebote']]);
      m.hojas.forEach((h, i) => anim(h, [[z.ini + 0.2 + 0.08 * i, { o: 0, x: -6, y: 8 }], [z.ini + 0.7 + 0.08 * i, { o: 1, x: 0, y: 0 }, 'sale4']]));
      const [uno, dos] = lista(guion.lema);
      const tLema = porId['frase:lema'] ? G.frase('lema').ini : z.ini + 0.4;
      const larga = Math.max((uno || '').length, (dos || '').length);
      const tam = larga > 38 ? 68 : larga > 30 ? 80 : 88;
      if (uno) {
        const l1 = centrado('', 420, { fontSize: `${tam}px` }, g, 'titular');
        l1.textContent = uno;
        E.palabras(l1, tLema - 0.15, { paso: 0.08 });
      }
      if (dos) {
        const l2 = centrado('', 420 + tam * 1.1, { fontSize: `${tam}px`, color: 'var(--verde-oscuro)' }, g, 'titular');
        l2.textContent = dos;
        const t2 = porId['frase:lema'] && guion.lema_en ? G.palabra('lema', guion.lema_en) - 0.25 : tLema + 0.9;
        E.palabras(l2, t2, { paso: 0.09 });
      }
      const tSig = porId['frase:siguiente'] ? G.frase('siguiente').ini : z.ini + 2;
      if (V.siguiente) {
        const sig = centrado(`<span class="chip" style="font-size:30px;padding:14px 26px 14px 20px"><span class="punto" style="background:var(--verde-oscuro)"></span>Siguiente&nbsp;&nbsp;<b>${V.siguiente}</b></span>`, 700, {}, g);
        entra(sig, tSig - 0.1, { dy: 20 });
      }
      const url = centrado('franjfal.github.io/didacta', 812, { fontSize: '26px', fontWeight: 600, color: 'var(--apagado)', letterSpacing: '0.01em' }, g);
      entra(url, tSig + 0.5, { dy: 10 });
      visible(g, z.ini, G.total + 1, 0.3, 0.01);
    }

    // --------------------------------------------------------- pantallas --

    /** Varias escenas seguidas con la misma pantalla comparten ventana,
     * cámara y puntero: se pasa de una a otra sin cortar. */
    function pantallas(escenas) {
      const primera = G.escena(escenas[0].id);
      const ultima = G.escena(escenas[escenas.length - 1].id);
      const conf = escenas[0].ventana || {};
      const nombre = escenas[0].pantalla;
      const cap = D.capturas[nombre];
      if (!cap) throw new Error(`no hay captura «${nombre}»`);
      const ancho = conf.ancho || 1500;
      const barra = cap.direccion ? 52 : 36;
      const alto = (cap.alto * ancho) / cap.ancho + barra;
      const x = conf.x ?? (W - ancho) / 2;
      const y = conf.y ?? Math.max(40, (H - alto) / 2);
      const g = capa();
      const cam = E.camara(g, { x, y, w: ancho, h: alto });
      const v = E.ventana({ captura: nombre, x, y, ancho, padre: g, camara: cam });
      anim(v.raiz, [
        [primera.ini, { o: 0, y: 50, s: 0.97 }],
        [primera.ini + 0.7, { o: 1, y: 0, s: 1 }, 'sale4'],
      ]);
      visible(g, primera.ini, ultima.fin + 0.05, 0.3, 0.4);

      let cursor = null;
      const puntero = (t) => {
        if (!cursor) {
          cursor = E.cursor(v, { padre: g, desde: { x: x + ancho * 0.72, y: y + alto * 0.9, lienzo: true } });
          cursor.mostrar(t - 1.1, ultima.fin - 0.2);
        }
        return cursor;
      };
      const zonaDe = (z, p) => (typeof z === 'string' ? z : null) && z;

      const ctx = { E, G, D, v, cam, g, escenas, cuando, hastaDe, palabraEnEscena };
      // La captura que se ve en cada momento: los pasos se escriben en orden,
      // así que es la última que ha puesto un `cambia`. Cada paso se queda con
      // la suya; si no, un recuadro buscaría su zona en la que se ve al final.
      let actual = nombre;
      for (const escena of escenas) {
        for (const frase of escena.frases) {
          for (const p0 of frase.pasos || []) {
            const t = cuando(frase, p0);
            if (p0.cambia) {
              v.cambiar(t, p0.cambia, p0.funde ?? 0.35);
              actual = p0.cambia;
            }
            const p = { ...p0, captura: p0.captura || actual };
            const hasta = hastaDe(escena, frase, p, t) ?? ultima.fin - 0.3;
            if (p.enfoca) {
              const r = union(lista(p.enfoca).map((z) => v.zona(z, p.captura)));
              cam.enfocar(t - (p.antes ?? 0.5), t + (p.dura ?? 0.8), r, { margen: p.margen ?? 0.12, max: p.max ?? 2.0, dx: p.dx || 0, dy: p.dy || 0 });
            }
            if (p.reposo) cam.reposo(t - 0.3, t + 0.9);
            if (p.pulsa) {
              const c = puntero(t);
              const destino = { zona: p.pulsa, captura: p.captura, ax: p.ax, ay: p.ay };
              c.ir(t - (p.viaje ?? 0.9), t - 0.05, destino);
              c.clic(t);
              if (p.doble) c.clic(t + 0.2);
            }
            if (p.apunta) {
              const c = puntero(t);
              c.ir(t - (p.viaje ?? 0.9), t, { zona: p.apunta, captura: p.captura, ax: p.ax, ay: p.ay });
            }
            if (p.resalta) {
              for (const z of lista(p.resalta)) {
                E.resaltar(v, zonaDe(z, p), {
                  t0: t - 0.1,
                  t1: hasta,
                  etiqueta: z === lista(p.resalta)[0] ? p.etiqueta : undefined,
                  lado: p.lado || 'abajo',
                  alinear: p.alinear,
                  color: color(p.color),
                  pad: p.pad ?? 6,
                  foco: !!p.foco,
                  captura: p.captura,
                  discontinuo: !!p.discontinuo,
                });
              }
            }
            if (p.rotulo) rotulo(p.rotulo, t, hasta, p);
            if (p.teclas) teclas(p.teclas, t, hasta);
          }
        }
        if (extra[escena.id]) extra[escena.id]({ ...ctx, escena });
      }
    }

    /** Un rótulo abajo, en el centro, sobre lo que haya. */
    function rotulo(texto, t0, t1, p = {}) {
      const g = capa(48);
      const r = centrado(`<span class="etiqueta" style="position:relative;display:inline-flex;--color:${color(p.color)};font-size:30px;padding:14px 24px">${texto}</span>`, p.arriba ? 120 : H - 150, {}, g);
      anim(r, [
        [t0, { o: 0, y: 16 }],
        [t0 + 0.4, { o: 1, y: 0 }, 'sale4'],
        [t1, { o: 1, y: 0 }],
        [t1 + 0.35, { o: 0, y: 8 }],
      ]);
    }

    /** Un atajo de teclado, con sus teclas. */
    function teclas(texto, t0, t1) {
      const g = capa(48);
      const cajas = texto
        .split(/\s+/)
        .map((k) => `<span style="display:inline-grid;place-items:center;min-width:74px;height:74px;padding:0 18px;margin:0 6px;border-radius:14px;background:#fff;box-shadow:0 0 0 1px rgba(28,31,38,.14),0 6px 0 rgba(28,31,38,.12),0 16px 30px rgba(28,31,38,.18);font-size:36px;font-weight:700;color:var(--tinta)">${k}</span>`)
        .join('<span style="font-size:32px;color:var(--apagado);font-weight:700">+</span>');
      const r = centrado(cajas, H - 190, {}, g);
      anim(r, [
        [t0, { o: 0, s: 0.9 }],
        [t0 + 0.35, { o: 1, s: 1 }, 'rebote'],
        [t1, { o: 1 }],
        [t1 + 0.3, { o: 0 }],
      ]);
    }

    // ---------------------------------------------------------- gráficos --

    function tarjetaHtml(item, ancho) {
      const c = color(item.color);
      const ic = item.icono ? `<div style="width:64px;height:64px;border-radius:16px;display:grid;place-items:center;background:color-mix(in srgb, ${c} 13%, #fff);color:${c};margin-bottom:22px"><div style="width:36px;height:36px">${icono(item.icono)}</div></div>` : '';
      return `<div style="width:${ancho}px;box-sizing:border-box;padding:34px 34px 36px;border-radius:24px;background:#fff;box-shadow:0 0 0 1px rgba(28,31,38,.06),0 18px 44px -12px rgba(28,31,38,.22)">${ic}<div style="font-size:32px;font-weight:800;letter-spacing:-.01em;line-height:1.15">${item.titulo || ''}</div>${item.texto ? `<div style="margin-top:14px;font-size:23px;line-height:1.45;color:var(--apagado)">${item.texto}</div>` : ''}</div>`;
    }

    function grafico(escena) {
      const e = G.escena(escena.id);
      const gr = escena.grafico;
      const g = capa();
      const tipo = gr.tipo || 'puntos';
      let arriba = 150;
      if (gr.titulo) {
        const tit = centrado('', 150, { fontSize: `${gr.tam || 64}px`, padding: '0 120px', boxSizing: 'border-box' }, g, 'titular');
        tit.textContent = gr.titulo;
        const t = gr.titulo_en ? palabraEnEscena(escena, gr.titulo_en) - 0.3 : e.ini + 0.3;
        E.palabras(tit, t, { paso: 0.07, dy: 30 });
        arriba = 150 + (gr.tam || 64) * 1.2 + 60;
      }
      if (gr.sub) {
        const sub = centrado(gr.sub, arriba - 30, { fontSize: '30px' }, g, 'entradilla');
        entra(sub, e.ini + 0.7, { dy: 16 });
        arriba += 50;
      }

      if (tipo === 'frase') {
        // Una idea en grande: dos líneas, la segunda en verde.
        const l1 = centrado('', 380, { fontSize: `${gr.tam || 92}px`, padding: '0 120px', boxSizing: 'border-box' }, g, 'titular');
        l1.textContent = gr.uno;
        E.palabras(l1, tDe(escena, gr, e.ini + 0.3) - 0.2, { paso: 0.08 });
        if (gr.dos) {
          const l2 = centrado('', 380 + (gr.tam || 92) * 1.12, { fontSize: `${gr.tam || 92}px`, color: 'var(--verde-oscuro)', padding: '0 120px', boxSizing: 'border-box' }, g, 'titular');
          l2.textContent = gr.dos;
          E.palabras(l2, tDe(escena, { en: gr.dos_en }, e.ini + 1.4) - 0.2, { paso: 0.09 });
        }
      }

      if (tipo === 'puntos') {
        const items = gr.items || [];
        const n = items.length;
        const porFila = gr.por_fila || (n <= 3 ? n : n === 4 ? 4 : 3);
        const hueco = 36;
        const ancho = Math.min(gr.ancho || 460, (W - 240 - hueco * (porFila - 1)) / porFila);
        const filas = Math.ceil(n / porFila);
        items.forEach((it, i) => {
          const fila = Math.floor(i / porFila);
          const col = i % porFila;
          const enFila = Math.min(porFila, n - fila * porFila);
          const x0 = (W - (enFila * ancho + (enFila - 1) * hueco)) / 2;
          const alturaFila = gr.alto_fila || (filas > 1 ? 330 : 380);
          const bloque = filas * alturaFila + (filas - 1) * 36;
          const y0 = Math.max(arriba + 30, (H - bloque) / 2 + 40);
          const y = y0 + fila * (alturaFila + 36);
          const card = nodo({ padre: g, clase: 'abs', html: tarjetaHtml(it, ancho), estilo: { left: `${x0 + col * (ancho + hueco)}px`, top: `${y}px` } });
          entra(card, tDe(escena, it, e.ini + 0.4 + 0.25 * i) - 0.25, { dy: 40, curva: 'sale4' });
        });
      }

      if (tipo === 'comparar') {
        const lados = [gr.izquierda, gr.derecha];
        const ancho = 700;
        lados.forEach((it, k) => {
          const marca = it.ok === true ? 'ok' : it.ok === false ? 'no' : null;
          const card = nodo({
            padre: g,
            clase: 'abs',
            html: tarjetaHtml({ ...it, icono: it.icono || marca, color: it.color || (it.ok === false ? 'rojo' : 'verde') }, ancho),
            estilo: { left: `${W / 2 - ancho - 30 + k * (ancho + 60)}px`, top: `${Math.max(arriba + 40, (H - 330) / 2 + 50)}px` },
          });
          entra(card, tDe(escena, it, e.ini + 0.5 + 0.8 * k) - 0.25, { dy: 40 });
        });
      }

      if (tipo === 'flujo') {
        // Una cosa a la izquierda y lo que sale de ella a la derecha.
        const o = gr.origen;
        const destinos = gr.destinos || [];
        const oy = arriba + 60 + Math.max(0, (destinos.length * 112 - 300) / 2);
        const origen = nodo({ padre: g, clase: 'leccion-madre', html: `<div class="antetitulo" style="font-size:18px">${o.ante || ''}</div><div style="font-size:40px;font-weight:800;letter-spacing:-.02em;line-height:1.08;margin-top:10px">${o.titulo}</div>${o.sub ? `<div class="mono" style="margin-top:14px;font-size:19px;color:var(--apagado)">${o.sub}</div>` : ''}`, estilo: { left: '300px', top: `${oy}px` } });
        entra(origen, tDe(escena, o, e.ini + 0.3) - 0.2, { dy: 30 });
        const svg = nodo({ svg: true, tag: 'svg', padre: g, attrs: { width: W, height: H }, estilo: { position: 'absolute', left: 0, top: 0 } });
        destinos.forEach((d, i) => {
          const y = arriba + 40 + i * 112;
          const c = color(d.color);
          const card = nodo({ padre: g, clase: 'salida', html: `<span class="icono" style="--color:${c}"><span style="width:28px;height:28px;display:block">${icono(d.icono)}</span></span>${d.titulo}`, estilo: { left: `${1200}px`, top: `${y}px`, '--color': c } });
          card.style.setProperty('--color', c);
          const t = tDe(escena, d, e.ini + 1 + 0.3 * i);
          const x1 = 760;
          const y1 = oy + 150;
          const x2 = 1200;
          const y2 = y + 46;
          const path = nodo({ svg: true, tag: 'path', padre: svg, attrs: { d: `M${x1},${y1} C${x1 + 220},${y1} ${x2 - 220},${y2} ${x2},${y2}`, fill: 'none', stroke: c, 'stroke-width': 3, 'stroke-opacity': 0.55 } });
          anim(path, [[t - 0.3, { trazo: 0 }], [t + 0.3, { trazo: 1 }, 'sale']]);
          entra(card, t, { dy: 0, blur: 6 });
          anim(card, [[t, { x: -30 }], [t + 0.6, { x: 0 }, 'sale4']]);
        });
      }

      if (tipo === 'pdfs') {
        const hojas = gr.hojas || [];
        const n = hojas.length;
        const hueco = 50;
        const ancho = gr.ancho || Math.min(820, (W - 220 - hueco * (n - 1)) / n);
        const x0 = (W - (n * ancho + (n - 1) * hueco)) / 2;
        hojas.forEach((h, i) => {
          // `desde_zona`: la página empieza un poco antes de esa zona, para
          // enseñar solo el ejercicio que interesa.
          let desde = h.desde;
          if (h.desde_zona) {
            const z = D.pdf[h.pdf].zonas[h.desde_zona];
            if (!z) throw new Error(`no hay zona «${h.desde_zona}» en ${h.pdf}`);
            desde = z[1] - (h.margen ?? 60);
          }
          let izquierda = h.izquierda || 0;
          if (h.izquierda_zona) izquierda = D.pdf[h.pdf].zonas[h.izquierda_zona][0] - (h.margen_x ?? 30);
          const p = E.hoja({ pdf: h.pdf, x: x0 + i * (ancho + hueco), y: arriba + 90, ancho, alto: h.alto, desde, zoom: h.zoom, izquierda, padre: g });
          const t = tDe(escena, h, e.ini + 0.4 + 0.3 * i);
          anim(p.raiz, [
            [t - 0.2, { o: 0, y: 70 }],
            [t + 0.5, { o: 1, y: 0 }, 'sale4'],
          ]);
          if (h.rotulo) {
            const r = nodo({ padre: g, clase: 'rotulo-hoja', html: `<span style="display:inline-block;width:14px;height:14px;border-radius:50%;background:${color(h.color)};margin-right:12px;vertical-align:2px"></span>${h.rotulo}`, estilo: { left: `${p.x}px`, top: `${p.y - 56}px` } });
            entra(r, t, { dy: 12 });
          }
          for (const m of lista(h.resalta)) {
            E.resaltar(p, m.zona, { t0: tDe(escena, m, t + 1), t1: e.fin - 0.3, etiqueta: m.etiqueta, lado: m.lado || 'abajo', color: color(m.color), pad: 4, padre: g });
          }
        });
      }

      if (tipo === 'arbol' || tipo === 'pasos') {
        const lineas = gr.lineas || [];
        const x0 = gr.x || (tipo === 'arbol' ? 560 : 420);
        const paso = tipo === 'arbol' ? 74 : 92;
        const y0 = Math.max(arriba + 30, (H - lineas.length * paso) / 2 + 50);
        lineas.forEach((l, i) => {
          const sangria = (l.nivel || 0) * 56;
          const html =
            tipo === 'arbol'
              ? `<span class="mono" style="font-size:34px;font-weight:600">${l.nivel ? '<span style="color:var(--tenue)">└─ </span>' : ''}${l.texto}</span>${l.nota ? `<span style="margin-left:26px;font-size:25px;color:var(--apagado)">${l.nota}</span>` : ''}`
              : `<span style="display:inline-grid;place-items:center;width:52px;height:52px;border-radius:50%;background:var(--verde-oscuro);color:#fff;font-weight:800;font-size:26px;margin-right:24px">${i + 1}</span><span style="font-size:34px;font-weight:600">${l.texto}</span>`;
          const n = nodo({ padre: g, clase: 'abs', html, estilo: { left: `${x0 + sangria}px`, top: `${y0 + i * paso}px`, display: 'flex', alignItems: 'center', whiteSpace: 'nowrap' } });
          entra(n, tDe(escena, l, e.ini + 0.4 + 0.3 * i) - 0.2, { dy: 18 });
        });
      }

      visible(g, e.ini, e.fin + 0.05, 0.3, 0.4);
      if (extra[escena.id]) extra[escena.id]({ E, G, D, g, escena });
    }

    // -------------------------------------------------------------- todo --

    const escenas = guion.escenas;
    for (let i = 0; i < escenas.length; i += 1) {
      const escena = escenas[i];
      if (escena.id === 'apertura') apertura(escena);
      else if (escena.id === 'cierre') cierre(escena);
      else if (escena.pantalla) {
        const grupo = [escena];
        while (i + 1 < escenas.length && escenas[i + 1].pantalla === escena.pantalla && !escenas[i + 1].corta) grupo.push(escenas[(i += 1)]);
        pantallas(grupo);
      } else if (escena.grafico) grafico(escena);
      else if (extra[escena.id]) extra[escena.id]({ E, G, D, escena });
    }
    if (extra.todo) extra.todo({ E, G, D, capa, visible, entra, sale, centrado, rotulo, teclas, icono, color });
  }

  window.Recorrido = { montar, ICONOS, COLORES };
})();
