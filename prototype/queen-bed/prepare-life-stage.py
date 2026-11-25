"""Stage the shared native and Lua eligibility policy before packaging HZoi Gameplay."""

import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("mod", type=Path, help="Staged HZoi Gameplay mod root")
args = parser.parse_args()

policy_file = args.mod / "lua/B2/LifeStageEligibility.lua"
policy = policy_file.read_text(encoding="utf-8")
stages = re.search(r"^local stages = \{\n([^}]+)\n\}", policy, re.M)
if not stages:
    raise ValueError(f"Could not read stages from {policy_file}")
mask = 0
for line in stages[1].splitlines():
    entry = re.fullmatch(r"\s*[A-Za-z_]\w*\s*=\s*(\d+)\s*,\s*", line)
    if not entry:
        raise ValueError(f"Invalid life-stage entry: {line}")
    bit = int(entry[1])
    if not 0 < bit <= 0x40000000 or bit & (bit - 1) or mask & bit:
        raise ValueError(f"Life-stage values must be distinct positive one-bit flags: {line}")
    mask |= bit

native_file = args.mod / "Content/JsonPatch/InteractionBag_patch.json"
native_source = native_file.read_text(encoding="utf-8")
native_rows = json.loads(native_source)
generated_bags = {
    "HZoiGameplay_Invite", "HZoiGameplay_GroundInvite", "HZoiGameplay_Walk", "HZoiGameplay_WalkRetry",
    "HZoiGameplay_MarkPrivateRoom",
}
changed = set()
for patch in native_rows["PatchList"]:
    row = patch["Value"]
    name = row.get("Id", row.get("ID"))
    if name in generated_bags:
        row["AgingConditionFlags"] = mask
        changed.add(name)

if changed != generated_bags:
    raise ValueError(f"Missing native HZoi bags: {generated_bags - changed}")
native_file.write_text(json.dumps(native_rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
(args.mod / "lua/B1/LifeStageEligibility.lua").write_bytes(policy_file.read_bytes())
