#!/bin/bash
#
# Didacta — compilar
#
# Doble clic en Finder abre esto en Terminal y arranca el menú. También sirve
# desde la línea de órdenes con un objetivo directo:
#
#   ./build.command macos
#   ./build.command instalar
#   ./build.command --list
#
# Sin dependencias: bash, flutter, python3 y lo que ya haga falta para
# compilar. Nada que instalar para usarlo.
#
# **Por qué existe.** Compilar Didacta y dejarla puesta son cinco órdenes
# --compilar, cerrar la que está abierta, borrar la vieja, copiar la nueva,
# abrirla-- y saltarse la segunda copia encima de una aplicación en marcha y
# la deja a medias. Eso no es conocimiento que deba vivir en la cabeza de
# nadie ni en el historial de una terminal.

set -uo pipefail

cd "$(dirname "$0")" || exit 1
ROOT="$(pwd)"
APP="$ROOT/app"

# Dónde se instala: `~/Applications`, no `/Applications`.
#
# En una sesión se instaló en las dos y acabaron dos Didactas en el Dock: la
# de `/Applications` con el trabajo del día y la de `~/Applications` --la que
# se abría-- vieja. Dos copias es peor que una en el sitio menos canónico.
INSTALLED="$HOME/Applications/Didacta.app"

# ─────────────────────────────────────────────────────────────── apariencia ──
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
  GREEN=$'\033[38;5;149m'; BLUE=$'\033[38;5;111m'
  AMBER=$'\033[38;5;215m'; RED=$'\033[38;5;210m'
else
  BOLD=""; DIM=""; RESET=""; GREEN=""; BLUE=""; AMBER=""; RED=""
fi

