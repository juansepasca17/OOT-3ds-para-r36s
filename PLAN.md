# Plan — OoT3D (TriAevum) en R36S / dArkOS RE

Estado: **Fase 0 en curso** · Última actualización: 2026-10-25

## Estructura de la carpeta

```
OOT 3ds/
├── PLAN.md                  ← este documento
├── PROMPT_MEJORADO.md       ← especificación completa del proyecto
├── rom/                     ← tu ROM .cci (privada, nunca se sube a ningún lado)
├── repos/
│   ├── TriAevum/            ← runtime + generador AOT (último commit 2026-10-22)
│   └── dArkOS/              ← scripts de construcción del SO (referencia de libs y SDL2)
├── deps/                    ← libmali G31, sysroot arm64, toolchains
├── work/                    ← extracción de la ROM, C++ generado, builds (privado)
└── dist/ports/oot3d/        ← ENTREGA FINAL: lo que se copia a la SD + OOT3D.sh
```

## Fases y puertas de decisión

### Fase 0 — Entorno (en curso)
- [x] Clonar TriAevum (`8f69a26`, 2026-10-22) y dArkOS.
- [x] Verificar la ROM: desencriptada, USA Rev 1, SHA-1 idéntico a No-Intro 1259 → soportada.
- [ ] Instalar WSL2 **Debian trixie** (mismo glibc 2.41 que dArkOS).
- [ ] Toolchain: clang/LLVM, CMake ≥ 3.26, Ninja, Python 3, `dpkg --add-architecture arm64` con
      `libsdl2-dev:arm64`, `libgles-dev:arm64`, `libegl-dev:arm64`, `libstdc++-dev:arm64`, y `qemu-user-static`.
- [ ] Descargar `libmali-bifrost-g31-rxp0-gbm.so` (aarch64) desde `christianhaitian/rk3326_core_builds`.

### Fase 1 — Datos del juego y referencia x86 en WSL
- Forge `prepare` + `verify`: extraer `code.bin`, `exheader.bin` y `romfs.bin` de la ROM.
- Generar el IR y los 256 shards C++ (`build-title` / `generate_whole_aot_cpp.py`).
- Compilar el producto Linux x86-64 con el backend OpenGL (el mismo que usa Switch) y correrlo en WSLg.
- Crear savestates deterministas: Bosque Kokiri, Campo de Hyrule y Árbol Deku.
- **Entregable:** el juego corriendo en el PC como referencia, más los savestates de prueba.

### Fase 2 — PUERTA DE CPU en la R36S (la más crítica)
- Compilar solo la lógica (whole-AOT + servicios + audio) para aarch64 con renderer nulo,
  usando `-O3 -mcpu=cortex-a35 -flto`.
- Correr `--throughput-benchmark` con el savestate en la consola y medir ms por actualización.
- **Criterio:** ≤ 25 ms por actualización (deja unos 8 ms para el render, que va en otro hilo).
- Si no se cumple → **Fase 2b**: optimizar el generador AOT, iterando y midiendo cada cambio:
  1. Fastmem: reservar el espacio de direcciones del 3DS y acceder directo con base + offset,
     sin comprobaciones de límites (en aarch64 sobra espacio virtual).
  2. Eliminar presupuestos de bloques y filtros de hooks en el modo producto.
  3. Calcular flags de la CPU solo cuando algo los lee (análisis de vida de flags en el generador).
  4. PGO con perfil del savestate, LTO, `-fno-plt`, y orden de funciones para la caché L1-I de 32 KB.
  5. Mover audio (DSP) y el frontend PICA a hilos aparte (hay 4 núcleos).
- Si tras la 2b sigue por encima de 33 ms, **paro y te consulto** con números reales.
  Opciones: 20–25 fps estables, salto de frames, o renunciar.

### Fase 3 — Renderer GLES 3.2 para libmali
- Probe de capacidades del dispositivo: SSBO por etapa, límites de uniforms, ETC1/ETC2, *program binary*.
- Port del dialecto de shaders: GLSL 4.50/4.30 → **GLSL ES 3.20**, con precisión explícita y SSBO
  o UBO según lo que reporte el probe.
