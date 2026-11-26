"""Stage or archive an isolated native ModKit package of HZoi Gameplay."""

import argparse
from hashlib import md5, sha256
import json
from pathlib import Path
import shutil
import subprocess
import sys
from zipfile import ZIP_DEFLATED, ZipFile


SOURCE = Path(__file__).resolve().parent
GAMEPLAY_LICENSE = SOURCE.parents[1] / "LICENSE"
MOD = "HZoiGameplayPrototype_4BD2AC16"
DESCRIPTOR = f"{MOD}.uplugin"
DEPENDENCIES = ["SceneZOI_93C44199", "HZoi_660649D8"]
ASSETS = {"String/mod_ST_Buff_4bd2ac16", "String/mod_ST_SpeechBubble_4bd2ac16"}
VENUE_UI = {
    "ui/uimod_apps.json",
    "ui/venue-invitation/uimod_manifest.json",
    "ui/venue-invitation/index.html",
    "ui/venue-invitation/app.js",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def files(root):
    return {path.relative_to(root).as_posix(): path for path in root.rglob("*") if path.is_file()}


def stage(args):
    source = SOURCE / MOD
    sdk = args.scenezoi / "sdk/lua/SceneZOIAddon"
    mod = args.project.parent / "Mods" / MOD
    require(args.project.is_file() and args.project.suffix == ".uproject", "Supply an isolated ModKit .uproject.")
    require(not mod.exists(), f"Use a fresh project staging directory. {mod} already exists.")
    require((args.scenezoi / "LICENSE").is_file() and (sdk / "Json.lua").is_file(), "Select the matching SceneZOI checkout.")
    shutil.copytree(source, mod)
    shutil.copytree(sdk, mod / "lua/B2/SceneZOIAddon")
    b1_sdk = mod / "lua/B1/SceneZOIAddon"
    b1_sdk.mkdir()
    shutil.copyfile(sdk / "Json.lua", b1_sdk / "Json.lua")
    for tool in ("prepare-life-stage.py", "prepare-localization.py"):
        subprocess.run([sys.executable, str(SOURCE / tool), str(mod)], check=True)
    print(f"Staged {mod}")


def non_assets(prepared):
    expected = {}
    for area in ("lua", "l10n", "ui", "Content/JsonPatch"):
        target = "non_ufs/JsonPatch" if area == "Content/JsonPatch" else area
        expected.update({f"{target}/{key}": path for key, path in files(prepared / area).items()})
    return expected


def verify_export(prepared, exported):
    actual = files(exported)
    manifest = load(exported / "mod_manifest.json")
    require(manifest["ProjectName"] == MOD, "Wrong mod identity in the native export.")
    require(load(exported / DESCRIPTOR) == load(prepared / DESCRIPTOR), "Exported plugin descriptor differs from the prepared candidate.")
    require(set(manifest["Protected"]) == {"/lua"}, "Native Lua protection is missing or changed.")
    require(set(manifest["Assets"]) == ASSETS and not manifest["Maps"], "Unexpected cooked asset inventory.")
    asset_classes = load(exported / "mod_assethash.json")["assetClasses"]
    require(asset_classes == dict.fromkeys(ASSETS, "/Script/Engine.StringTable"), "Native asset classes differ from the two StringTables.")
    expected = non_assets(prepared)
    require(VENUE_UI <= expected.keys(), "The prepared payload is missing the venue invitation UI app.")
    require({key.lstrip("/") for key in manifest["NonAssets"]} == set(expected), "Native manifest differs from the prepared payload.")
    require(len([key for key in expected if key.startswith("l10n/")]) == 14, "Expected one native PO for each of the 14 non-English locales.")
    cooked = {key for key in actual if key.startswith("Content/Paks/")}
    require(len(cooked) == 3 and {actual[key].suffix for key in cooked} == {".pak", ".ucas", ".utoc"}, "Expected the three cooked ModKit containers.")
    require(set(actual) == set(expected) | cooked | {"mod_manifest.json", "mod_assethash.json", DESCRIPTOR}, "Unexpected or missing exported file.")
    checksums = dict(item.rsplit("|", 1) for item in manifest["FileChecksums"])
    # ModKit emits the app manifests separately from its checksummed payload.
    ui_manifests = {key for key in expected if key.startswith("ui/") and key.endswith("/uimod_manifest.json")}
    expected_checksums = (set(expected) | cooked) - ui_manifests
    require(
        len(checksums) == len(manifest["FileChecksums"]) and set(checksums) == expected_checksums,
        "Native checksum inventory differs from the prepared payload.",
    )
    for key, checksum in checksums.items():
        path = actual[key]
        native_checksum = md5(f"{path.name}|{path.stat().st_size}".encode()).hexdigest()
        require(native_checksum == checksum, f"Native checksum mismatch for {key}.")
    for key, source in expected.items():
        blob = actual[key].read_bytes()
        if key.endswith(".lua"):
            require(blob != source.read_bytes(), f"Lua was exported without protection: {key}.")
        elif key in ui_manifests:
            require(
                load(actual[key]) == dict(load(source), encoded=True),
                f"Encoded UI app manifest differs from source: {key}.",
            )
        elif key.startswith("ui/") and source.suffix in {".html", ".js", ".css"}:
            source_size = int.from_bytes(blob[6:10], "little")
            require(
                blob.startswith(b"IZUI") and len(blob) >= 10 and source_size == source.stat().st_size,
                f"UI was not encoded from the prepared source: {key}.",
            )
        else:
            require(blob == source.read_bytes(), f"Unprotected file differs from source: {key}.")
    return actual, manifest


def archive(args):
    exported_files, manifest = verify_export(args.prepared, args.exported)
    sdk_license = args.scenezoi / "LICENSE"
    sdk = args.scenezoi / "sdk/lua/SceneZOIAddon"
    prepared_sdk = args.prepared / "lua/B2/SceneZOIAddon"
    require(GAMEPLAY_LICENSE.is_file(), "The HZoi Gameplay license is missing from the source checkout.")
    require(sdk_license.is_file() and sdk.is_dir(), "Select the same SceneZOI checkout used for staging.")
    sdk_files = files(sdk)
    require(set(files(prepared_sdk)) == set(sdk_files), "Prepared B2 SDK file inventory differs from the matching checkout.")
    for key, path in sdk_files.items():
        require(path.read_bytes() == (prepared_sdk / key).read_bytes(), f"Prepared SDK differs from the matching checkout: {key}.")
    b1_sdk = args.prepared / "lua/B1/SceneZOIAddon/Json.lua"
    require(b1_sdk.read_bytes() == (sdk / "Json.lua").read_bytes(), "Prepared B1 Json.lua differs from the matching SDK.")
    manifest["Dependencies"] = DEPENDENCIES
    manifest["bEnable"] = True
    with ZipFile(args.output, "x", compression=ZIP_DEFLATED) as package:
        for key, file in sorted(exported_files.items()):
            if key != "mod_manifest.json":
                package.write(file, f"{MOD}/{key}")
        package.writestr(f"{MOD}/mod_manifest.json", json.dumps(manifest, indent=2) + "\n")
        package.write(GAMEPLAY_LICENSE, f"{MOD}/LICENSE.txt")
        package.write(sdk_license, f"{MOD}/LICENSE-SceneZOI-SDK.txt")
    with ZipFile(args.output) as package:
        require(package.testzip() is None, "ZIP failed its integrity check.")
    print(f"{sha256(args.output.read_bytes()).hexdigest()}  {args.output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(required=True)
    staging = commands.add_parser("stage")
    staging.add_argument("--scenezoi", type=Path, required=True)
    staging.add_argument("--project", type=Path, required=True, help="Isolated ModKit .uproject")
    staging.set_defaults(action=stage)
    packaging = commands.add_parser("archive")
    packaging.add_argument("--scenezoi", type=Path, required=True)
    packaging.add_argument("--prepared", type=Path, required=True)
    packaging.add_argument("--exported", type=Path, required=True)
    packaging.add_argument("--output", type=Path, required=True)
    packaging.set_defaults(action=archive)
    args = parser.parse_args()
    args.action(args)


if __name__ == "__main__":
    main()
