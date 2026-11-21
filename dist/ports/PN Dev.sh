#!/bin/bash
# PN Dev — agente de pruebas por red para Pocket Native en la R36S.
# Queda abierto consultando a la PC (scripts/devserver.py) cada 20 s. Si hay un
# trabajo nuevo lo descarga, lo ejecuta y sube los resultados. Start (mientras
# espera) cierra el agente; también se cierra solo tras 3 h sin trabajos.
# Configuración: pocket-native/dev/agent.conf con SERVER=http://IP:8765 y TOKEN=...

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder=""
fi
if [ -n "$controlfolder" ]; then
  source "$controlfolder/control.txt"
  [ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
  get_controls
fi
ESUDO=${ESUDO:-sudo}
[ "$(id -u)" = 0 ] && ESUDO=""

PNDIR="$(cd "$(dirname "$0")/pocket-native" && pwd)"
TITLE=0004000000033500
GAME="$PNDIR/games/$TITLE"
DEVDIR="$PNDIR/dev"
mkdir -p "$DEVDIR/jobs"
exec > "$DEVDIR/agent.log" 2>&1
echo "== PN Dev $(date) =="

screen() {  # texto en la pantalla (consola de texto)
  printf '\033c\n  PN Dev - agente de pruebas (Pocket Native)\n\n%b\n' "$1" | $ESUDO tee /dev/tty1 >/dev/null 2>&1
}

if [ ! -f "$DEVDIR/agent.conf" ]; then
  screen "  Falta pocket-native/dev/agent.conf\n  (SERVER=... y TOKEN=...)"
  sleep 8; exit 1
fi
. "$DEVDIR/agent.conf"
export SERVER TOKEN PNDIR TITLE GAME DEVDIR ESUDO

# Cliente HTTP: curl si existe, si no wget.
http_get() {  # url archivo
  if command -v curl >/dev/null; then curl -fsS --connect-timeout 5 --max-time 900 -o "$2" "$1"
  else wget -q -T 10 -O "$2" "$1"; fi
}
http_post() {  # archivo url
  if command -v curl >/dev/null; then curl -fsS --connect-timeout 5 --max-time 300 --data-binary "@$1" "$2" >/dev/null
  else wget -q -T 30 -O /dev/null --post-file="$1" "$2"; fi
}
# Para los trabajos: fetch NOMBRE DESTINO [sha256]  (descomprime si termina en .gz)
fetch() {
  local name=$1 dest=$2 sum=${3:-}
  mkdir -p "$(dirname "$dest")"
  http_get "$SERVER/files/$name?t=$TOKEN" "$dest.part" || { echo "fetch $name: fallo"; return 1; }
  if [ -n "$sum" ] && [ "$(sha256sum "$dest.part" | cut -d' ' -f1)" != "$sum" ]; then
    echo "fetch $name: sha256 distinto"; rm -f "$dest.part"; return 1
  fi
  case $name in *.gz) gunzip -c "$dest.part" > "$dest" && rm -f "$dest.part" ;; *) mv -f "$dest.part" "$dest" ;; esac
  echo "fetch $name -> $dest ok"
}
# Para los trabajos: send ARCHIVO  (sube al servidor dentro de results/<trabajo>/)
send() {
  local i
  for i in 1 2 3 4 5; do
    http_post "$1" "$SERVER/upload/$JOB_ID/$(basename "$1")?t=$TOKEN" && { echo "send $(basename "$1") ok"; return 0; }
    sleep 5
  done
  echo "send $(basename "$1"): fallo"; return 1
}
# Para los trabajos: backup ARCHIVO  (copia ARCHIVO.bak una sola vez, antes de reemplazarlo)
backup() { [ -f "$1" ] && [ ! -f "$1.bak" ] && cp -p "$1" "$1.bak" && echo "respaldo $1.bak"; }
# Para los trabajos: restore ARCHIVO  (vuelve a la copia .bak)
restore() { [ -f "$1.bak" ] && cp -p "$1.bak" "$1" && echo "restaurado $1"; }
# El mismo entorno que pone pocket-native/run.sh.
pn_env() {
  local data="$GAME/data"
  mkdir -p "$data" "$PNDIR/config"
  export ZAKURO_FAST=1 ZAKURO_KMS=1 ZAKURO_DATA="$data" ZAKURO_RECOMPILED="$GAME/title.so" ZAKURO_SHADER_MANIFEST="$data/shaders.txt"
  export POCKET_NATIVE_TITLES="$PNDIR/titles" POCKET_NATIVE_POWER="$PNDIR/power.sh" POCKET_NATIVE_CONFIG="$PNDIR/config"
  if [ -f "$data/drops.txt" ]; then export ZAKURO_DROP_DRAWS="$(cat "$data/drops.txt")"; else unset ZAKURO_DROP_DRAWS; fi
}
# Para los trabajos: play NOMBRE SEGUNDOS [VAR=valor...]
#   Abre el juego SEGUNDOS (puedes jugar mientras tanto) y deja out/log_NOMBRE.txt.
play() {
  local name=$1 secs=$2; shift 2
  pn_env
  echo "==== play $name ${secs}s ($*)"
  ( cd "$GAME" && env "$@" timeout -s INT "$secs" "$PNDIR/pocket-native" "$GAME/game.3ds" ) > "$JOBDIR/out/log_$name.txt" 2>&1
  echo "exit $name: $?"
  "$PNDIR/power.sh" normal
}
# Para los trabajos: lastlog [NOMBRE]  (sube el log.txt de la última partida normal)
lastlog() { cp "$GAME/data/log.txt" "$JOBDIR/out/lastlog_${1:-game}.txt" 2>/dev/null && echo "lastlog ok"; }
export -f http_get http_post fetch send backup restore pn_env play lastlog