- Contexto SDL2 KMSDRM GLES 3.2 (quitar el perfil Core 4.x de `gfx_sdl2.cpp`).
- Resolución interna configurable: **400×240 nativa** por defecto, escalada a 640×480.
- Caché persistente de shaders compilados (`glProgramBinary`) para evitar tirones.
- Reducir llamadas al driver: buffers persistentes, uniforms agrupados, menos cambios de estado.

### Fase 4 — Una pantalla, modo cartoon, controles y menú
- Perfil `topscreen` + atlas SingleScreen 3.0 (ya incluido en el repo) y gameplay a 30 Hz sin interpolación.
- **Toon Lite**: luz cuantizada en el shader de fragmentos más contorno por bordes de profundidad
  a resolución interna. Se puede activar o desactivar.
- Controles R36S basados en el perfil de Switch: D-pad arriba = vista, D-pad abajo = ocarina,
  izquierda/derecha = objetos rápidos, L2/R2 = objetos, R1 = fijar objetivo, Select+Start = salir.
- Menú de configuración (ImGui de TriAevum, con backend GLES3) con el combo **Select + R3**:
  resolución interna, toon, contorno, contador de FPS, salto de frames, sombras, filtrado, cámara
  invertida, botones de objetos, autoguardado, guardado y carga rápidos, brillo y gamma.

### Fase 5 — Empaquetado dArkOS / PortMaster
- `dist/ports/oot3d/`: binario, `resources.o2r`, caché de shaders, `config/`, `gamedata/`
  (datos extraídos de tu ROM, solo para ti), librerías extra si hacen falta.
- `dist/ports/OOT3D.sh`: detecta `control.txt` de PortMaster si existe, pone el governor en
  *performance*, exporta las variables SDL KMSDRM, ejecuta y escribe `log.txt`.
- Primer arranque: si falta `gamedata/`, el script lo explica en pantalla.

### Fase 6 — Pruebas en la consola y ajuste fino
- Ciclo de prueba: tú corres el port y me pasas `log.txt` y las métricas.
- Prueba de 30 minutos en las tres zonas, y medición de memoria (RSS) y temperatura.

### Fase 7 — Limpieza final (pedida por ti)
- Cuando el port esté entregado y probado: desinstalar la distro WSL Debian (`wsl --unregister Debian`),
  borrar `repos/`, `deps/`, `work/`, `scripts/`, los documentos de trabajo y la ROM extraída.
- En el PC queda **solo** `dist/ports/oot3d/` (el juego) y `dist/ports/OOT3D.sh`.

## Lo que necesito de ti

1. **Cómo probar en la consola.** Lo ideal es SSH: dArkOS lo trae, pero la R36S no tiene WiFi y
   necesita un adaptador USB WiFi u OTG. Si no, lo hacemos copiando archivos con la SD y
   devolviéndome `log.txt`.
2. Confirmar el modelo exacto de tu R36S y la versión de dArkOS RE (panel V12/V20/V21… y la fecha
   de la versión), porque cambia el *device tree* y el mapeo de controles.

## Riesgos (con honestidad)

| Riesgo | Probabilidad | Mitigación |
|---|---|---|
| La CPU no llega a 30 fps aunque se optimice el generador | **Alta** | Puerta de la Fase 2 antes de invertir en gráficos; plan B de 20–25 fps o salto de frames |
| Quirks del driver libmali con shaders traducidos | Media | Probe de capacidades al inicio y fallbacks de UBO o texturas |
| 1 GB de RAM: binario de ~120 MB + RomFS de 473 MB leída por streaming + texturas | Media | Streaming de RomFS (ya existe), texturas de 16 bits, zram |
| Proyecto origen en beta y con cambios rápidos | Media | Fijar el commit `8f69a26` y registrar cada parche |
| Tiempo: es un proyecto de muchas sesiones, no de una | Seguro | Bitácora en `docs/BITACORA.md` para retomar sin perder contexto |
