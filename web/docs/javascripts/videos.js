/* El reproductor de los videotutoriales.
 *
 * Todo lo que lleva `data-video="A1"` --las tarjetas de la galería, el
 * recuadro «En vídeo» de cada página, la cabecera de la portada-- abre el
 * vídeo encima de la página, sin salir de ella. Sin JavaScript, esos mismos
 * enlaces llevan a la página del vídeo, que tiene su propio reproductor: esto
 * es una comodidad, no el único camino.
 *
 * Los datos no van en cada página: se piden la primera vez que se abre uno,
 * de `videos/catalogo.json`, que escribe `web/hooks/videos.py` al construir.
 *
 * Y en la página de un vídeo, los capítulos saltan a su momento del
 * reproductor de la página.
 */
(function () {
  'use strict';

  var script = document.currentScript;
  var urlCatalogo = new URL('../videos/catalogo.json', script.src);
  var raiz = new URL('../', urlCatalogo);
  var catalogo = null;
  var dialogo = null;
  var vuelta = null; // el elemento al que devolver el foco al cerrar

  var ICONO = {
    play: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5.5v13a1 1 0 0 0 1.5.86l10.2-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5z"/></svg>',
    cerrar: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg>',
    otra: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5V2L7 6l5 4V7a5 5 0 1 1-5 5H5a7 7 0 1 0 7-7z"/></svg>',
  };

  function pedirCatalogo() {
    if (!catalogo) {
      catalogo = fetch(urlCatalogo).then(function (r) {
        if (!r.ok) throw new Error(r.status);
        return r.json();
      });
    }
    return catalogo;
  }

  function absoluta(url) {
    return new URL(url, raiz).href;
  }

  function reloj(s) {
    s = Math.round(s);
    return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
  }

  function texto(s) {
    var d = document.createElement('div');
    d.textContent = s;
    return d.innerHTML;
  }

  // ---------------------------------------------------------- el diálogo --

  function crearDialogo() {
    dialogo = document.createElement('dialog');
    dialogo.className = 'dv-lightbox';
    dialogo.setAttribute('aria-labelledby', 'dv-titulo');
    dialogo.innerHTML =
      '<div class="dv-lightbox__panel">' +
      '<div class="dv-lightbox__head"><span class="dv-code"></span><h2 id="dv-titulo"></h2><small></small>' +
      '<button type="button" class="dv-lightbox__close" aria-label="Cerrar el vídeo">' + ICONO.cerrar + '</button></div>' +
      '<div class="dv-lightbox__stage"><video controls playsinline preload="metadata"></video>' +
      '<div class="dv-lightbox__end" aria-live="polite"></div></div>' +
      '<div class="dv-lightbox__foot"><div class="dv-lightbox__chapters" role="group" aria-label="Capítulos"></div>' +
      '<div class="dv-lightbox__links"><a class="dv-boton" href="#">Transcripción</a></div></div>' +
      '</div>';
    document.body.appendChild(dialogo);

    var video = dialogo.querySelector('video');
    dialogo.querySelector('.dv-lightbox__close').addEventListener('click', cerrar);
    // Pulsar fuera del vídeo, en el fondo oscuro, también cierra.
    dialogo.addEventListener('click', function (ev) {
      if (ev.target === dialogo) cerrar();
    });
    dialogo.addEventListener('close', alCerrar);
    // Escape cierra. Un diálogo modal ya lo hace solo, pero no en todos los
    // navegadores ni con cualquier cosa enfocada, y la tecla de salir de un
    // vídeo tiene que funcionar siempre.
    document.addEventListener('keydown', function (ev) {
      if (ev.key === 'Escape' && dialogo.open) {
        ev.preventDefault();
        ev.stopPropagation();
        cerrar();
      }
    }, true);
    video.addEventListener('timeupdate', marcarCapitulo);
    video.addEventListener('play', function () {
      dialogo.querySelector('.dv-lightbox__end').classList.remove('dv-visible');
    });
    video.addEventListener('ended', alTerminar);
  }

  function abrir(codigo, desde) {
    return pedirCatalogo().then(function (datos) {
      var v = datos[codigo];
      if (!v) return false;
      if (!dialogo) crearDialogo();
      vuelta = desde || document.activeElement;

      var video = dialogo.querySelector('video');
      dialogo.dataset.codigo = codigo;
      dialogo.querySelector('.dv-code').textContent = codigo;
      dialogo.querySelector('h2').textContent = v.titulo;
      dialogo.querySelector('.dv-lightbox__head small').textContent = v.ruta + ' · ' + v.duracion;
      dialogo.querySelector('.dv-lightbox__links a').href = absoluta(v.pagina);
      dialogo.querySelector('.dv-lightbox__end').classList.remove('dv-visible');

      video.poster = absoluta(v.portada);
      video.innerHTML =
        '<source src="' + absoluta(v.mp4) + '" type="video/mp4">' +
        '<track kind="subtitles" srclang="es" label="Castellano" src="' + absoluta(v.subtitulos) + '">' +
        '<track kind="chapters" srclang="es" label="Capítulos" src="' + absoluta(v.capitulos_vtt) + '">';
      video.load();

      var caps = dialogo.querySelector('.dv-lightbox__chapters');
      caps.innerHTML = v.capitulos
        .map(function (c) {
          return '<button type="button" data-t="' + c.t + '"><span>' + reloj(c.t) + '</span>' + texto(c.titulo) + '</button>';
        })
        .join('');
      caps.querySelectorAll('button').forEach(function (b) {
        b.addEventListener('click', function () {
          video.currentTime = parseFloat(b.dataset.t);
          video.play();
        });
      });

      if (!dialogo.open) dialogo.showModal();
      history.replaceState(null, '', '#video-' + codigo.toLowerCase());
      var promesa = video.play();
      if (promesa) promesa.catch(function () {});
      return true;
    });
  }

  function cerrar() {
    if (dialogo && dialogo.open) dialogo.close();
  }

  function alCerrar() {
    var video = dialogo.querySelector('video');
    video.pause();
    // Soltar el fichero: si no, el navegador lo sigue descargando cerrado.
    video.removeAttribute('src');
    video.innerHTML = '';
    video.load();
    if (/^#video-/.test(location.hash)) history.replaceState(null, '', location.pathname + location.search);
    if (vuelta && vuelta.focus) vuelta.focus();
  }

  function marcarCapitulo() {
    var t = dialogo.querySelector('video').currentTime;
    var botones = dialogo.querySelectorAll('.dv-lightbox__chapters button');
    var activo = null;
    botones.forEach(function (b) {
      if (parseFloat(b.dataset.t) <= t + 0.05) activo = b;
    });
    botones.forEach(function (b) {
      b.classList.toggle('dv-activo', b === activo);
    });
  }

  function alTerminar() {
    pedirCatalogo().then(function (datos) {
      var v = datos[dialogo.dataset.codigo];
      var fin = dialogo.querySelector('.dv-lightbox__end');
      var html = '';
      if (v.siguiente) {
        html +=
          '<small>El siguiente</small><strong>' + v.siguiente.codigo + ' · ' + texto(v.siguiente.titulo) + '</strong>' +
          '<div><button type="button" class="dv-boton dv-boton--verde" data-siguiente="' + v.siguiente.codigo + '">' +
          ICONO.play + 'Verlo</button>';
      } else {
        html += '<small>Has llegado al final</small><strong>' + texto(v.titulo) + '</strong><div>';
      }
      html += '<button type="button" class="dv-boton" data-otra>' + ICONO.otra + 'Otra vez</button></div>';
      fin.innerHTML = html;
      fin.classList.add('dv-visible');
      var sig = fin.querySelector('[data-siguiente]');
      if (sig) {
        sig.addEventListener('click', function () {
          abrir(sig.dataset.siguiente, vuelta);
        });
        sig.focus();
      }
      fin.querySelector('[data-otra]').addEventListener('click', function () {
        var video = dialogo.querySelector('video');
        video.currentTime = 0;
        video.play();
      });
    });
  }

  // ----------------------------------------------------------- enganchar --

  document.addEventListener('click', function (ev) {
    if (ev.defaultPrevented || ev.button !== 0 || ev.metaKey || ev.ctrlKey || ev.shiftKey || ev.altKey) return;
    var enlace = ev.target.closest('[data-video]');
    if (!enlace || typeof HTMLDialogElement !== 'function') return;
    ev.preventDefault();
    abrir(enlace.dataset.video, enlace).then(function (ok) {
      // Si algo falla --sin conexión, el catálogo no está--, a su página.
      if (!ok && enlace.href) location.href = enlace.href;
    }, function () {
      if (enlace.href) location.href = enlace.href;
    });
  });

  // `…/videos/#video-a1` abre el A1 al llegar: es el enlace para compartir.
  function desdeLaDireccion() {
    var m = /^#video-([a-l]\d+)$/i.exec(location.hash);
    if (m && typeof HTMLDialogElement === 'function') abrir(m[1].toUpperCase(), null);
  }

  // En la página de un vídeo, los capítulos y las marcas de la transcripción
  // mueven su reproductor.
  function capitulosDeLaPagina() {
    var video = document.querySelector('.dv-player video');
    if (!video) return;
    var enlaces = document.querySelectorAll('.md-typeset a[href^="#t="]');
    enlaces.forEach(function (a) {
      a.addEventListener('click', function (ev) {
        ev.preventDefault();
        video.currentTime = parseFloat(a.getAttribute('href').slice(3));
        video.play();
        video.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
      });
    });
    var lista = document.querySelectorAll('.dv-chapters a');
    video.addEventListener('timeupdate', function () {
      var activo = null;
      lista.forEach(function (a) {
        if (parseFloat(a.dataset.t) <= video.currentTime + 0.05) activo = a;
      });
      lista.forEach(function (a) {
        a.classList.toggle('dv-activo', a === activo);
      });
    });
  }

  function arrancar() {
    desdeLaDireccion();
    capitulosDeLaPagina();
    window.addEventListener('hashchange', desdeLaDireccion);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arrancar);
  else arrancar();
})();
