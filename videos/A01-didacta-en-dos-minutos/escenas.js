/* A1 · Didacta en dos minutos: el montaje.
 *
 * Qué se ve mientras se dice cada frase de `guion.yaml`. Ningún tiempo está
 * escrito a mano --todo sale de `G.frase()` y `G.palabra()`, que vienen de la
 * locución-- y ningún sitio de la pantalla tampoco: `v.zona('compilar')` es
 * donde el arnés de capturas encontró la pestaña en la versión de hoy.
 */
window.montaje = function (E, G, D) {
  const { W, H, nodo, anim, tarea, sonido } = E;
  const V = D.video;

  // ---------------------------------------------------------- utilidades --

  const capa = (z = 10) => nodo({ clase: 'capa', estilo: { width: `${W}px`, height: `${H}px`, zIndex: z } });

  /** Visible entre ini y fin, fundiendo en los bordes. */
  const visible = (n, ini, fin, entra = 0.45, sale = 0.4) =>
    anim(n, [
      [ini, { o: 0 }],
      [ini + entra, { o: 1 }, 'sale'],
      [fin - sale, { o: 1 }],
      [fin, { o: 0 }, 'suave'],
    ]);

  /** Entra subiendo y desenfocado; sale igual, hacia arriba. */
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

  const union = (...rs) => {
    const x = Math.min(...rs.map((r) => r.x));
    const y = Math.min(...rs.map((r) => r.y));
    return { x, y, w: Math.max(...rs.map((r) => r.x + r.w)) - x, h: Math.max(...rs.map((r) => r.y + r.h)) - y };
  };

  const centrado = (html, top, estilo = {}, padre) =>
    nodo({ padre, html, estilo: { position: 'absolute', left: 0, width: `${W}px`, top: `${top}px`, textAlign: 'center', ...estilo } });

  const icono = {
    diapositivas: '<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="13" rx="2"/><path d="M10 8.5l4 2.5-4 2.5z" fill="currentColor"/><path d="M8 21h8"/></svg>',
    apuntes: '<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 3h9l4 4v14H6z"/><path d="M9 11h7M9 15h7M9 7h3"/></svg>',
    profesor: '<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M2 9l10-5 10 5-10 5z"/><path d="M6 11v5c3 2.5 9 2.5 12 0v-5"/></svg>',
    hoja: '<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 6h11M9 12h11M9 18h11"/><circle cx="4.5" cy="6" r="1.2" fill="currentColor"/><circle cx="4.5" cy="12" r="1.2" fill="currentColor"/><circle cx="4.5" cy="18" r="1.2" fill="currentColor"/></svg>',
    examen: '<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 12l3 3 5-6"/></svg>',
  };

  // --------------------------------------------------------------- fondo --

  nodo({ clase: 'fondo' });
  nodo({ clase: 'reticula' });

  // Arriba a la izquierda, el capítulo: entra al empezar cada uno y se retira
  // a los pocos segundos, que encima de la aplicación con zoom estorba.
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
  }
  // La marca, arriba a la derecha, solo sobre las escenas gráficas: encima de
  // la aplicación estorba, y la aplicación ya lleva la suya en el carril.
  const tramosGraficos = [
    [G.escena('problema').ini + 0.2, G.escena('idea').fin],
    [G.palabra('compilar', 'salen') - 0.1, G.escena('salidas').fin],
    [G.frase('mismo-tema').ini, G.escena('idiomas').fin],
  ];
  for (const [desde, hasta] of tramosGraficos) {
    const bicho = nodo({ estilo: { position: 'absolute', right: '60px', top: '48px', zIndex: 50, display: 'flex', alignItems: 'center', gap: '12px' } });
    E.marca({ tam: 40, padre: bicho }).raiz.style.position = 'relative';
    nodo({ padre: bicho, texto: 'Didacta', estilo: { fontWeight: 800, fontSize: '26px', letterSpacing: '-0.02em', color: 'var(--verde-tinta)' } });
    visible(bicho, desde, hasta, 0.5, 0.4);
  }
  const progreso = nodo({ clase: 'progreso', estilo: { width: `${W}px`, zIndex: 60 } });
  tarea((t) => {
    progreso.style.transform = `scaleX(${Math.min(1, t / G.total)})`;
  });
  for (const id of ['problema', 'idea', 'leccion', 'idiomas', 'composicion', 'cierre']) sonido(G.escena(id).ini, 'soplo', 0.8);

  // ------------------------------------------------------------ apertura --
  {
    const a = G.escena('apertura');
    const g = capa();
    const m = E.marca({ tam: 190, x: W / 2 - 95, y: 214, padre: g });
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
    [m.titular, ...m.lineas].forEach((l, i) =>
      anim(l, [
        [a.ini + 1.0 + 0.1 * i, { sx: 0 }],
        [a.ini + 1.4 + 0.1 * i, { sx: 1 }, 'sale4'],
      ]),
    );
    const ante = centrado(`${V.codigo} · ${V.ruta}`, 470, {}, g);
    ante.className = 'antetitulo';
    Object.assign(ante.style, { position: 'absolute', left: 0, width: `${W}px`, textAlign: 'center' });
    entra(ante, a.ini + 0.8, { dy: 16 });
    const titulo = centrado('', 520, { fontSize: '112px' }, g);
    titulo.className = 'titular';
    Object.assign(titulo.style, { position: 'absolute', left: 0, width: `${W}px`, textAlign: 'center' });
    titulo.textContent = V.titulo;
    E.palabras(titulo, a.ini + 0.95, { paso: 0.09, dy: 40 });
    const sub = centrado(V.subtitulo, 668, { fontSize: '40px' }, g);
    sub.className = 'entradilla';
    Object.assign(sub.style, { position: 'absolute', left: 0, width: `${W}px`, textAlign: 'center' });
    entra(sub, a.ini + 1.55, { dy: 20 });
    sale(g, a.fin - 0.5, { dur: 0.5, dy: -30 });
  }

  // ------------------------------------------------------------ problema --
  {
    const p = G.escena('problema');
    const g = capa();
    const anios = ['2024-25', '2025-26', '2026-27'];
    const filas = [
      ['Tema 1 · Diapositivas', 'tema1-diapos.tex', 'diapositivas'],
      ['Tema 1 · Apuntes', 'tema1-apuntes.tex', 'apuntes'],
      ['Tema 1 · Notes', 'tema1-notes-en.tex', 'idioma'],
      ['Primer parcial', 'parcial1-final.tex', 'exámenes'],
    ];
    const x0 = 395;
    const dx = 440;
    const y0 = 300;
    const dy = 138;
    const tCurso = G.palabra('te-suena', 'curso');
    const tarjetas = [];
    anios.forEach((anio, c) => {
      const carpeta = nodo({ clase: 'carpeta', texto: anio, padre: g, estilo: { left: `${x0 + c * dx}px`, top: `${y0 - 58}px` } });
      entra(carpeta, c === 0 ? p.ini + 0.3 : tCurso + 0.15 * c, { dy: 12 });
    });
    filas.forEach(([titulo, fichero, palabra], f) => {
      anios.forEach((anio, c) => {
        const card = nodo({ clase: 'fichero', padre: g, html: `${titulo}<small>${fichero.replace('.tex', `-${anio.slice(2).replace('-', '')}.tex`)}</small>`, estilo: { left: `${x0 + c * dx}px`, top: `${y0 + f * dy}px` } });
        const tPalabra = G.palabra('te-suena', palabra);
        let t = c === 0 ? tPalabra : Math.max(tCurso, tPalabra) + 0.12 * c + 0.05 * f;
        if (palabra === 'idioma') t = tPalabra + 0.1 * c;
        anim(card, [
          [t, { o: 0, y: 24, s: 0.94 }],
          [t + 0.5, { o: 1, y: 0, s: 1 }, 'rebote'],
        ]);
        tarjetas.push({ card, c, f, x: x0 + c * dx, y: y0 + f * dy });
      });
    });
    const cuenta = centrado('<b style="color:var(--tinta)">12 copias</b> del mismo tema', 872, { fontSize: '38px', fontWeight: 500, color: 'var(--apagado)' }, g);
    entra(cuenta, G.palabra('te-suena', 'idioma') + 0.45, { dy: 16 });

    // La errata: en todas; se corrige en una; sigue en las demás.
    const tErrata = G.palabra('errata', 'errata');
    const tSitio = G.palabra('errata', 'sitio');
    const tSigue = G.palabra('errata', 'sigue');
    tarjetas.forEach(({ card, c, f }, i) => {
      const roja = nodo({ padre: card, html: '!', estilo: { position: 'absolute', right: '-12px', top: '-12px', width: '34px', height: '34px', borderRadius: '50%', background: 'var(--profesor)', color: '#fff', fontWeight: 800, fontSize: '22px', display: 'grid', placeItems: 'center', boxShadow: '0 4px 12px rgba(170,75,75,.4)', paddingLeft: 0 } });
      const t = tErrata + 0.025 * i;
      anim(roja, [
        [t, { o: 0, s: 0.3 }],
        [t + 0.35, { o: 1, s: 1 }, 'rebote'],
      ]);
      if (c === 2 && f === 0) {
        anim(roja, [[tSitio, { o: 1 }], [tSitio + 0.2, { o: 0 }]]);
        const verde = nodo({ padre: card, html: '✓', estilo: { position: 'absolute', right: '-12px', top: '-12px', width: '34px', height: '34px', borderRadius: '50%', background: 'var(--verde-oscuro)', color: '#fff', fontWeight: 800, fontSize: '20px', display: 'grid', placeItems: 'center' } });
        anim(verde, [
          [tSitio, { o: 0, s: 0.3 }],
          [tSitio + 0.35, { o: 1, s: 1 }, 'rebote'],
        ]);
        card.style.outline = '0px solid transparent';
        tarea((tt) => {
          card.style.boxShadow = tt >= tSitio ? '0 0 0 3px var(--verde), 0 10px 26px rgba(28,31,38,.12)' : '';
        });
      } else {
        const d = 0.02 * i;
        anim(roja, [
          [tSigue + d, { s: 1 }],
          [tSigue + d + 0.18, { s: 1.4 }, 'sale'],
          [tSigue + d + 0.5, { s: 1 }, 'suave'],
        ]);
      }
    });
    // Salen todas hacia el centro: la idea es juntarlas en una.
    tarjetas.forEach(({ card, x, y }, i) => {
      const t = p.fin - 0.55 + 0.012 * i;
      anim(card, [
        [t, { x: 0, y: 0, s: 1, o: 1 }],
        [t + 0.55, { x: W / 2 - 125 - x, y: H / 2 - 40 - y, s: 0.5, o: 0 }, 'entra'],
      ]);
    });
    visible(g, p.ini, p.fin + 0.05, 0.3, 0.2);
  }

  // ---------------------------------------------------------------- idea --
  {
    const i = G.escena('idea');
    const g = capa();
    const titular = centrado('', 128, { fontSize: '76px' }, g);
    titular.className = 'titular';
    Object.assign(titular.style, { position: 'absolute', left: 0, width: `${W}px`, textAlign: 'center' });
    titular.textContent = 'Se escribe una vez';
    E.palabras(titular, G.palabra('vuelta', 'vuelta') - 0.1, { paso: 0.08 });

    const madre = nodo({
      clase: 'leccion-madre',
      padre: g,
      html: `<div class="antetitulo" style="font-size:18px">Una lección</div>
        <div style="font-size:36px;font-weight:800;letter-spacing:-.02em;line-height:1.12;margin:14px 0 12px">Límite de una función en un punto</div>
        <div class="mono" style="font-size:16px;color:var(--apagado);white-space:nowrap">calculo/limites/concepto-de-limite/definicion-de-limite</div>
        <div class="idiomas" style="display:flex;gap:10px;margin-top:22px"></div>`,
      estilo: { left: '300px', top: '380px' },
    });
    entra(madre, i.ini + 0.15, { s: 0.9, dy: 0, blur: 10, dur: 0.7 });
    const tIdioma = G.palabra('una-vez', 'idioma');
    ['Castellano', 'English'].forEach((nombre, k) => {
      const chip = nodo({ clase: 'chip', padre: madre.querySelector('.idiomas'), html: `<span class="punto"></span>${nombre}`, estilo: { fontSize: '20px', padding: '8px 16px 8px 12px', position: 'relative' } });
      entra(chip, tIdioma - 0.25 + 0.12 * k, { dy: 14, curva: 'rebote' });
    });

    const salidas = [
      ['Diapositivas', 'diapositivas', 'var(--diapositivas)', 'diapositivas'],
      ['Apuntes', 'apuntes', 'var(--apuntes)', 'apuntes'],
      ['Copia del profesor', 'profesor', 'var(--profesor)', 'profesor'],
      ['Hoja de problemas', 'hoja', 'var(--ambar)', null],
      ['Examen', 'examen', 'var(--verde-tinta)', null],
    ];
    const svg = nodo({ svg: true, tag: 'svg', padre: g, attrs: { width: W, height: H, viewBox: `0 0 ${W} ${H}` }, estilo: { position: 'absolute', left: 0, top: 0 } });
    const origen = { x: 760, y: 530 };
    const tProfesor = G.palabra('una-vez', 'profesor');
    salidas.forEach(([nombre, ic, color, palabra], k) => {
      const y = 250 + k * 112;
      const t = palabra ? G.palabra('una-vez', palabra) - 0.15 : tProfesor + 0.35 + 0.25 * (k - 3);
      const camino = nodo({ svg: true, tag: 'path', padre: svg, attrs: { d: `M ${origen.x} ${origen.y} C ${origen.x + 220} ${origen.y}, ${1200 - 220} ${y + 46}, 1200 ${y + 46}`, fill: 'none', stroke: color, 'stroke-width': 3, 'stroke-linecap': 'round', opacity: 0.55 } });
      anim(camino, [
        [t - 0.1, { trazo: 0 }],
        [t + 0.4, { trazo: 1 }, 'sale'],
      ]);
      const tarjeta = nodo({ clase: 'salida', padre: g, html: `<span class="icono">${icono[ic]}</span>${nombre}`, estilo: { left: '1200px', top: `${y}px` } });
      tarjeta.style.setProperty('--color', color);
      tarjeta.querySelector('.icono').style.color = color;
      anim(tarjeta, [
        [t + 0.15, { o: 0, x: 30, s: 0.94 }],
        [t + 0.65, { o: 1, x: 0, s: 1 }, 'rebote'],
      ]);
    });
    visible(g, i.ini, i.fin + 0.05, 0.25, 0.4);
  }

  // ----------------------------------------------- lección y salidas: app --
  const l = G.escena('leccion');
  const s = G.escena('salidas');
  const tSalen = G.palabra('compilar', 'salen') - 0.35;
  {
    const g = capa();
    const cam = E.camara(g);
    const v = E.ventana({ captura: 'leccion', x: 210, y: 53, ancho: 1500, padre: g, camara: cam });
    anim(v.raiz, [
      [l.ini, { o: 0, y: 70 }],
      [l.ini + 0.85, { o: 1, y: 0 }, 'sale4'],
      [tSalen, { o: 1 }],
      [tSalen + 0.55, { o: 0 }, 'suave'],
    ]);
    const tMira = G.frase('asi-se-ve').ini + 0.2;
    cam.enfocar(tMira, tMira + 1.8, union(v.zona('titulo'), v.zona('editor-definicion')), { margen: 0.05 });
    const tMarcas = G.frase('marcas').ini;
    cam.enfocar(tMarcas + 0.3, tMarcas + 1.9, union(v.zona('editor-titulo'), v.zona('editor-medio')), { margen: 0.16, dy: 10, max: 1.85 });
    const tFrase = G.palabra('marcas', 'esta frase');
    const tParrafo = G.palabra('marcas', 'este párrafo');
    E.resaltar(v, 'editor-medio', { t0: tFrase - 0.3, t1: l.fin - 0.1, foco: true, oscuro: 1, pad: 18, caja: false, color: 'transparent' });
    E.resaltar(v, 'editor-diapositivas', { t0: tFrase, t1: l.fin - 0.1, color: '#2d5fa0', etiqueta: `${icono.diapositivas} Diapositivas`, lado: 'arriba', alinear: 'derecha', pad: 8 });
    E.resaltar(v, 'editor-apuntes', { t0: tParrafo, t1: l.fin - 0.1, color: '#3c876e', etiqueta: `${icono.apuntes} Apuntes`, lado: 'abajo', alinear: 'derecha', pad: 8 });

    // Salidas: se vuelve a la pantalla entera y se pulsa «compilar».
    cam.reposo(s.ini - 0.2, s.ini + 0.9);
    const tPulsa = G.palabra('compilar', 'Compilar', { fin: true }) - 0.12;
    const c = E.cursor(v, { desde: { lienzo: true, x: 1320, y: 980 } });
    c.mostrar(s.ini, tSalen + 0.2);
    c.ir(s.ini + 0.15, tPulsa - 0.08, { zona: 'compilar', ax: 0.42, ay: 0.55 });
    c.clic(tPulsa);
    E.resaltar(v, 'compilar', { t0: tPulsa - 0.5, t1: tSalen, color: '#346e34', pad: 6 });
  }
  {
    const g = capa();
    const x = [65, 680, 1295];
    const pDia = E.hoja({ pdf: 'diapositivas', x: x[0], y: 330, ancho: 560, padre: g });
    const zInt = D.pdf.apuntes.zonas.intuicion;
    const pApu = E.hoja({ pdf: 'apuntes', x: x[1], y: 262, ancho: 560, alto: 576, desde: zInt[1] - 190, padre: g });
    const pPro = E.hoja({ pdf: 'profesor', x: x[2], y: 330, ancho: 560, padre: g });
    const rotulos = [
      ['Diapositivas', 'var(--diapositivas)', 'diapositivas', pDia],
      ['Apuntes', 'var(--apuntes)', 'apuntes', pApu],
      ['Copia del profesor', 'var(--profesor)', 'profesor', pPro],
    ];
    rotulos.forEach(([texto, color, palabra, p], k) => {
      const t = G.palabra('compilar', palabra) - 0.2;
      anim(p.raiz, [
        [t, { o: 0, y: 90, r: k === 1 ? 0 : k === 0 ? -2.5 : 2.5 }],
        [t + 0.7, { o: 1, y: 0, r: 0 }, 'sale4'],
      ]);
      const r = nodo({ clase: 'rotulo-hoja', padre: g, html: `<span style="display:inline-block;width:14px;height:14px;border-radius:50%;background:${color};margin-right:12px;vertical-align:2px"></span>${texto}`, estilo: { left: `${p.x}px`, top: `${p.y - 58}px` } });
      entra(r, t + 0.2, { dy: 12 });
    });
    E.resaltar(pPro, 'nota', { t0: G.palabra('compilar', 'notas de clase') - 0.1, t1: s.fin - 0.15, color: '#aa4b4b', etiqueta: 'Solo en tu copia', lado: 'abajo', pad: 4 });
    // Las diapositivas centran su contenido en vertical, así que la del
    // alumno, que tiene menos, lo tiene más abajo: el hueco se mide desde su
    // propia definición, con la misma distancia que en la del profesor.
    const zonaFantasma = () => {
      const n = pPro.zona('nota');
      const dP = pPro.zona('definicion');
      const dD = pDia.zona('definicion');
      const y = dD.y + dD.h + (n.y - (dP.y + dP.h));
      return { x: n.x - pPro.x + pDia.x, y, w: n.w, h: Math.min(n.h, pDia.y + pDia.alto - 22 - y) };
    };
    E.resaltar(pDia, zonaFantasma, { t0: G.palabra('no-existen', 'no existen') - 0.2, t1: s.fin - 0.15, color: '#8c939d', etiqueta: 'Aquí no existe', lado: 'abajo', pad: 4, discontinuo: true });
    visible(g, tSalen, s.fin + 0.05, 0.3, 0.4);
  }

  // ------------------------------------------------------------- idiomas --
  {
    const d = G.escena('idiomas');
    const tMismo = G.frase('mismo-tema').ini - 0.2;
    const g = capa();
    const cam = E.camara(g);
    const v = E.ventana({ captura: 'leccion', x: 210, y: 53, ancho: 1500, padre: g, camara: cam });
    visible(v.raiz, d.ini, tMismo + 0.5, 0.45, 0.5);
    cam.enfocar(d.ini + 0.2, d.ini + 1.5, union(v.zona('castellano'), v.zona('ingles'), v.zona('titulo')), { margen: 0.12, max: 1.8, dy: 30 });
    const tFichero = G.palabra('un-fichero', 'por idioma');
    E.resaltar(v, 'castellano', { t0: tFichero - 0.2, t1: tMismo + 0.2, color: '#346e34', etiqueta: 'Original', lado: 'abajo', pad: 6 });
    const tTrad = G.palabra('un-fichero', 'traducidos');
    E.resaltar(v, 'ingles', { t0: tTrad - 0.2, t1: tMismo + 0.2, color: '#2d5fa0', etiqueta: 'Traducida', lado: 'abajo', pad: 6 });

    const g2 = capa();
    const pes = E.hoja({ pdf: 'diapositivas', x: 110, y: 318, ancho: 820, padre: g2 });
    const pen = E.hoja({ pdf: 'diapositivas-en', x: 990, y: 318, ancho: 820, padre: g2 });
    [
      [pes, 'Castellano', 'castellano'],
      [pen, 'English', 'inglés'],
    ].forEach(([p, texto, palabra], k) => {
      const t = Math.max(tMismo + 0.1, G.palabra('mismo-tema', palabra) - 0.35);
      anim(p.raiz, [
        [t, { o: 0, y: 80, s: 0.97 }],
        [t + 0.7, { o: 1, y: 0, s: 1 }, 'sale4'],
      ]);
      const r = nodo({ clase: 'rotulo-hoja', padre: g2, texto, estilo: { left: `${p.x}px`, top: `${p.y - 60}px` } });
      entra(r, t + 0.2, { dy: 12 });
    });
    visible(g2, tMismo, d.fin + 0.05, 0.3, 0.4);
  }

  // --------------------------------------------------------- composición --
  {
    const c = G.escena('composicion');
    const tSin = G.frase('sin-copiar').ini;
    const g = capa();
    const cam = E.camara(g);
    const v = E.ventana({ captura: 'composicion-antes', x: 210, y: 53, ancho: 1500, padre: g, camara: cam });
    visible(v.raiz, c.ini, c.fin + 0.05, 0.45, 0.4);
    cam.enfocar(c.ini + 0.2, c.ini + 1.4, union(v.zona('apartado'), v.zona('algebra')), { margen: 0.1 });

    // El arrastre, con trozos de la captura de antes que acaban exactamente
    // donde la de después tiene cada fila.
    const antes = D.capturas['composicion-antes'];
    const despues = D.capturas['composicion-despues'];
    const contenido = v.raiz.querySelector('.contenido');
    const esc = v.escala;
    const tCoge = G.palabra('lista', 'arrastrando') - 0.55;
    const tSuelta = tCoge + 1.45;
    const trozo = (nombre) => {
      const z = antes.zonas[nombre];
      return nodo({
        padre: contenido,
        estilo: {
          position: 'absolute', left: `${z[0] * esc}px`, top: `${z[1] * esc}px`, width: `${z[2] * esc}px`, height: `${z[3] * esc}px`,
          backgroundImage: `url("${antes.src}")`, backgroundSize: `${antes.ancho * esc}px ${antes.alto * esc}px`, backgroundPosition: `${-z[0] * esc}px ${-z[1] * esc}px`,
          transformOrigin: '50% 50%',
        },
      });
    };
    const zp = antes.zonas['por-definicion'];
    const za = antes.zonas.algebra;
    const hueco = nodo({ padre: contenido, estilo: { position: 'absolute', left: `${zp[0] * esc}px`, top: `${zp[1] * esc}px`, width: `${zp[2] * esc}px`, height: `${(za[1] + za[3] - zp[1]) * esc}px`, background: '#f5f6f3' } });
    const mover = (nombre) => (despues.zonas[nombre][1] - antes.zonas[nombre][1]) * esc;
    const tPor = trozo('por-definicion');
    const tHis = trozo('historia');
    const sombra = nodo({ padre: contenido, estilo: { position: 'absolute', left: `${za[0] * esc}px`, top: `${za[1] * esc}px`, width: `${za[2] * esc}px`, height: `${za[3] * esc}px`, borderRadius: '6px', boxShadow: '0 14px 30px rgba(28,31,38,.28), 0 2px 6px rgba(28,31,38,.18)' } });
    const tAlg = trozo('algebra');
    for (const n of [hueco, tPor, tHis, tAlg, sombra]) anim(n, [[0, { o: 0 }], [tCoge, { o: 0 }], [tCoge + 0.01, { o: 1 }], [tSuelta + 0.18, { o: 1 }], [tSuelta + 0.19, { o: 0 }]]);
    anim(sombra, [[tCoge, { o: 0 }], [tCoge + 0.2, { o: 1 }], [tSuelta, { o: 1 }], [tSuelta + 0.18, { o: 0 }]]);
    for (const n of [tAlg, sombra]) {
      anim(n, [
        [tCoge, { y: 0, s: 1 }],
        [tCoge + 0.2, { y: 0, s: 1.015 }, 'sale'],
        [tSuelta - 0.05, { y: mover('algebra'), s: 1.015 }, 'muysuave'],
        [tSuelta + 0.15, { y: mover('algebra'), s: 1 }, 'sale'],
      ]);
    }
    anim(tHis, [[tCoge + 0.35, { y: 0 }], [tCoge + 0.75, { y: mover('historia') }, 'suave']]);
    anim(tPor, [[tCoge + 0.75, { y: 0 }], [tCoge + 1.15, { y: mover('por-definicion') }, 'suave']]);
    v.cambiar(tSuelta + 0.17, 'composicion-despues', 0.02);
    const cur = E.cursor(v, { desde: { lienzo: true, x: 1500, y: 1000 } });
    cur.mostrar(c.ini + 0.9, tSin - 0.1);
    cur.ir(c.ini + 1.0, tCoge - 0.05, { zona: 'algebra', captura: 'composicion-antes', ax: 0.02, ay: 0.5 });
    cur.clic(tCoge);
    cur.ir(tCoge + 0.2, tSuelta - 0.05, { zona: 'algebra', captura: 'composicion-despues', ax: 0.02, ay: 0.5 });
    sonido(tSuelta, 'clic', 0.5);

    // La misma lección, en la hoja y en el examen.
    v.cambiar(tSin - 0.3, 'discontinuidades', 0.5);
    cam.reposo(tSin - 0.4, tSin + 0.4);
    const tHoja = G.palabra('sin-copiar', 'hoja de problemas');
    const tExamen = G.palabra('sin-copiar', 'examen');
    cam.enfocar(tHoja - 0.5, tHoja + 0.5, union(v.zona('hoja', 'discontinuidades'), v.zona('parcial', 'discontinuidades')), { margen: 0.3, max: 1.8, dx: -120 });
    E.resaltar(v, 'hoja', { captura: 'discontinuidades', t0: tHoja - 0.1, t1: c.fin - 0.2, color: '#be8237', etiqueta: `${icono.hoja} Hoja de problemas`, lado: 'izquierda', pad: 6 });
    E.resaltar(v, 'parcial', { captura: 'discontinuidades', t0: tExamen - 0.1, t1: c.fin - 0.2, color: '#275227', etiqueta: `${icono.examen} Examen`, lado: 'izquierda', pad: 6 });
    const tUnaVez = G.palabra('sin-copiar', 'una vez');
    cam.reposo(tUnaVez - 0.5, tUnaVez + 0.6);
    E.resaltar(v, 'titulo', { captura: 'discontinuidades', t0: tUnaVez - 0.1, t1: c.fin - 0.2, color: '#346e34', etiqueta: 'Una sola lección', lado: 'abajo', pad: 8 });
  }

  // ------------------------------------------------------------ guardado --
  {
    const gu = G.escena('guardado');
    const g = capa();
    const cam = E.camara(g);
    const v = E.ventana({ captura: 'composicion-despues', x: 210, y: 53, ancho: 1500, padre: g, camara: cam });
    visible(v.raiz, gu.ini, gu.fin + 0.05, 0.4, 0.4);
    anim(g, [[0, { x: 0, y: 0, s: 1 }]]);
    cam.enfocar(gu.ini, gu.ini + 0.01, union(v.zona('guardar'), v.zona('apartado')), { margen: 0.1 });
    const cur = E.cursor(v, { desde: { lienzo: true, x: 1400, y: 900 } });
    const tPulsa = gu.ini + 1.0;
    cur.mostrar(gu.ini + 0.1, gu.fin - 0.2);
    cur.ir(gu.ini + 0.2, tPulsa - 0.05, { zona: 'guardar', ax: 0.45 });
    cur.clic(tPulsa);
    v.cambiar(tPulsa + 0.25, 'composicion', 0.3);
    cam.reposo(tPulsa + 0.35, tPulsa + 1.3);
    E.resaltar(v, 'aviso', { captura: 'composicion', t0: tPulsa + 0.9, t1: gu.fin - 0.2, color: '#346e34', etiqueta: 'Un cambio, con tu nombre', lado: 'arriba', pad: 4 });
    const tGit = G.palabra('historial', 'GitHub');
    cur.ir(tGit - 0.6, tGit + 0.1, { zona: 'subir', captura: 'composicion', ax: 0.5, ay: 0.7 });
    E.resaltar(v, 'subir', { captura: 'composicion', t0: tGit - 0.1, t1: gu.fin - 0.2, color: '#346e34', etiqueta: 'A tu GitHub', lado: 'abajo', alinear: 'derecha', pad: 6 });
  }

  // -------------------------------------------------------------- cierre --
  {
    const z = G.escena('cierre');
    const g = capa();
    const m = E.marca({ tam: 150, x: W / 2 - 75, y: 200, padre: g });
    m.baldosa.style.transformBox = 'fill-box';
    m.baldosa.style.transformOrigin = '50% 50%';
    anim(m.baldosa, [[z.ini, { o: 0, s: 0.6 }], [z.ini + 0.6, { o: 1, s: 1 }, 'rebote']]);
    m.hojas.forEach((h, i) => anim(h, [[z.ini + 0.2 + 0.08 * i, { o: 0, x: -6, y: 8 }], [z.ini + 0.7 + 0.08 * i, { o: 1, x: 0, y: 0 }, 'sale4']]));
    const l1 = centrado('', 420, { fontSize: '88px' }, g);
    l1.className = 'titular';
    Object.assign(l1.style, { position: 'absolute', left: 0, width: `${W}px`, textAlign: 'center' });
    l1.textContent = 'Se escribe una vez.';
    E.palabras(l1, G.frase('lema').ini - 0.15, { paso: 0.1 });
    const l2 = centrado('', 520, { fontSize: '88px', color: 'var(--verde-oscuro)' }, g);
    l2.className = 'titular';
    Object.assign(l2.style, { position: 'absolute', left: 0, width: `${W}px`, textAlign: 'center', color: 'var(--verde-oscuro)' });
    l2.textContent = 'Lo demás, se genera.';
    E.palabras(l2, G.palabra('lema', 'demás') - 0.3, { paso: 0.1 });
    const sig = centrado(`<span class="chip" style="font-size:30px;padding:14px 26px 14px 20px"><span class="punto" style="background:var(--verde-oscuro)"></span>Siguiente&nbsp;&nbsp;<b>${V.siguiente}</b></span>`, 700, {}, g);
    entra(sig, G.frase('siguiente').ini - 0.1, { dy: 20 });
    const url = centrado('franjfal.github.io/didacta', 812, { fontSize: '26px', fontWeight: 600, color: 'var(--apagado)', letterSpacing: '0.01em' }, g);
    entra(url, G.frase('siguiente').ini + 0.5, { dy: 10 });
    visible(g, z.ini, G.total + 1, 0.3, 0.01);
  }
};
