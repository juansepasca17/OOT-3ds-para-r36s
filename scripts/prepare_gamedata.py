#!/usr/bin/env python3
"""Extract, adapt and verify the user's decrypted OoT3D ROM with TriAevum's own Forge code.

Usage (inside WSL):
    python3 -I scripts/prepare_gamedata.py --repo repos/TriAevum --rom rom/<file>.cci --out work/gamedata

Produces <out>/sources/{code,exheader,romfs}.bin (canonical execution inputs) plus
<out>/titles/<recipe>/ (Forge's prepared content index). Nothing is downloaded or decrypted.
"""
import argparse
import copy
import json
import shutil
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--rom", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    release = (args.repo / "tools" / "triaevum_release").resolve()
    sys.path.insert(0, str(release))
    import ctr_rom
    import forge
    from common import load_json_object
    from data_compatibility import expected
    from input_adapters import adapt_extracted_inputs, import_contract

    out = args.out.resolve()
    staging = out / ".staging"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)

    print("[1/5] extract", flush=True)
    extracted = ctr_rom.extract_decrypted_rom(args.rom.resolve(), staging / "raw")
    for kind, item in extracted.by_kind().items():
        print(f"      {kind}: {item.bytes} bytes sha256={item.sha256}")
    print(f"      program id {extracted.program_id:016X}")

    # Same recipe set the release package ships: repository recipes plus the
    # qualified-input bindings (USA and catalogue revisions) from input_coverage.
    recipes = load_json_object(forge.DEFAULT_RECIPES)
    coverage_root = release / "input_coverage"
    coverage = load_json_object(coverage_root / "coverage.json")
    for binding in coverage["bindings"]:
        base = next(r for r in recipes["recipes"] if r["id"] == binding["base_recipe"])
        recipe = copy.deepcopy(base)
        recipe.pop("precompiled_base_recipe", None)
        recipe.update(copy.deepcopy(binding["input"]))
        recipes["recipes"] = [r for r in recipes["recipes"] if r["id"] != recipe["id"]] + [recipe]

    print("[2/5] match revision", flush=True)
    actual = extracted.by_kind()
    matches = []
    for recipe in recipes["recipes"]:
        contracts = import_contract(recipe)
        if all(contracts.get(k, {}).get("bytes") == v.bytes
               and str(contracts.get(k, {}).get("sha256", "")).lower() == v.sha256
               for k, v in actual.items()):
            matches.append(recipe)
    if not matches:
        source = {"bytes": extracted.code.bytes, "sha256": extracted.code.sha256}
        matches = [r for r in recipes["recipes"]
                   if expected(r, "source") is not None and expected(r, "source")["code"] == source]
    if len(matches) != 1:
        print(f"      no unique recipe ({len(matches)} matches)", file=sys.stderr)
        return 1
    recipe = matches[0]
    print(f"      recipe {recipe['id']} ({recipe.get('region')})")

    print("[3/5] adapt to canonical execution inputs", flush=True)
    extracted, adaptation = adapt_extracted_inputs(
        extracted, recipe, root=coverage_root, output=staging / "normalized")
    if adaptation:
        print(f"      adapted in {adaptation['wall_seconds']:.1f}s")

    print("[4/5] publish + verify", flush=True)
    extracted = ctr_rom.publish_extracted_inputs(extracted, out / "sources")
    cache = forge.HashCache(out / ".hash-cache.json")
    for item in extracted.by_kind().values():
        cache.remember(item.path, item.sha256)
    verified, verified_mod = forge.verify_sources(
        recipe, code_path=extracted.code.path, exheader_path=extracted.exheader.path,
        romfs_path=extracted.romfs.path, cache=cache)

    print("[5/5] prepare content index", flush=True)
    prepared = forge.prepare_content(recipe, verified, output_root=out / "titles",
                                     verified_mod=verified_mod)
    (out / "recipe.json").write_text(json.dumps(recipe, indent=2))
    (out / "prepared.json").write_text(json.dumps(prepared, indent=2, default=str))
    shutil.rmtree(staging, ignore_errors=True)
    print(f"OK prepared directory: {prepared['directory']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