say()   { printf '%s\n' "$*"; }
step()  { printf '%s▸%s %s\n' "$BLUE" "$RESET" "$*"; }
ok()    { printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn()  { printf '%s!%s %s\n' "$AMBER" "$RESET" "$*"; }
fail()  { printf '%s✗%s %s\n' "$RED" "$RESET" "$*"; }

banner() {
  clear 2>/dev/null || true
  printf '%s\n' "$BOLD"
  cat <<'ART'
   ┌─────────────────────────────────────────┐
   │   D I D A C T A   ·   compilar          │
   └─────────────────────────────────────────┘
ART
  printf '%s' "$RESET"
  printf '   %s%s · %s · Flutter %s%s\n\n' \
    "$DIM" "$(app_version)" "$(git_summary)" "$(flutter_version)" "$RESET"
}

# ──────────────────────────────────────────────────────────────── contexto ──

app_version() {
  local line
  line="$(grep -m1 '^version:' "$APP/pubspec.yaml" 2>/dev/null)"
  printf '%s' "${line#version: }"
}

git_summary() {
  local branch commit dirty
  branch="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 0
  commit="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null)"
  dirty=""
  [[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]] && dirty=" +cambios"
  printf '%s@%s%s' "$branch" "$commit" "$dirty"
}

flutter_version() {
  flutter --version 2>/dev/null | head -1 | awk '{print $2}'
}

# Flutter, TeX y Python no siempre están en el PATH de una sesión abierta con
# doble clic: launchd le da a una aplicación `/usr/bin:/bin:/usr/sbin:/sbin` y
# nada más, y eso no incluye ni el SDK ni `/Library/TeX/texbin`.
prepare_environment() {
  local candidate
  if ! command -v flutter >/dev/null 2>&1; then
    for candidate in "$HOME/flutter-sdk/bin" "$HOME/flutter/bin" \
                     "$HOME/fvm/default/bin" "/opt/homebrew/bin" "/usr/local/bin"; do
      [[ -x "$candidate/flutter" ]] && PATH="$candidate:$PATH" && break
    done
  fi
  if ! command -v flutter >/dev/null 2>&1; then
    fail "No encuentro flutter. Añádelo al PATH y vuelve a intentarlo."
    return 1
  fi

  # TeX solo hace falta para compilar material, no la aplicación, así que su
  # ausencia no para nada: se avisa donde toca y se sigue.
  [[ -d /Library/TeX/texbin ]] && PATH="/Library/TeX/texbin:$PATH"
  export PATH
  return 0
}

# ──────────────────────────────────────────────────────────────── objetivos ──
# id|nombre|qué hace|ruta del artefacto (relativa a la raíz)
#
# Solo lo que **esta** máquina puede hacer. Flutter compila para el escritorio
# en el que corre, así que ofrecer Linux o Windows desde un Mac sería ofrecer
# un botón que siempre falla; de eso se encarga la integración continua.

TARGETS=(
  "instalar|Compilar e instalar en ~/Applications||"
  "macos|macOS · publicación|build macos --release|app/build/macos/Build/Products/Release/Didacta.app"
  "macos-debug|macOS · pruebas|build macos --debug|app/build/macos/Build/Products/Debug/Didacta.app"
  "web|Web · publicación|build web --release|app/build/web"
  "paquete|Empaquetar para repartir (DMG + ZIP)||"
  "check|Comprobar · la aplicación (analyze + tests)||"
  "motor|Comprobar · el motor (tests de Python)||"
  "todo|Comprobar · las dos cosas||"
)

target_field() { # id campo(2|3|4)
  local entry
  for entry in "${TARGETS[@]}"; do
    [[ "${entry%%|*}" == "$1" ]] || continue
    printf '%s' "$(printf '%s' "$entry" | cut -d'|' -f"$2")"
    return 0
  done
  return 1
}

# ─────────────────────────────────────────────────────────── menú de flechas ──
# Devuelve el índice elegido en CHOICE. ↑ ↓ mueven, Enter elige, q sale.

CHOICE=-1
menu() {
  local title="$1"; shift
  local options=("$@")
  local selected=0 key rest
  local count=${#options[@]}

  printf '%s%s%s\n\n' "$BOLD" "$title" "$RESET"
  local first=1
  while true; do
    if [[ $first -eq 0 ]]; then
      printf '\033[%dA' "$count"   # subir para redibujar en el mismo sitio
    fi
    first=0
    local i
    for ((i = 0; i < count; i++)); do
      printf '\033[2K'             # limpiar la línea entera
      if [[ $i -eq $selected ]]; then
        printf '  %s▸ %s%s\n' "$GREEN" "${options[$i]}" "$RESET"
      else
        printf '    %s%s%s\n' "$DIM" "${options[$i]}" "$RESET"
      fi
    done

    IFS= read -rsn1 key || return 1
    case "$key" in
      $'\x1b')
        # Una flecha llega como ESC [ A. El timeout es entero a propósito:
        # macOS trae bash 3.2, que rechaza uno decimal y hacía que cualquier
        # flecha se leyera como un ESC suelto, es decir, como «salir».
        read -rsn2 -t 1 rest || rest=""
        case "$rest" in
          "[A") ((selected = (selected - 1 + count) % count)) ;;
          "[B") ((selected = (selected + 1) % count)) ;;
          "")   CHOICE=-1; return 1 ;;
        esac
        ;;
      "" ) CHOICE=$selected; printf '\n'; return 0 ;;   # Enter
      k|w) ((selected = (selected - 1 + count) % count)) ;;
      j|s) ((selected = (selected + 1) % count)) ;;
      q)   CHOICE=-1; printf '\n'; return 1 ;;
      [1-9])
        if ((key <= count)); then
          CHOICE=$((key - 1)); printf '\n'; return 0
        fi
        ;;
    esac
  done
}

# ──────────────────────────────────────────────────────────────── compilar ──

BUILD_TARGET=""
BUILD_ARTIFACT=""
BUILD_SECONDS=0

human_size() { # ruta
  [[ -e "$1" ]] || { printf '—'; return; }
  du -sh "$1" 2>/dev/null | awk '{print $1}'
}

