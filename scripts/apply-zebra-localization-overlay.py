#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path


def run_plutil(args):
    return subprocess.run(
        ["/usr/bin/plutil", *args],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def read_strings(path):
    result = run_plutil(["-convert", "json", "-o", "-", str(path)])
    return json.loads(result.stdout)


def write_strings(path, values):
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".json", delete=False) as tmp:
        json.dump(values, tmp, ensure_ascii=False, indent=2, sort_keys=True)
        tmp_path = Path(tmp.name)
    try:
        run_plutil(["-convert", "binary1", "-o", str(path), str(tmp_path)])
    finally:
        tmp_path.unlink(missing_ok=True)


def apply_table_overlay(resources_dir, table_name, table_overlay, brand_source, brand_name):
    changed = 0
    skipped = 0
    table_filename = f"{table_name}.strings"
    replace_keys = set(table_overlay.get("replaceBrandInKeys", []))
    fixed_values = table_overlay.get("fixedValues", {})

    for lproj_dir in sorted(resources_dir.glob("*.lproj")):
        strings_path = lproj_dir / table_filename
        if not strings_path.exists():
            skipped += 1
            continue

        values = read_strings(strings_path)
        before = dict(values)

        for key in replace_keys:
            value = values.get(key)
            if isinstance(value, str):
                values[key] = value.replace(brand_source, brand_name)

        for key, value in fixed_values.items():
            if key in values:
                values[key] = value

        for key in replace_keys | set(fixed_values):
            value = values.get(key)
            if isinstance(value, str) and brand_source in value:
                raise RuntimeError(
                    f"{strings_path}: overlay key {key!r} still contains {brand_source!r}: {value!r}"
                )

        if values != before:
            write_strings(strings_path, values)
            changed += 1

    return changed, skipped


def apply_info_plist_overlay(app_path, resources_dir, overlay):
    changed = 0
    info_overlay = overlay.get("infoPlist", {})
    fixed_values = info_overlay.get("fixedValues", {})
    info_path = app_path / "Contents" / "Info.plist"
    if fixed_values:
        values = read_strings(info_path)
        before = dict(values)
        values.update(fixed_values)
        if values != before:
            write_strings(info_path, values)
            changed += 1

    localized_values = info_overlay.get("localizedValues", {})
    for language, values in localized_values.items():
        lproj_dir = resources_dir / f"{language}.lproj"
        if not lproj_dir.is_dir():
            continue
        strings_path = lproj_dir / "InfoPlist.strings"
        existing = read_strings(strings_path) if strings_path.exists() else {}
        before = dict(existing)
        existing.update(values)
        if existing != before:
            write_strings(strings_path, existing)
            changed += 1
    return changed


def main():
    parser = argparse.ArgumentParser(
        description="Apply Zebra release-only localization overrides to a built app bundle."
    )
    parser.add_argument("app_path", help="Path to the built Zebra.app bundle")
    parser.add_argument(
        "--overlay",
        default="scripts/zebra-localization-overlay.json",
        help="Path to the Zebra localization overlay JSON",
    )
    args = parser.parse_args()

    app_path = Path(args.app_path)
    resources_dir = app_path / "Contents" / "Resources"
    overlay_path = Path(args.overlay)

    if not app_path.is_dir():
        print(f"error: app bundle not found: {app_path}", file=sys.stderr)
        return 1
    if not resources_dir.is_dir():
        print(f"error: resources directory not found: {resources_dir}", file=sys.stderr)
        return 1
    if not overlay_path.is_file():
        print(f"error: overlay not found: {overlay_path}", file=sys.stderr)
        return 1

    overlay = json.loads(overlay_path.read_text(encoding="utf-8"))
    brand_source = overlay.get("brandSource")
    brand_name = overlay.get("brandName")
    if not brand_source or not brand_name:
        print("error: overlay must define brandSource and brandName", file=sys.stderr)
        return 1

    localization_changed = 0
    total_skipped = 0
    for table_name, table_overlay in overlay.get("tables", {}).items():
        changed, skipped = apply_table_overlay(
            resources_dir,
            table_name,
            table_overlay,
            brand_source,
            brand_name,
        )
        localization_changed += changed
        total_skipped += skipped
        print(f"overlay {table_name}: changed {changed} locale(s), skipped {skipped}")

    if localization_changed == 0:
        print("error: no localization tables were changed", file=sys.stderr)
        return 1

    info_changed = apply_info_plist_overlay(app_path, resources_dir, overlay)
    print(f"overlay InfoPlist: changed {info_changed} artifact(s)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
