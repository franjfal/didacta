/* El motor de los vídeos de Didacta.
 *
 * Un vídeo es una página: `Estudio.pintar(t)` deja la página exactamente como
 * tiene que estar en el segundo `t`, y `grabar.mjs` la fotografía treinta
 * veces por segundo. Nada depende del reloj de verdad, así que el mismo guion
 * da el mismo vídeo cada vez que se pinta.
 *
 * Tres ideas sostienen el resto:
 *
 * - **Todo se engancha a la voz.** El montaje no escribe segundos: pide
 *   `G.frase('marcas').ini` o `G.palabra('marcas', 'párrafo')`, que salen de
 *   la locución de verdad. Si una frase cambia, la imagen la sigue.
 * - **Todo se engancha a la interfaz por su nombre.** Una captura trae sus
 *   zonas --«compilar», «editor-apuntes»-- medidas por el propio Flutter. La
 *   cámara, los recuadros y el cursor van a la zona, no a unos píxeles.
 * - **Las marcas se pintan en el lienzo, no en la captura.** Un recuadro o una
 *   etiqueta sigue a la cámara pero no crece con ella: el borde mide lo mismo
 *   con la pantalla entera que con el zoom a la pestaña.
 */
(function () {
  'use strict';

  const W = 1920;
  const H = 1080;

  // ------------------------------------------------------------ curvas ---

  const curvas = {
    lineal: (t) => t,
    entra: (t) => t * t * t,
    sale: (t) => 1 - Math.pow(1 - t, 3),
    sale4: (t) => 1 - Math.pow(1 - t, 4),
    suave: (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2),
    muysuave: (t) => (t < 0.5 ? 16 * Math.pow(t, 5) : 1 - Math.pow(-2 * t + 2, 5) / 2),
    rebote: (t) => {
      const c1 = 1.3;
      const c3 = c1 + 1;
      return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2);
    },
  };

  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

  // ------------------------------------------------------------ pistas ---

  const pistas = new Map(); // nodo -> [{t, props, e}]
  const tareas = [];
  const sonidos = [];
  const TRANSFORMA = ['x', 'y', 's', 'sx', 'sy', 'r'];

  function lienzo() {
    return document.getElementById('lienzo');
  }

  function nodo(o = {}) {
    const n = document.createElementNS(
      o.svg ? 'http://www.w3.org/2000/svg' : 'http://www.w3.org/1999/xhtml',
      o.tag || 'div',
    );
    if (o.clase) n.setAttribute('class', o.clase);
    if (o.html != null) n.innerHTML = o.html;
    if (o.texto != null) n.textContent = o.texto;
    if (o.estilo) Object.assign(n.style, o.estilo);
    if (o.attrs) for (const [k, v] of Object.entries(o.attrs)) n.setAttribute(k, v);
    (o.padre || lienzo()).appendChild(n);
    return n;
  }

  /** Claves de un nodo: [[t, {x, y, s, o, blur, ...}, curva], ...].
   *
   * Cada propiedad se interpola entre las claves que la nombran, con la curva
   * de la clave de destino. Antes de la primera vale lo de la primera; después
   * de la última, lo de la última.
   */
  function anim(n, claves) {
    const lista = pistas.get(n) || [];
    for (const [t, props, e] of claves) {
      lista.push({ t, props, e: typeof e === 'function' ? e : curvas[e || 'suave'] });
    }
    lista.sort((a, b) => a.t - b.t);
    pistas.set(n, lista);
    return n;
  }

  function valor(n, prop, t, porDefecto) {
    const lista = pistas.get(n);
    if (!lista) return porDefecto;
    let antes = null;
    let despues = null;
    for (const k of lista) {
      if (!(prop in k.props)) continue;
      if (k.t <= t) antes = k;
      else {
        despues = k;
        break;
      }
    }
    if (!antes && !despues) return porDefecto;
    if (!antes) return despues.props[prop];
    if (!despues) return antes.props[prop];
    const u = despues.e(clamp((t - antes.t) / (despues.t - antes.t), 0, 1));
    return antes.props[prop] + (despues.props[prop] - antes.props[prop]) * u;
  }

  function aplicar(n, lista, t) {
    const tiene = new Set();
    for (const k of lista) for (const p in k.props) tiene.add(p);
    if (TRANSFORMA.some((p) => tiene.has(p))) {
      const x = valor(n, 'x', t, 0);
      const y = valor(n, 'y', t, 0);
      const s = valor(n, 's', t, 1);
      const sx = valor(n, 'sx', t, 1) * s;
      const sy = valor(n, 'sy', t, 1) * s;
      const r = valor(n, 'r', t, 0);
      n.style.transform = `translate(${x}px, ${y}px) rotate(${r}deg) scale(${sx}, ${sy})`;
    }
    if (tiene.has('o')) {
      const o = clamp(valor(n, 'o', t, 1), 0, 1);
      n.style.opacity = o;
      n.style.visibility = o <= 0.001 ? 'hidden' : 'visible';
    }
    if (tiene.has('blur')) n.style.filter = `blur(${Math.max(0, valor(n, 'blur', t, 0))}px)`;
    if (tiene.has('w')) n.style.width = `${valor(n, 'w', t, 0)}px`;
    if (tiene.has('h')) n.style.height = `${valor(n, 'h', t, 0)}px`;
    if (tiene.has('revela')) {
      // De izquierda a derecha, de 0 a 1.
      const v = clamp(valor(n, 'revela', t, 1), 0, 1);
      n.style.clipPath = `inset(-20% ${(1 - v) * 100}% -20% -20%)`;
    }
    if (tiene.has('trazo')) {
      // Una línea de SVG que se dibuja: 0 nada, 1 entera.
      const largo = n.getTotalLength ? n.getTotalLength() : 1000;
      n.style.strokeDasharray = `${largo}`;
      n.style.strokeDashoffset = `${largo * (1 - clamp(valor(n, 'trazo', t, 1), 0, 1))}`;
    }
  }

  function tarea(fn) {
    tareas.push(fn);
  }

  function sonido(t, tipo, volumen = 1) {
    sonidos.push({ t: +t.toFixed(3), tipo, volumen });
  }

  function pintar(t) {
    for (const [n, lista] of pistas) aplicar(n, lista, t);
    for (const fn of tareas) fn(t);
  }

  // ------------------------------------------------------------ tiempos ---

  function normal(texto) {
    return texto
      .toLowerCase()
      .normalize('NFD')
      .replace(/[̀-ͯ]/g, '')
      .replace(/[^a-z0-9ñ ]+/g, ' ')
      .trim()
      .split(/\s+/)
      .filter(Boolean);
  }

  function crearTiempos(datos) {
    const frases = {};
    const escenas = {};
    for (const e of datos.escenas) {
      escenas[e.id] = e;
      for (const f of e.frases) frases[f.id] = f;
    }
    const G = {
      total: datos.total,
      escenas: datos.escenas,
      escena(id) {
        if (!escenas[id]) throw new Error(`no hay escena «${id}»`);
        return escenas[id];
      },
      frase(id) {
        if (!frases[id]) throw new Error(`no hay frase «${id}»`);
        return frases[id];
      },
      /** Cuándo empieza (o acaba, con {fin: true}) una palabra de una frase. */
      palabra(id, texto, o = {}) {
        const f = G.frase(id);
        const buscado = normal(texto);
        const oidas = f.palabras.map((p) => normal(p.p)[0] || '');
        let vistas = 0;
        for (let i = 0; i + buscado.length <= oidas.length; i += 1) {
          let casa = true;
          for (let k = 0; k < buscado.length; k += 1) {
            if (!oidas[i + k] || !oidas[i + k].startsWith(buscado[k].slice(0, Math.max(3, buscado[k].length - 1)))) {
              casa = false;
              break;
            }
          }
          if (casa && vistas++ === (o.n || 0)) {
            const ultima = f.palabras[i + buscado.length - 1];
            return o.fin ? ultima.fin : f.palabras[i].ini;
          }
        }
        // Si Whisper la oyó de otra forma, se estima por dónde cae en el texto.
        const at = f.texto.toLowerCase().indexOf(texto.toLowerCase());
        const u = at < 0 ? 0.5 : (at + (o.fin ? texto.length : 0)) / f.texto.length;
        console.warn(`«${texto}» no se oye en «${id}»; lo estimo`);
        return f.ini + (f.fin - f.ini) * u;
      },
    };
    return G;
  }

  // ------------------------------------------------------------ piezas ---

  /** La marca de Didacta, con las proporciones de `app/lib/ui/brand.dart`. */
  function marca(o) {
    const tam = o.tam || 200;
    const raiz = nodo({ clase: 'abs', padre: o.padre, estilo: { width: `${tam}px`, height: `${tam}px`, left: `${o.x || 0}px`, top: `${o.y || 0}px` } });
    const svg = nodo({ svg: true, tag: 'svg', padre: raiz, attrs: { viewBox: '0 0 100 100', width: tam, height: tam } });
    const id = `g${Math.random().toString(36).slice(2, 8)}`;
    svg.innerHTML = `<defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5FB35F"/><stop offset="1" stop-color="#346E34"/></linearGradient></defs>`;
    const baldosa = nodo({ svg: true, tag: 'rect', padre: svg, attrs: { x: 0, y: 0, width: 100, height: 100, rx: 22.5, fill: `url(#${id})` } });
    const u = (v) => 5.5 + 89 * v;
    const hojas = [];
    const opacidades = [0.42, 0.7, 1.0];
    for (let i = 0; i < 3; i += 1) {
      const shift = (2 - i) * 0.075;
      const x = 0.165 + shift;
      const y = 0.105 + 0.15 - shift;
      const g = nodo({ svg: true, tag: 'g', padre: svg });
      g.style.transformBox = 'fill-box';
      g.style.transformOrigin = '50% 50%';
      nodo({ svg: true, tag: 'rect', padre: g, attrs: { x: u(x), y: u(y), width: 89 * 0.52, height: 89 * 0.64, rx: 89 * 0.045, fill: '#fff', 'fill-opacity': opacidades[i] } });
      hojas.push(g);
    }
    const frente = hojas[2];
    const titular = nodo({ svg: true, tag: 'rect', padre: frente, attrs: { x: u(0.223), y: u(0.3759), width: 89 * 0.2505, height: 89 * 0.062, rx: 89 * 0.018, fill: '#346E34' } });
    const lineas = [0, 1].map((k) =>
      nodo({ svg: true, tag: 'rect', padre: frente, attrs: { x: u(0.223), y: u(k === 0 ? 0.5165 : 0.5997), width: 89 * 0.404 * (k === 0 ? 1 : 0.74), height: 89 * 0.036, rx: 89 * 0.018, fill: '#346E34', 'fill-opacity': 0.55 } }),
    );
    for (const l of [titular, ...lineas]) {
      l.style.transformBox = 'fill-box';
      l.style.transformOrigin = '0% 50%';
    }
    return { raiz, baldosa, hojas, titular, lineas };
  }

  /** Un texto que entra palabra a palabra. Devuelve las palabras. */
  function palabras(n, t0, o = {}) {
    const texto = n.textContent;
    n.textContent = '';
    const paso = o.paso ?? 0.055;
    const out = [];
    texto.split(/(\s+)/).forEach((trozo) => {
      if (/^\s+$/.test(trozo)) {
        n.appendChild(document.createTextNode(trozo));
        return;
      }
      const s = nodo({ tag: 'span', clase: 'palabra', texto: trozo, padre: n });
      const i = out.length;
      anim(s, [
        [t0 + i * paso, { o: 0, y: o.dy ?? 28, blur: 6 }],
        [t0 + i * paso + (o.dur ?? 0.6), { o: 1, y: 0, blur: 0 }, 'sale4'],
      ]);
      out.push(s);
    });
    return out;
  }

  /** La ventana de la aplicación, con una captura dentro. */
  function ventana(o) {
    const D = window.DATOS;
    const cap = D.capturas[o.captura];
    if (!cap) throw new Error(`no hay captura «${o.captura}»`);
    // Un navegador, si la captura es de una página web: la barra lleva su
    // dirección en lugar del nombre de la aplicación.
    const direccion = o.direccion ?? cap.direccion;
    const barra = direccion ? 52 : 36;
    const escala = o.ancho / cap.ancho;
    const alto = cap.alto * escala + barra;
    const raiz = nodo({ clase: 'ventana', padre: o.padre, estilo: { left: `${o.x}px`, top: `${o.y}px`, width: `${o.ancho}px`, height: `${alto}px` } });
    if (direccion) {
      nodo({
        clase: 'barra navegador',
        padre: raiz,
        html: `<i></i><i></i><i></i><span class="flechas">‹ ›</span><span class="direccion"><svg viewBox="0 0 16 16"><path d="M4.5 7V5a3.5 3.5 0 0 1 7 0v2M3.5 7h9v6.5h-9z" fill="none" stroke="currentColor" stroke-width="1.5"/></svg>${direccion}</span>`,
      });
    } else {
      nodo({ clase: 'barra', padre: raiz, html: `<i></i><i></i><i></i><b>${o.titulo || 'Didacta'}</b>` });
    }
    const contenido = nodo({ clase: 'contenido', padre: raiz, estilo: { top: `${barra}px` } });
    const imagenes = {};
    function imagen(nombre) {
      if (!imagenes[nombre]) {
        const c = D.capturas[nombre];
        imagenes[nombre] = nodo({ tag: 'img', padre: contenido, attrs: { src: c.src }, estilo: { width: `${c.ancho * escala}px`, height: `${c.alto * escala}px` } });
      }
      return imagenes[nombre];
    }
    imagen(o.captura);
    const v = {
      raiz,
      x: o.x,
      y: o.y,
      ancho: o.ancho,
      alto,
      escala,
      barra,
      camara: o.camara || null,
      actual: o.captura,
      /** Una zona de una captura, en coordenadas del escenario (sin cámara). */
      zona(nombre, captura) {
        const c = D.capturas[captura || v.actual] || cap;
        let z = c.zonas[nombre];
        if (!z) {
          for (const otra of Object.values(D.capturas)) if (otra.zonas[nombre]) z = otra.zonas[nombre];
        }
        if (!z) throw new Error(`no hay zona «${nombre}»`);
        return { x: v.x + z[0] * escala, y: v.y + barra + z[1] * escala, w: z[2] * escala, h: z[3] * escala };
      },
      /** Pasa a otra captura fundiendo, entre t0 y t0 + dur.
       *
       * Cada imagen parte de como estaba justo antes: si no, volver a una
       * captura que ya salió la dejaba transparente desde el principio del
       * vídeo (su primera clave manda en todo lo anterior). */
      cambiar(t0, nombre, dur = 0.45) {
        const destino = imagen(nombre);
        for (const [n, img] of Object.entries(imagenes)) {
          const antes = valor(img, 'o', t0 - 0.0001, n === o.captura ? 1 : 0);
          const despues = img === destino ? 1 : 0;
          if (antes === despues) continue;
          anim(img, [
            [t0, { o: antes }],
            [t0 + dur, { o: despues }, 'suave'],
          ]);
        }
        v.actual = nombre;
        return destino;
      },
      imagen,
    };
    for (const [nombre, img] of Object.entries(imagenes)) if (nombre !== o.captura) anim(img, [[0, { o: 0 }]]);
    return v;
  }

  /** Una cámara sobre un grupo: acercarse a un rectángulo del escenario. */
  function camara(grupo) {
    grupo.style.transformOrigin = '0 0';
    let estado = { x: 0, y: 0, s: 1 };
    anim(grupo, [[0, { ...estado }]]);
    const cam = {
      grupo,
      /** Del escenario al lienzo, en el segundo t. */
      aLienzo(r, t) {
        const s = valor(grupo, 's', t, 1);
        const x = valor(grupo, 'x', t, 0);
        const y = valor(grupo, 'y', t, 0);
        return { x: x + r.x * s, y: y + r.y * s, w: r.w * s, h: r.h * s, s };
      },
      enfocar(t0, t1, r, o = {}) {
        const margen = o.margen ?? 0.14;
        const max = o.max ?? 2.2;
        const s = Math.min((W * (1 - 2 * margen)) / r.w, (H * (1 - 2 * margen)) / r.h, max);
        const cx = r.x + r.w / 2 + (o.dx || 0);
        const cy = r.y + r.h / 2 + (o.dy || 0);
        const nuevo = { x: W / 2 - cx * s, y: H / 2 - cy * s, s };
        anim(grupo, [
          [t0, { ...estado }],
          [t1, nuevo, o.curva || 'muysuave'],
        ]);
        estado = nuevo;
        return cam;
      },
      reposo(t0, t1, o = {}) {
        const nuevo = { x: 0, y: 0, s: 1 };
        anim(grupo, [
          [t0, { ...estado }],
          [t1, nuevo, o.curva || 'muysuave'],
        ]);
        estado = nuevo;
        return cam;
      },
    };
    return cam;
  }

  /** Dónde está algo de una ventana en el lienzo, en el segundo t. */
  function enLienzo(v, r, t) {
    // Sin ventana, la zona ya está en el lienzo: la de un dibujo del montaje.
    if (!v) return { ...r, s: 1 };
    const dx = valor(v.raiz, 'x', t, 0);
    const dy = valor(v.raiz, 'y', t, 0);
    const movido = { x: r.x + dx, y: r.y + dy, w: r.w, h: r.h };
    return v.camara ? v.camara.aLienzo(movido, t) : { ...movido, s: 1 };
  }

  /** Un recuadro sobre una zona, con foco (lo demás se oscurece) y etiqueta. */
  function resaltar(v, zona, o) {
    const pad = o.pad ?? 8;
    const color = o.color || '#346e34';
    const capa = o.padre || lienzo();
    const foco = o.foco ? nodo({ clase: 'foco', padre: capa }) : null;
    const caja = nodo({ clase: 'resalte', padre: capa, estilo: { '--color': color } });
    caja.style.setProperty('--color', color);
    if (o.caja === false) caja.style.border = 'none';
    if (o.caja === false) caja.style.boxShadow = 'none';
    if (o.discontinuo) {
      caja.style.borderStyle = 'dashed';
      caja.style.boxShadow = 'none';
      caja.style.background = 'rgba(140,147,157,.06)';
    }
    const etiqueta = o.etiqueta ? nodo({ clase: 'etiqueta', padre: capa, html: o.etiqueta }) : null;
    if (etiqueta) etiqueta.style.setProperty('--color', color);
    const t0 = o.t0;
    const t1 = o.t1;
    const entra = o.entra ?? 0.35;
    for (const n of [caja, foco, etiqueta].filter(Boolean)) {
      anim(n, [
        [t0, { o: 0 }],
        [t0 + entra, { o: n === foco ? o.oscuro ?? 1 : 1 }, 'sale'],
        [t1, { o: n === foco ? o.oscuro ?? 1 : 1 }],
        [t1 + 0.35, { o: 0 }, 'suave'],
      ]);
    }
    if (etiqueta) anim(etiqueta, [[t0, { s: 0.9 }], [t0 + 0.45, { s: 1 }, 'rebote']]);
    tarea((t) => {
      if (t < t0 - 0.1 || t > t1 + 0.6) return;
      const base = typeof zona === 'function' ? zona(t) : v.zona(zona, o.captura);
      const r = enLienzo(v, base, t);
      const caja_ = { x: r.x - pad, y: r.y - pad, w: r.w + 2 * pad, h: r.h + 2 * pad };
      for (const n of [caja, foco].filter(Boolean)) {
        Object.assign(n.style, { left: `${caja_.x}px`, top: `${caja_.y}px`, width: `${caja_.w}px`, height: `${caja_.h}px` });
      }
      if (etiqueta) {
        const lado = o.lado || 'arriba';
        const ew = etiqueta.offsetWidth;
        const eh = etiqueta.offsetHeight;
        let x = caja_.x;
        let y = caja_.y - eh - 14;
        if (lado === 'abajo') y = caja_.y + caja_.h + 14;
        if (lado === 'derecha') {
          x = caja_.x + caja_.w + 18;
          y = caja_.y + caja_.h / 2 - eh / 2;
        }
        if (lado === 'izquierda') {
          x = caja_.x - ew - 18;
          y = caja_.y + caja_.h / 2 - eh / 2;
        }
        if (o.alinear === 'derecha') x = caja_.x + caja_.w - ew;
        etiqueta.style.left = `${clamp(x, 24, W - ew - 24)}px`;
        etiqueta.style.top = `${clamp(y, 24, H - eh - 24)}px`;
        etiqueta.style.transformOrigin = lado === 'abajo' ? '0 0' : '0 100%';
      }
    });
    return { caja, foco, etiqueta };
  }

  /** El puntero de macOS, que va a zonas de una ventana, pulsa y arrastra. */
  function cursor(v, o = {}) {
    const capa = o.padre || lienzo();
    const n = nodo({
      clase: 'cursor',
      padre: capa,
      html: `<svg viewBox="0 0 28 36" width="34" height="44"><path d="M3 2 L3 28 L9.5 22 L14 32 L18.5 30 L14 20.5 L23 20.5 Z" fill="#111" stroke="#fff" stroke-width="2.2" stroke-linejoin="round"/></svg>`,
    });
    const tramos = [];
    const pulsaciones = [];
    let punto = o.desde || { x: W * 0.7, y: H * 1.1, lienzo: true };
    const aqui = (p, t) => {
      if (p.lienzo) return { x: p.x, y: p.y };
      const r = enLienzo(v, v.zona(p.zona, p.captura), t);
      return { x: r.x + r.w * (p.ax ?? 0.5) + (p.dx || 0), y: r.y + r.h * (p.ay ?? 0.5) + (p.dy || 0) };
    };
    const c = {
      nodo: n,
      ir(t0, t1, destino) {
        tramos.push({ t0, t1, de: punto, a: destino });
        punto = destino;
        return c;
      },
      clic(t) {
        pulsaciones.push(t);
        const onda = nodo({ clase: 'onda', padre: capa });
        anim(onda, [
          [t, { o: 0, s: 0.2 }],
          [t + 0.04, { o: 1, s: 0.3 }],
          [t + 0.55, { o: 0, s: 1.3 }, 'sale'],
        ]);
        tarea((tt) => {
          if (tt < t - 0.1 || tt > t + 0.7) return;
          const p = aqui(punto_en(t), tt);
          onda.style.left = `${p.x}px`;
          onda.style.top = `${p.y}px`;
        });
        sonido(t, 'clic', 0.9);
        return c;
      },
      mostrar(t0, t1) {
        anim(n, [
          [t0, { o: 0 }],
          [t0 + 0.3, { o: 1 }],
          [t1, { o: 1 }],
          [t1 + 0.3, { o: 0 }],
        ]);
        return c;
      },
    };
    function punto_en(t) {
      let p = tramos.length ? tramos[0].de : punto;
      for (const tr of tramos) if (t >= tr.t0) p = t >= tr.t1 ? tr.a : p;
      return p;
    }
    tarea((t) => {
      let pos = null;
      let ultimo = tramos.length ? tramos[0].de : punto;
      for (const tr of tramos) {
        if (t < tr.t0) break;
        if (t >= tr.t1) {
          ultimo = tr.a;
          continue;
        }
        const u = curvas.muysuave((t - tr.t0) / (tr.t1 - tr.t0));
        const a = aqui(tr.de, t);
        const b = aqui(tr.a, t);
        // Un arco suave, como una mano, y no una recta de regla.
        const mx = (a.x + b.x) / 2 - (b.y - a.y) * 0.12;
        const my = (a.y + b.y) / 2 + (b.x - a.x) * 0.12;
        pos = {
          x: (1 - u) * (1 - u) * a.x + 2 * (1 - u) * u * mx + u * u * b.x,
          y: (1 - u) * (1 - u) * a.y + 2 * (1 - u) * u * my + u * u * b.y,
        };
      }
      if (!pos) pos = aqui(ultimo, t);
      let s = 1;
      for (const p of pulsaciones) if (t >= p - 0.08 && t <= p + 0.16) s = 0.86;
      n.style.left = `${pos.x}px`;
      n.style.top = `${pos.y}px`;
      n.style.transform = `scale(${s})`;
    });
    anim(n, [[0, { o: 0 }]]);
    return c;
  }

  /** Una página de un PDF, en papel, con sus zonas a mano. */
  function hoja(o) {
    const D = window.DATOS;
    const pdf = D.pdf[o.pdf];
    if (!pdf) throw new Error(`no hay pdf «${o.pdf}»`);
    // `zoom` acerca la página dentro de su marco, y `izquierda` (en puntos de
    // la página) la recorta por ese lado: para leer un ejercicio sin la
    // página entera alrededor.
    const zoom = o.zoom || 1;
    const izquierda = o.izquierda || 0;
    const escala = (o.ancho * zoom) / pdf.ancho;
    const altoPagina = pdf.alto * escala;
    const alto = o.alto || altoPagina;
    const raiz = nodo({ clase: 'hoja', padre: o.padre, estilo: { left: `${o.x}px`, top: `${o.y}px`, width: `${o.ancho}px`, height: `${alto}px` } });
    const img = nodo({ tag: 'img', padre: raiz, attrs: { src: pdf.src }, estilo: { position: 'absolute', left: `${-izquierda * escala}px`, top: `${-(o.desde || 0) * escala}px`, width: `${pdf.ancho * escala}px`, height: `${altoPagina}px` } });
    return {
      raiz,
      img,
      x: o.x,
      y: o.y,
      ancho: o.ancho,
      alto,
      zona(nombre) {
        const z = pdf.zonas[nombre];
        if (!z) throw new Error(`no hay zona «${nombre}» en ${o.pdf}`);
        // Recortada al marco: con zoom, la zona puede seguir más allá.
        const x = o.x + (z[0] - izquierda) * escala;
        const y = o.y + (z[1] - (o.desde || 0)) * escala;
        const x1 = Math.min(x + z[2] * escala, o.x + o.ancho - 6);
        const y1 = Math.min(y + z[3] * escala, o.y + alto - 6);
        return { x, y, w: Math.max(0, x1 - x), h: Math.max(0, y1 - y) };
      },
    };
  }

  // -------------------------------------------------------------- inicio ---

  function arrancar() {
    const D = window.DATOS;
    const G = crearTiempos(D.tiempos);
    const E = { W, H, nodo, anim, valor, tarea, sonido, curvas, palabras, marca, ventana, camara, enLienzo, resaltar, cursor, hoja, clamp };
    window.montaje(E, G, D);
    window.__duracion = G.total;
    window.__sonidos = sonidos;
    const imagenes = [...document.images].map((img) => (img.complete ? img.decode().catch(() => {}) : new Promise((r) => { img.onload = () => img.decode().then(r, r); img.onerror = r; })));
    window.__listo = Promise.all([document.fonts.ready, ...imagenes]).then(() => {
      pintar(0);
      return true;
    });
    window.__pintar = (t) => pintar(t);
  }

  window.Estudio = { arrancar, pintar };
})();