# Start (botón 13) mientras espera: cerrar el agente. Lee eventos crudos de js0.
STOP="$DEVDIR/stop"; rm -f "$STOP"
( stdbuf -o0 od -An -tx1 -w8 -v /dev/input/js0 2>/dev/null | while read -r _ _ _ _ v0 _ typ num; do
    [ "$typ" = "01" ] && [ "$v0" = "01" ] && [ "$num" = "0d" ] && touch "$STOP"
  done ) &
WATCHER=$!

es=$(pgrep -f "^/usr/bin/emulationstation/emulationstation( |$)" || true)
last=$(cat "$DEVDIR/last_job" 2>/dev/null)
idle_since=$(date +%s)
status="conectando con $SERVER..."
while :; do
  if [ -f "$STOP" ]; then break; fi
  if [ $(( $(date +%s) - idle_since )) -gt 10800 ]; then echo "3 h sin trabajos: cierre"; break; fi
  http_get "$SERVER/heartbeat?t=$TOKEN&last=${last:--}" /dev/null >/dev/null 2>&1 \
    && status="conectado a $SERVER" || status="SIN CONEXION con $SERVER (reintentando)"
  if http_get "$SERVER/job.txt?t=$TOKEN" "$DEVDIR/job.txt" 2>/dev/null; then
    JOB_ID=$(head -n1 "$DEVDIR/job.txt" | tr -cd 'A-Za-z0-9._-')
    if [ -n "$JOB_ID" ] && [ "$JOB_ID" != "$last" ]; then
      export JOB_ID JOBDIR="$DEVDIR/jobs/$JOB_ID"
      mkdir -p "$JOBDIR/out"
      screen "  Ejecutando trabajo $JOB_ID...\n  (no apagar)"
      if http_get "$SERVER/job.sh?t=$TOKEN" "$JOBDIR/job.sh"; then
        echo "== trabajo $JOB_ID $(date) =="
        [ -n "$es" ] && kill -STOP $es
        ( cd "$JOBDIR" && timeout "${JOB_TIMEOUT:-3600}" bash ./job.sh ) > "$JOBDIR/job.log" 2>&1
        echo "exit: $?" >> "$JOBDIR/job.log"
        [ -n "$es" ] && kill -CONT $es
        sync
        send "$JOBDIR/job.log"
        for f in "$JOBDIR"/out/*; do [ -f "$f" ] && send "$f"; done
        last=$JOB_ID; echo "$last" > "$DEVDIR/last_job"
        idle_since=$(date +%s)
        rm -f "$STOP"   # un Start dentro del juego no debe cerrar el agente
      fi
    fi
  fi
  screen "  $status\n  Ultimo trabajo: ${last:-ninguno}\n\n  Consulto cada 20 s.  Start: salir"
  for _ in $(seq 20); do [ -f "$STOP" ] && break; sleep 1; done
done

kill "$WATCHER" 2>/dev/null; pkill -f "od -An -tx1 -w8 -v /dev/input/js0" 2>/dev/null
screen "  Agente cerrado."; sleep 1
sync
[ -n "$controlfolder" ] && pm_finish
printf "\033c" | $ESUDO tee /dev/tty1 >/dev/null 2>&1
