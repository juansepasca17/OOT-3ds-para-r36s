#!/usr/bin/env python3
"""romfs_ls.py <rom.3ds> [prefijo] [--extract RUTA DESTINO]

Lista (o extrae) archivos del RomFS de la partición 0 de una .3ds desencriptada.
Solo lee: sirve para ver qué carpetas de idioma trae el juego y qué tocó un mod.
"""
import struct
import sys


def open_romfs(path):
    f = open(path, "rb")
    f.seek(0x120)
    part_off, _ = struct.unpack("<II", f.read(8))
    ncch = part_off * 0x200
    f.seek(ncch)
    header = f.read(0x200)
    romfs_off = struct.unpack_from("<I", header, 0x1B0)[0] * 0x200
    ivfc = ncch + romfs_off
    f.seek(ivfc)
    ivfc_header = f.read(0x60)
    master_size = struct.unpack_from("<I", ivfc_header, 0x08)[0]
    level3_block = 1 << struct.unpack_from("<I", ivfc_header, 0x4C)[0]
    level3 = ivfc + ((0x60 + master_size + level3_block - 1) // level3_block) * level3_block
    f.seek(level3)
    h = struct.unpack("<10I", f.read(0x28))
    dir_meta_off, dir_meta_size = h[3], h[4]
    file_meta_off, file_meta_size = h[7], h[8]
    data_off = h[9]
    f.seek(level3 + dir_meta_off)
    dirs = f.read(dir_meta_size)
    f.seek(level3 + file_meta_off)
    files = f.read(file_meta_size)
    return f, level3 + data_off, dirs, files


def level3_header(path):
    """(offset del nivel 3 en el archivo, offset de la tabla de archivos, offset de los datos)."""
    f, data_base, _, _ = open_romfs(path)
    f.seek(0x120)
    part_off, _ = struct.unpack("<II", f.read(8))
    ncch = part_off * 0x200
    f.seek(ncch)
    ivfc = ncch + struct.unpack_from("<I", f.read(0x200), 0x1B0)[0] * 0x200
    f.seek(ivfc)
    ivh = f.read(0x60)
    master = struct.unpack_from("<I", ivh, 0x08)[0]
    block = 1 << struct.unpack_from("<I", ivh, 0x4C)[0]
    level3 = ivfc + ((0x60 + master + block - 1) // block) * block
    f.seek(level3)
    h = struct.unpack("<10I", f.read(0x28))
    assert level3 + h[9] == data_base
    return level3, h[7], h[9]


def walk(dirs, files, off=0, path=""):
    parent, sibling, child, first_file, _, name_len = struct.unpack_from("<6I", dirs, off)
    name = dirs[off + 0x18: off + 0x18 + name_len].decode("utf-16le")
    here = f"{path}/{name}" if off else ""
    fo = first_file
    while fo != 0xFFFFFFFF:
        _, nxt, data, size, _, flen = struct.unpack_from("<IIQQII", files, fo)
        fname = files[fo + 0x20: fo + 0x20 + flen].decode("utf-16le")
        yield f"{here}/{fname}", data, size
        fo = nxt
    co = child
    while co != 0xFFFFFFFF:
        yield from walk(dirs, files, co, here)
        co = struct.unpack_from("<I", dirs, co + 4)[0]


def main():
    f, data_base, dirs, files = open_romfs(sys.argv[1])
    if "--extract" in sys.argv:
        i = sys.argv.index("--extract")
        want, dest = sys.argv[i + 1], sys.argv[i + 2]
        for p, data, size in walk(dirs, files):
            if p == want:
                f.seek(data_base + data)
                open(dest, "wb").write(f.read(size))
                print(f"{p} -> {dest} ({size} bytes)")
                return
        sys.exit(f"no existe {want}")
    prefix = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else ""
    for p, _, size in walk(dirs, files):
        if p.startswith(prefix):
            print(f"{size:>10} {p}")


if __name__ == "__main__":
    main()
