#!/bin/bash
# OOT3D Dev — agente de pruebas para la R36S.
# Queda abierto consultando a la PC (scripts/devserver.py) cada 20 s. Si hay un
# trabajo nuevo lo descarga, lo ejecuta y sube los resultados. Start (mientras
# espera) cierra el agente; también se cierra solo tras 3 h sin trabajos.
# Configuración: oot3d/dev/agent.conf con SERVER=http://IP:8765 y TOKEN=...

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

GAMEDIR="$(cd "$(dirname "$0")/oot3d" && pwd)"
DEVDIR="$GAMEDIR/dev"
mkdir -p "$DEVDIR/jobs"
exec > "$DEVDIR/agent.log" 2>&1
echo "== OOT3D Dev $(date) =="

screen() {  # texto en la pantalla (consola de texto)
  printf '\033c\n  OOT3D Dev - agente de pruebas\n\n%b\n' "$1" | $ESUDO tee /dev/tty1 >/dev/null 2>&1
}

if [ ! -f "$DEVDIR/agent.conf" ]; then
  screen "  Falta oot3d/dev/agent.conf\n  (SERVER=... y TOKEN=...)"
  sleep 8; exit 1
fi
. "$DEVDIR/agent.conf"
export SERVER TOKEN GAMEDIR DEVDIR ESUDO

# Cliente HTTP: curl si existe, si no wget.
http_get() {  # url archivo
  # --max-time: si el anclaje USB parpadea, la conexión no queda colgada para siempre.
  if command -v curl >/dev/null; then curl -fsS --connect-timeout 5 --max-time 900 -o "$2" "$1"
  else wget -q -T 10 -O "$2" "$1"; fi
}
http_post() {  # archivo url
  if command -v curl >/dev/null; then curl -fsS --connect-timeout 5 --max-time 120 --data-binary "@$1" "$2" >/dev/null
  else wget -q -T 30 -O /dev/null --post-file="$1" "$2"; fi
}
# Para los trabajos: fetch NOMBRE DESTINO [sha256]  (descomprime si termina en .gz)
fetch() {
  local name=$1 dest=$2 sum=${3:-}
  http_get "$SERVER/files/$name?t=$TOKEN" "$dest.part" || { echo "fetch $name: fallo"; return 1; }
  if [ -n "$sum" ] && [ "$(sha256sum "$dest.part" | cut -d' ' -f1)" != "$sum" ]; then
    echo "fetch $name: sha256 distinto"; rm -f "$dest.part"; return 1
  fi
  case $name in *.gz) gunzip -c "$dest.part" > "$dest" && rm -f "$dest.part" ;; *) mv -f "$dest.part" "$dest" ;; esac
  echo "fetch $name -> $dest ok"
}
# Para los trabajos: send ARCHIVO  (sube al servidor dentro de results/<trabajo>/)
# Reintenta: una subida cortada no pierde resultados.
send() {
  local i
  for i in 1 2 3 4 5; do
    http_post "$1" "$SERVER/upload/$JOB_ID/$(basename "$1")?t=$TOKEN" && { echo "send $(basename "$1") ok"; return 0; }
    sleep 5
  done
  echo "send $(basename "$1"): fallo"; return 1
}
# Para los trabajos: entorno estándar del juego (GPU real, paralelo, caché de shaders).
oot3d_env() {
  export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"
  export SDL_GAMECONTROLLERCONFIG="${sdl_controllerconfig:-$SDL_GAMECONTROLLERCONFIG}"
  export TRIAEVUM_PARALLEL_PRESENTATION=1 TRIAEVUM_INPUT_ADMISSION=0
  export OOT3D_GL_PROGRAM_CACHE="$GAMEDIR/shadercache"
}
# Argumentos estándar del juego en benchmark (FRAMES/WARMUP ajustables por trabajo).
oot3d_args() {
  OOT3D_ARGS=(--a32-process-manifest "$GAMEDIR/game/oot3d_native_process_manifest.json"
    --resource-root "$GAMEDIR/resources.o2r" --config "$GAMEDIR/config/oot3d_native_game.json"
    --controls-config "$GAMEDIR/config/oot3d_controls.json" --ui-profile topscreen
    --topscreen-config "$GAMEDIR/config/topscreen_ui.json"
    --topscreen-texture-overrides "$GAMEDIR/config/atlas_overrides.o3tu" --save-data "$GAMEDIR/savedata"
    --quick-state "$GAMEDIR/savedata/quick.oot3dsav" --renderer opengl
    --gameplay-timing native30_no_interpolation --parallel-presentation --width 640 --height 480
    --throughput-benchmark --disable-audio --frames "${FRAMES:-600}" --benchmark-warmup-frames "${WARMUP:-100}")
}
# Para los trabajos: bench NOMBRE BINARIO [VAR=valor...]
#   -> out/bench_NOMBRE.json + out/log_NOMBRE.txt (BINARIO "game" = el juego instalado)
bench() {
  local name=$1 bin=$2; shift 2
  [ "$bin" = game ] && bin="$GAMEDIR/oot3d_r36s"
  oot3d_env; oot3d_args
  echo "==== bench $name ($*)"
  ( cd "$GAMEDIR" && env "$@" OOT3D_HANG_DUMP_SECONDS=40 timeout "${BENCH_TIMEOUT:-400}" "$bin" "${OOT3D_ARGS[@]}"       --output "$JOBDIR/out/bench_$name.json" > "$JOBDIR/out/log_$name.txt" 2>&1 )
  echo "exit $name: $?"
}
# Para los trabajos: perfrec NOMBRE BINARIO [VAR=valor...]  -> out/perf_NOMBRE.data (solo espacio de usuario)
perfrec() {
  local name=$1 bin=$2 P="$DEVDIR/perf"; shift 2
  [ "$bin" = game ] && bin="$GAMEDIR/oot3d_r36s"
  [ -x "$P/perf" ] || { echo "perf no instalado en $P"; return 1; }
  oot3d_env; oot3d_args
  echo "==== perf $name ($*)"
  ( cd "$GAMEDIR" && env "$@" LD_LIBRARY_PATH="$P/lib:$LD_LIBRARY_PATH" timeout "${BENCH_TIMEOUT:-400}"       "$P/perf" record -e cpu-clock:u -F 499 -o "$JOBDIR/out/perf_$name.data" -- "$bin" "${OOT3D_ARGS[@]}"       --output "$JOBDIR/out/bench_perf_$name.json" > "$JOBDIR/out/log_perf_$name.txt" 2>&1 )
  echo "exit perf $name: $?"
}
export -f http_get http_post fetch send oot3d_env oot3d_args bench perfrec

# Start (botón 13) mientras espera: cerrar el agente. Lee eventos crudos de js0.
STOP="$DEVDIR/stop"; rm -f "$STOP"
( stdbuf -o0 od -An -tx1 -w8 -v /dev/input/js0 2>/dev/null | while read -r _ _ _ _ v0 _ typ num; do
    [ "$typ" = "01" ] && [ "$v0" = "01" ] && [ "$num" = "0d" ] && touch "$STOP"
  done ) &
WATCHER=$!

echo performance | $ESUDO tee /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor >/dev/null 2>&1
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
        ( cd "$JOBDIR" && timeout "${JOB_TIMEOUT:-1800}" bash ./job.sh ) > "$JOBDIR/job.log" 2>&1
        echo "exit: $?" >> "$JOBDIR/job.log"
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
