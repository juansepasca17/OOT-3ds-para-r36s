# OoT3D para R36S (dArkOS RE)

Port experimental de **The Legend of Zelda: Ocarina of Time 3D** a la consola **R36S**
(RK3326, Mali-G31, 1 GB de RAM) con **dArkOS RE**, basado en
[TriAevum](https://github.com/coccofresco/TriAevum), la recompilación nativa AOT de coccofresco.

> **Estado: en desarrollo, todavía no se puede jugar.** Ver [PLAN.md](PLAN.md) y [docs/BITACORA.md](docs/BITACORA.md).

## Qué contiene este repo

- `PLAN.md`: fases, puertas de rendimiento y riesgos.
- `PROMPT_MEJORADO.md`: especificación completa del objetivo.
- `scripts/fetch_sources.sh`: descarga TriAevum (commit fijo), dArkOS y libmali.
- `scripts/prepare_gamedata.py`: extrae y verifica **tu** ROM con el código de Forge de TriAevum.
- `scripts/wsl/`: pasos de compilación en WSL2 Debian trixie.
- `dist/ports/OOT3D.sh`: lanzador para el menú *Ports* de dArkOS / PortMaster.

## Qué NO contiene (y nunca contendrá)

- Ninguna ROM ni datos del juego. Necesitas un volcado **desencriptado** de **tu propio**
  cartucho de *Ocarina of Time 3D* (USA o Europa, versión original o Rev 1).
- Ningún código ni recurso de Nintendo.
- Binarios de terceros con licencia cerrada (libmali se descarga desde su repositorio original).

## Uso (cuando esté listo)

1. En WSL2 Debian 13: `bash scripts/fetch_sources.sh`.
2. `python3 -I scripts/prepare_gamedata.py --repo repos/TriAevum --rom <tu_rom>.cci --out work/gamedata`.
3. Compilar con los scripts de `scripts/wsl/` (pendiente).
4. Copiar `dist/ports/OOT3D.sh` y `dist/ports/oot3d/` a `/roms/ports/` en la SD de la R36S.

## Licencia

GPL-3.0-or-later, igual que TriAevum. *The Legend of Zelda* es una marca de Nintendo.
Este es un proyecto de fans, sin afiliación con Nintendo.