human_time() { # segundos
  local s=$1
  if ((s < 60)); then printf '%ds' "$s"; else printf '%dm %02ds' $((s / 60)) $((s % 60)); fi
}

# Un aviso del sistema: una compilación de release tarda lo suficiente como
# para irse a otra cosa, y volver a mirar la ventana es lo que sobra.
notify() { # título mensaje
  osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
}

# Cierra la Didacta que esté abierta y espera a que se vaya de verdad.
#
# Copiar encima de una aplicación en marcha la deja a medias: macOS no lo
# impide, y lo que queda es un paquete que abre y se cierra solo.
close_running() {
  pgrep -f "Didacta.app/Contents/MacOS/Didacta" >/dev/null 2>&1 || return 0
  step "Cerrando la Didacta que está abierta"
  pkill -f "Didacta.app/Contents/MacOS/Didacta" 2>/dev/null
  local waited=0
  while pgrep -f "Didacta.app/Contents/MacOS/Didacta" >/dev/null 2>&1; do
    sleep 1
    ((waited++))
    if ((waited > 15)); then
      warn "Sigue abierta. Ciérrala a mano y vuelve a intentarlo."
      return 1
    fi
  done
  return 0
}

install_build() { # ruta del .app recién compilado
  local built="$1"
  [[ -d "$built" ]] || { fail "No encuentro $built"; return 1; }
  close_running || return 1

  step "Instalando en ${INSTALLED/#$HOME/~}"
  mkdir -p "$(dirname "$INSTALLED")"
  rm -rf "$INSTALLED" && cp -R "$built" "$INSTALLED" || {
    fail "No se pudo copiar"
    return 1
  }
  ok "Instalada"
  open -a "$INSTALLED" && ok "Abierta" || warn "No se pudo abrir"
  return 0
}

package_build() { # ruta del .app
  local built="$1" version out
  [[ -d "$built" ]] || { fail "Compila primero: no hay .app que empaquetar"; return 1; }
  version="$(app_version)"
  version="${version%%+*}"
  out="$ROOT/dist/$version"
  mkdir -p "$out"

  step "Empaquetando $version"
  if [[ ! -x "$ROOT/packaging/macos/package.sh" ]]; then
    fail "Falta packaging/macos/package.sh"
    return 1
  fi
  "$ROOT/packaging/macos/package.sh" "$built" "$version" "$out" || return 1
  ok "En ${out#"$ROOT"/}"
  BUILD_ARTIFACT="$out"
  return 0
}

run_build() { # id
  local id="$1" name command artifact started ended status
  name="$(target_field "$id" 2)"
  command="$(target_field "$id" 3)"
  artifact="$(target_field "$id" 4)"

  banner
  step "$name"
  say ""

  local release="app/build/macos/Build/Products/Release/Didacta.app"
  started=$(date +%s)
  case "$id" in
    check)
      ( cd "$APP" && flutter analyze && flutter test )
      status=$?
      ;;
    motor)
      ( cd "$ROOT" && python3 -m unittest discover -s tests )
      status=$?
      ;;
    todo)
      ( cd "$ROOT" && python3 -m unittest discover -s tests ) &&
        ( cd "$APP" && flutter analyze && flutter test )
      status=$?
      ;;
    instalar)
      ( cd "$APP" && flutter build macos --release ) && install_build "$ROOT/$release"
      status=$?
      artifact="$release"
      ;;
    paquete)
      ( cd "$APP" && flutter build macos --release ) && package_build "$ROOT/$release"
      status=$?
      artifact=""
      ;;
    *)
      # shellcheck disable=SC2086
      ( cd "$APP" && flutter $command )
      status=$?
      ;;
  esac
  ended=$(date +%s)
  BUILD_SECONDS=$((ended - started))
  BUILD_TARGET="$id"
  [[ -n "$artifact" && -e "$ROOT/$artifact" ]] && BUILD_ARTIFACT="$ROOT/$artifact"

  say ""
  if [[ $status -ne 0 ]]; then
    fail "$name — falló (código $status) en $(human_time "$BUILD_SECONDS")"
    notify "Didacta — falló" "$name"
    return $status
  fi

  ok "$name — listo en $(human_time "$BUILD_SECONDS")"
  notify "Didacta — listo" "$name · $(human_time "$BUILD_SECONDS")"
  say ""
  printf '  %sVersión%s    %s\n' "$DIM" "$RESET" "$(app_version)"
  printf '  %sGit%s        %s\n' "$DIM" "$RESET" "$(git_summary)"
  printf '  %sFlutter%s    %s\n' "$DIM" "$RESET" "$(flutter_version)"
  printf '  %sTiempo%s     %s\n' "$DIM" "$RESET" "$(human_time "$BUILD_SECONDS")"
  if [[ -n "$BUILD_ARTIFACT" ]]; then
    printf '  %sTamaño%s     %s\n' "$DIM" "$RESET" "$(human_size "$BUILD_ARTIFACT")"
    printf '  %sArtefacto%s  %s\n' "$DIM" "$RESET" "${BUILD_ARTIFACT#"$ROOT"/}"
  fi
  say ""
  return 0
}

