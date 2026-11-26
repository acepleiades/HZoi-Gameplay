"""Validate HZoi Gameplay translations and generate its Lua and native PO files."""
import argparse
import csv
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent
MOD = ROOT / "HZoiGameplayPrototype_4BD2AC16"
CULTURES = (
    "en-US", "ko-KR", "ja-JP", "zh-CN", "zh-TW", "de-DE", "es-ES", "fr-FR",
    "it-IT", "nl-NL", "pl-PL", "pt-BR", "pt-PT", "ru-RU", "tr-TR",
)
STOP_MESSAGES = {
    "witness_sighting": {
        "named": "{first} and {second} decided to stop after someone walked in on them.",
        "unnamed": "The encounter ended after someone walked in.",
    },
    "caught_by_partner": {
        "named": "{first} and {second} decided to stop after one of their romantic partners caught them together.",
        "unnamed": "The encounter ended after a romantic partner walked in on it.",
    },
}
PREFIX = "mod_Buff_BuffDisplayInfo_HZoiGameplay_"
BUFF_NAMESPACE = "ST_Buff_4bd2ac16"
SPEECH_NAMESPACE = "ST_SpeechBubble_4bd2ac16"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_csv(name):
    with (ROOT / name).open(encoding="utf-8-sig", newline="") as source:
        rows = list(csv.DictReader(source))
    strings = {row["Key"]: row["SourceString"] for row in rows}
    require(len(rows) == len(strings), f"Duplicate native string ID in {name}")
    return strings


def unique_keys(entries):
    result = dict(entries)
    require(len(result) == len(entries), "Duplicate localization key")
    return result


def load_catalogs():
    folder = ROOT / "localization"
    require({p.stem for p in folder.glob("*.json")} == set(CULTURES), "Expected all 15 inZOI locales")
    return {
        culture: json.loads((folder / f"{culture}.json").read_text(encoding="utf-8"), object_pairs_hook=unique_keys)
        for culture in CULTURES
    }


def single_line(value):
    return isinstance(value, str) and value.strip() and not re.search(r"[\x00-\x1f\x7f\u2028\u2029\ufffd]", value)


def placeholders(value):
    return sorted(re.findall(r"\{(\w+)\}", value))


def validate(catalogs, buffs, dialog):
    english = catalogs["en-US"]
    require(set(english) == {"moodlets", "causes", "messages"}, "Unexpected fields in the English catalog")
    identifiers = {
        key.removeprefix(PREFIX).removesuffix("_DisplayTextId")
        for key in buffs if key.startswith(PREFIX) and key.endswith("_DisplayTextId")
    }
    require(set(english["moodlets"]) == identifiers, "English moodlet IDs must match the StringTable")
    cause_mapping = {}
    for identifier, (title, body) in english["moodlets"].items():
        prefix = PREFIX + identifier
        reason = buffs[prefix + "_ReasonTextId"]
        cause, separator, description = reason.partition("\n")
        cause_mapping[identifier] = (cause.rstrip("\r"), "\r\n" if cause.endswith("\r") else separator)
        require(
            buffs[prefix + "_DisplayTextId"] == title
            and buffs[prefix + "_EmotionReasonDescTextId"] == body and description == body,
            f"English moodlet {identifier} differs from the native source",
        )
    require(set(english["causes"]) == {cause for cause, _ in cause_mapping.values()}, "English cause list differs from native source")
    require(set(dialog.values()) <= set(english["messages"]), "English speech must be declared")
    require(all(k == v for k, v in english["messages"].items()), "English message keys must match their values")
    require(all(k == v for k, v in english["causes"].items()), "English cause keys must match their values")

    for culture, catalog in catalogs.items():
        require(set(catalog) == set(english), f"Unexpected section in {culture}")
        for section in english:
            require(set(catalog[section]) == set(english[section]), f"Missing or extra {section} keys in {culture}")
        for key, value in catalog["messages"].items():
            require(single_line(value) and placeholders(value) == placeholders(key), f"{culture} invalid message: {key}")
        for key, value in catalog["causes"].items():
            require(single_line(value) and value.startswith("[") and value.endswith("]"), f"{culture} invalid cause: {key}")
        for identifier, pair in catalog["moodlets"].items():
            require(isinstance(pair, list) and len(pair) == 2 and all(single_line(v) for v in pair),
                    f"{culture} invalid moodlet: {identifier}")
        for pair in STOP_MESSAGES.values():
            for template in pair.values():
                value = catalog["messages"][template]
                require(len(value.encode()) <= 512, f"{culture} stop reason too long")
    return cause_mapping


