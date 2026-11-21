#!/usr/bin/env python3
"""romfs_patch.py <rom.3ds> <salida romfs.patch> RUTA_ROMFS=ARCHIVO [...]

Parche de RomFS para Pocket Native con soporte de romfs.patch (ver docs/POCKET_NATIVE.md):
reemplaza archivos del RomFS sin reconstruir la ROM. Las tablas no cambian de tamaño; solo se
reescriben la posición y el tamaño de cada archivo reemplazado, y sus datos nuevos van después
del final de los datos originales. El parche va en games/<title id>/data/romfs.patch.

Formato: "PNRP", u32 cantidad, y por pieza u64 offset (desde el nivel 3), u32 largo, bytes.
Ejemplo:
  romfs_patch.py game.3ds romfs.patch /menu/07_US_SPANISH/hud_all00.ctxb=hud_en.ctxb
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from romfs_ls import level3_header, open_romfs  # noqa: E402


def file_entries(dirs, files, off=0, path=""):
    """(ruta, offset de la entrada en la tabla de archivos, offset de datos, tamaño)."""
    _, _, child, first_file, _, name_len = struct.unpack_from("<6I", dirs, off)
    name = dirs[off + 0x18: off + 0x18 + name_len].decode("utf-16le")
    here = f"{path}/{name}" if off else ""
    fo = first_file
    while fo != 0xFFFFFFFF:
        _, nxt, data, size, _, flen = struct.unpack_from("<IIQQII", files, fo)
        yield f"{here}/{files[fo + 0x20: fo + 0x20 + flen].decode('utf-16le')}", fo, data, size
        fo = nxt
    co = child
    while co != 0xFFFFFFFF:
        yield from file_entries(dirs, files, co, here)
        co = struct.unpack_from("<I", dirs, co + 4)[0]


def main():
    rom, out, pairs = sys.argv[1], sys.argv[2], sys.argv[3:]
    _, _, dirs, files = open_romfs(rom)
    _, file_meta_off, data_off = level3_header(rom)
    entries = {p: (fo, d, s) for p, fo, d, s in file_entries(dirs, files)}
    end = max(d + s for _, d, s in entries.values())
    pieces = []
    for pair in pairs:
        path, local = pair.split("=", 1)
        if path not in entries:
            sys.exit(f"no existe en el RomFS: {path}")
        fo, _, old_size = entries[path]
        data = open(local, "rb").read()
        new_off = (end + 0xF) & ~0xF
        end = new_off + len(data)
        pieces.append((file_meta_off + fo + 8, struct.pack("<QQ", new_off, len(data))))
        pieces.append((data_off + new_off, data))
        print(f"{path}: {old_size} -> {len(data)} bytes")
    with open(out, "wb") as o:
        o.write(b"PNRP" + struct.pack("<I", len(pieces)))
        for at, data in pieces:
            o.write(struct.pack("<QI", at, len(data)) + data)
    print(f"{out}: {len(pieces)} piezas, {os.path.getsize(out)} bytes")


if __name__ == "__main__":
    main()
