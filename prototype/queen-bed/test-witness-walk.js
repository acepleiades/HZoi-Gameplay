const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const bagPath = path.join(__dirname, 'HZoiGameplayPrototype_4BD2AC16/Content/JsonPatch/InteractionBag_patch.json');
const bags = JSON.parse(fs.readFileSync(bagPath, 'utf8')).PatchList;
const witnessWalk = bags.find(({Value}) => Value.Id === 'HZoiGameplay_WitnessWalk');
assert(witnessWalk.Enabled && witnessWalk.Method === 'Append');
assert.deepEqual(witnessWalk.Value.InteractionSequence[0].InteractionInfos, [{InteractionId: 'ClickMove', Label: 'A'}]);
assert.equal(witnessWalk.Value.AgingConditionFlags, 508, 'Use the native ClickMove age mask for bystanders');
for (const age of [4, 8, 16, 32, 64, 128, 256]) {
    assert.equal(witnessWalk.Value.AgingConditionFlags & age, age);
}
assert.notEqual(witnessWalk.Value.Id, 'HZoiGameplay_Walk');
const policyGenerator = fs.readFileSync(path.join(__dirname, 'prepare-life-stage.py'), 'utf8');
assert(!policyGenerator.includes('HZoiGameplay_WitnessWalk'), 'Do not replace the native movement mask during packaging');
console.log('Native witness movement keeps the ClickMove life stages.');