def quote(value):
    return json.dumps(value, ensure_ascii=False)


def lua(value, depth=0):
    if isinstance(value, str):
        return quote(value)
    indent = "    " * depth
    fields = [f"{indent}    [{quote(key)}] = {lua(item, depth + 1)},\n" for key, item in value.items()]
    return "{\n" + "".join(fields) + indent + "}"


def native_po(culture, buffs, dialog, catalog, causes):
    localized = {}
    for identifier, (title, description) in catalog["moodlets"].items():
        prefix = PREFIX + identifier
        cause, suffix = causes[identifier]
        localized[prefix + "_DisplayTextId"] = title
        localized[prefix + "_ReasonTextId"] = catalog["causes"][cause] + suffix + description
        localized[prefix + "_EmotionReasonDescTextId"] = description
    # The language menu expects a separate quoted line for each gettext header field.
    header = (
        "Project-Id-Version: Blue_Data",
        f"Language: {culture}",
        "MIME-Version: 1.0",
        "Content-Type: text/plain; charset=UTF-8",
        "Content-Transfer-Encoding: 8bit",
    )
    rows = ['msgid ""\nmsgstr ""\n' + "\n".join(quote(line + "\n") for line in header) + "\n"]
    for namespace, english, translations in (
        (BUFF_NAMESPACE, buffs, localized),
        (SPEECH_NAMESPACE, dialog, {key: catalog["messages"][source] for key, source in dialog.items()}),
    ):
        require(set(english) == set(translations), f"{culture} native key mismatch for {namespace}")
        for key, source in english.items():
            rows.append(f"msgctxt {quote(namespace + ',' + key)}\nmsgid {quote(source)}\nmsgstr {quote(translations[key])}\n")
    return "\n".join(rows).replace("\n", "\r\n")


def generate():
    catalogs = load_catalogs()
    buffs = read_csv("moodlet-text.csv")
    dialog = read_csv("speech-text.csv")
    causes = validate(catalogs, buffs, dialog)
    stop_keys = {key for pair in STOP_MESSAGES.values() for key in pair.values()}
    runtime = {}
    stop_reasons = {}
    for culture, catalog in catalogs.items():
        messages = catalog["messages"]
        folded = culture.lower()
        runtime[folded] = {
            key: value for key, value in messages.items()
            if key not in stop_keys and key not in dialog.values()
        }
        stop_reasons[folded] = {
            reason: {variant: messages[source] for variant, source in variants.items()}
            for reason, variants in STOP_MESSAGES.items()
        }

    outputs = {
        "lua/B1/Translations.lua": "-- Generated by prepare-localization.py.\nreturn " + lua(runtime) + "\n",
        "lua/B2/StopReasons.lua": "-- Generated by prepare-localization.py.\nreturn " + lua(stop_reasons) + "\n",
    }
    for culture in CULTURES:
        if culture == "en-US":
            continue  # English is the source on the two native StringTable assets.
        outputs[f"l10n/{culture}_mod/Blue_Data.po"] = native_po(
            culture, buffs, dialog, catalogs[culture], causes
        )
    return outputs


def check_native_registration(target):
    # Valid gettext can put the entire header in msgstr. inZOI's language menu
    # only discovers Language in its own continuation line.
    with target.open(encoding="utf-8") as source:
        lines = [next(source, "").rstrip("\n") for _ in range(8)]
    locale = target.parent.name.removesuffix("_mod")
    require(
        lines[:2] == ['msgid ""', 'msgstr ""'] and quote(f"Language: {locale}\n") in lines[2:7],
        f"Missing an inZOI language registration header: {target}",
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mod", nargs="?", type=Path, default=MOD)
    parser.add_argument("--check", action="store_true", help="Validate that generated files match the translation sources")
    args = parser.parse_args()
    outputs = generate()
    for relative, content in outputs.items():
        target = args.mod / relative
        if args.check:
            require(target.is_file() and target.read_bytes() == content.encode(), f"Regenerate {relative}")
            if target.suffix == ".po":
                check_native_registration(target)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8", newline="\n")
    print(f"Verified {len(CULTURES)} locale catalogs and {len(outputs)} generated files.")


if __name__ == "__main__":
    main()