# ───────────────────────────────────────────────────── después de compilar ──

reveal() {
  if [[ -z "$BUILD_ARTIFACT" ]]; then
    warn "Esta comprobación no deja ningún archivo que abrir."
    return
  fi
  open -R "$BUILD_ARTIFACT" 2>/dev/null && ok "Abierto en Finder" ||
    warn "No he podido abrir Finder"
}

after_build() {
  local options=()
  case "$BUILD_TARGET" in
    macos|macos-debug)
      options=(
        "Instalar en ~/Applications y abrir"
        "Abrir la carpeta en Finder"
        "Compilar otra versión"
        "Salir"
      )
      ;;
    instalar|paquete)
      options=(
        "Abrir la carpeta en Finder"
        "Compilar otra versión"
        "Salir"
      )
      ;;
    *)
      options=("Compilar otra versión" "Salir")
      ;;
  esac

  while true; do
    say ""
    menu "¿Y ahora?" "${options[@]}" || return 1
    case "${options[$CHOICE]}" in
      "Instalar en ~/Applications y abrir") install_build "$BUILD_ARTIFACT" ;;
      "Abrir la carpeta en Finder") reveal ;;
      "Compilar otra versión") return 0 ;;
      "Salir") return 1 ;;
    esac
  done
}

# ─────────────────────────────────────────────────────────────────── inicio ──

usage() {
  say "Uso: ./build.command [objetivo]"
  say ""
  say "Objetivos:"
  local entry
  for entry in "${TARGETS[@]}"; do
    printf '  %-14s %s\n' "${entry%%|*}" "$(printf '%s' "$entry" | cut -d'|' -f2)"
  done
}

main() {
  prepare_environment || { read -rsn1 -p "Pulsa una tecla…"; exit 1; }

  if [[ $# -gt 0 ]]; then
    case "$1" in
      -h|--help|help) usage; exit 0 ;;
      -l|--list) usage; exit 0 ;;
      *)
        if ! target_field "$1" 2 >/dev/null; then
          fail "No conozco el objetivo «$1»."
          say ""
          usage
          exit 2
        fi
        run_build "$1"
        exit $?
        ;;
    esac
  fi

  local names=() entry
  for entry in "${TARGETS[@]}"; do
    names+=("$(printf '%s' "$entry" | cut -d'|' -f2)")
  done
  names+=("Salir")

  while true; do
    banner
    if ! menu "¿Qué compilo?" "${names[@]}"; then break; fi
    [[ $CHOICE -eq $((${#names[@]} - 1)) ]] && break

    local id="${TARGETS[$CHOICE]%%|*}"
    if run_build "$id"; then
      after_build || break
    else
      say ""
      read -rsn1 -p "Pulsa una tecla para volver al menú…"
    fi
  done

  say ""
  say "Hasta luego."
}

main "$@"
