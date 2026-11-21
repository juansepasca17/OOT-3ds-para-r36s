#!/bin/bash
# ab-fix2: A/B sin jugar con --probe (mismo recorrido, reloj fijo) fix1 vs fix2, y deja fix2 instalado
# si no falla. Usa copias de data/ sin la partida del usuario.
FRAMES=${FRAMES:-14400}
SUM_PN=@SUM_PN@
SUM_SO=@SUM_SO@
SUM_PATCH=@SUM_PATCH@

fetch pn-fix2.gz "$PNDIR/pocket-native.fix2" $SUM_PN || exit 1
fetch title-fix2.so.gz "$GAME/title.fix2.so" $SUM_SO || exit 1
fetch romfs-es.patch "$DEVDIR/romfs-es.patch" $SUM_PATCH || exit 1
chmod +x "$PNDIR/pocket-native.fix2"
# fix1 = lo instalado ahora
cp -p "$PNDIR/pocket-native" "$PNDIR/pocket-native.fix1"
cp -p "$GAME/title.so" "$GAME/title.fix1.so"

probe() {  # probe NOMBRE BINARIO SO [es]
  local name=$1 bin=$2 so=$3 es=${4:-}
  local d="$DEVDIR/bench/$name"
  rm -rf "$d"; mkdir -p "$d/data"
  # caché de shaders y listas, sin la partida (user/) ni logs
  ( cd "$GAME/data" && for f in *; do case $f in user|log.txt|romfs.patch) ;; *) cp -r "$f" "$d/data/" ;; esac; done )
  if [ -n "$es" ]; then
    cp "$DEVDIR/romfs-es.patch" "$d/data/romfs.patch"
    printf 'language = 5\nregion = 1\n\n[options]\n' > "$d/data/settings.toml"
  else
    printf 'language = 1\nregion = 1\n\n[options]\n' > "$d/data/settings.toml"
  fi
  pn_env
  echo "==== probe $name"
  ( cd "$d" && ZAKURO_DATA="$d/data" ZAKURO_RECOMPILED="$so" ZAKURO_CLOCK=1700000000000 \
      timeout 1500 "$bin" --probe "$GAME/game.3ds" "$FRAMES" > "$d/log.txt" 2>&1 )
  echo "exit $name: $?"
  cp "$d/log.txt" "$JOBDIR/out/log_$name.txt"
  cp "$d/probe-0004000000033500/report.md" "$JOBDIR/out/report_$name.md" 2>/dev/null
  for b in "$d"/probe-0004000000033500/frame-*.bmp; do [ -f "$b" ] && gzip -c "$b" > "$JOBDIR/out/${name}_$(basename "$b").gz"; done
}

probe a-fix1 "$PNDIR/pocket-native.fix1" "$GAME/title.fix1.so"
probe b-fix2 "$PNDIR/pocket-native.fix2" "$GAME/title.fix2.so"
FRAMES=4000 probe c-fix2-es "$PNDIR/pocket-native.fix2" "$GAME/title.fix2.so" es
"$PNDIR/power.sh" normal

# instalar fix2 si su probe no falló (report dice "Still running")
if grep -q "Still running" "$JOBDIR/out/report_b-fix2.md" 2>/dev/null; then
  mv -f "$PNDIR/pocket-native.fix2" "$PNDIR/pocket-native"
  mv -f "$GAME/title.fix2.so" "$GAME/title.so"
  cp "$DEVDIR/romfs-es.patch" "$GAME/data/romfs.patch"
  sed -i 's/^language = .*/language = 5/' "$GAME/data/settings.toml"
  echo "fix2 instalado (respaldo: pocket-native.fix1, title.fix1.so), espanol activado"
else
  echo "fix2 NO instalado: el probe fallo"
fi
sync
