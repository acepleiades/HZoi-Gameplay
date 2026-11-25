const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const patchFolder = path.join(__dirname, 'HZoiGameplayPrototype_4BD2AC16', 'Content', 'JsonPatch');
function rows(table) {
    const patch = fs.readFileSync(path.join(patchFolder, table + '_patch.json'), 'utf8');
    return new Map(JSON.parse(patch).PatchList.map(({Value}) => [Value.Id, Value]));
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
                case 'GrowthStep': actual = state.belowYouth === BaseObject ? -1 : 0; expected = 0;
                    assert.equal(S1, 'Youth'); break;
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
check({belowYouth: 'Target'}, []);
check({familyRelationship: 'Sibling'}, []);
console.log('Native invitation rules passed');
