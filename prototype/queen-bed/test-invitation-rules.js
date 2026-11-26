const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const patchFolder = path.join(__dirname, 'HZoiGameplayPrototype_4BD2AC16', 'Content', 'JsonPatch');
function rows(table) {
    const patch = fs.readFileSync(path.join(patchFolder, table + '_patch.json'), 'utf8');
    return new Map(JSON.parse(patch).PatchList.map(({Value}) => [Value.Id ?? Value.ID, Value]));
}

const enqueue = rows('Condition_Enqueue').get('HZoiGameplay_EligibleForMood');
const talkRules = rows('Condition_Interaction_Talk');
const invitation = rows('InteractionBag').get('HZoiGameplay_Invite');

function matches(row, state) {
    function matchesGroup({Conditions}) {
        return Conditions.every(({BaseObject, Command, CompareType, S1, F1}) => {
            let actual, expected;
            switch (Command) {
                case 'IsLovable': actual = state.lovable; expected = true; break;
                case 'IsFromRemoteCity': actual = state.remote === BaseObject; expected = true; break;
                case 'IsFamilyRelationship': actual = state.familyRelationship ?? 'None'; expected = S1; break;
                case 'RelationshipName': actual = state.relationship; expected = S1; break;
                case 'RelationshipStat': actual = state[S1]; expected = F1; break;
                case 'EmotionTendency': actual = state.emotion; expected = S1; break;
                default: assert.fail('Unhandled native condition: ' + Command);
            }
            // The native NotEqual rule with None means the pair has no family relationship.
            if (Command === 'IsFamilyRelationship' && CompareType === 'NotEqual' && S1 === 'None') {
                return state.familyRelationship === undefined;
            }
            switch (CompareType) {
                case 'Equal': return actual === expected;
                case 'NotEqual': return actual !== expected;
                case 'Less': return actual < expected;
                case 'GreaterOrEqual': return actual >= expected;
                case 'LessOrEqual': return actual <= expected;
                default: assert.fail('Unhandled native comparison: ' + CompareType);
            }
        });
    }
    return row.AndConditionsList.every(matchesGroup) &&
        (row.OrConditionsList.length === 0 || row.OrConditionsList.some(matchesGroup));
}

function check(overrides, expected) {
    const state = {romance: 0, emotion: 'Negative', lovable: true, ...overrides};
    assert.equal(matches(enqueue, state), expected.length > 0);
    const routes = invitation.InteractionSequence
        .filter(route => matches(talkRules.get(route.EnableConditionId), state));
    assert.deepEqual(routes.map(({CoopId, Probability}) => [CoopId, Probability]), expected);
    for (const route of routes) {
        assert.deepEqual(route.InteractionInfos.map(({InteractionId}) => InteractionId), ['RequestCoop']);
    }
}

const accept = 'HZoiGameplay_Coop_Accept';
const refuse = 'HZoiGameplay_Coop_Refuse';
check({}, [[refuse, 1]]);
check({romance: 29}, [[refuse, 1]]);
check({romance: 30}, [[accept, 0.3], [refuse, 0.7]]);
check({romance: 30, emotion: 'Positive'}, [[accept, 1]]);
check({relationship: 'Youth_Lover'}, [[accept, 0.7], [refuse, 0.3]]);
check({relationship: 'engagement'}, [[accept, 0.7], [refuse, 0.3]]);
check({familyRelationship: 'Spouse', family: 0}, [[accept, 0.7], [refuse, 0.3]]);
check({familyRelationship: 'Spouse', family: 30}, [[accept, 1]]);
check({relationship: 'HighTeen_Lover'}, []);
check({relationship: 'HighTeen_Lover', romance: 30}, [[accept, 1]]);
check({remote: 'Target'}, []);
check({remote: 'Self'}, []);
check({lovable: false}, []);
check({familyRelationship: 'Sibling'}, []);
const venue = 'HZoiGameplay_SelectVenue';
const options = JSON.parse(fs.readFileSync(path.join(patchFolder, 'ObjectSelectionSet_patch.json'), 'utf8'));
const menus = ['Click', 'Bed01', 'Bed02', 'Bed05', 'Bed06', 'Sofa', 'Sofa02', 'CinemaSeat02'];
const menuPatches = options.PatchList.filter(({Enabled}) => Enabled);
assert.deepEqual(menuPatches.map(({Method, Query, Value}) => [Method, Query, Value]), menus.map(id => [
    'Append',
    `ObjectSelectionSet[Id=${id}].SelectionSets[StateGroupId=Normal].InteractionBagList`,
    [venue],
]), 'Ground and furniture add the same native invitation to their existing actions');

const venueBag = rows('InteractionBag').get(venue);
assert.equal(venueBag.DisplayInfo.DisplayTextId, 'Have Sex Here');
assert.equal(venueBag.DisplayInfo.PanelIconId, 'Conversation_Icon_Mood');
assert.equal(venueBag.bUniqueInQueue, true);
assert.equal(venueBag.bAddSameInteractionToGroupMember, false);
assert.deepEqual(venueBag.InteractionSequence.flatMap(({InteractionInfos}) =>
    InteractionInfos.map(({InteractionId}) => InteractionId)), [venue]);

const action = rows('Interaction').get(venue);
assert.equal(action.NoneTargetPlayable, true, 'The same action can start from a targetless ground click');
assert.equal(action.bCheckCanMoveToSlot, false, 'Opening the picker must not walk Zois to furniture');
assert.equal(action.InteractionSlotUsage, 'None', 'Opening the picker must not reserve a seat');
assert.deepEqual(action.ActionIdList, ['Delay_0.1']);
console.log('Native relationship rules and shared ground, bed, and sofa menu registration passed.');
