const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const patchFolder = path.join(__dirname, 'HZoiGameplay_4BD2AC16', 'Content', 'JsonPatch');
function readJson(file) {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
}
function rows(table) {
    const patch = readJson(path.join(patchFolder, table + '_patch.json'));
    return new Map(patch.PatchList.map(({Value}) => [Value.Id ?? Value.ID, Value]));
}

const enqueue = rows('Condition_Enqueue').get('HZoiGameplay_EligibleForMood');
const talkRules = rows('Condition_Interaction_Talk');
const bags = rows('InteractionBag');
const invitation = bags.get('HZoiGameplay_Invite');
const coop = rows('Coop');
const romance = bags.get('HZoiGameplay_FindVenue');
const romanceVisibility = talkRules.get('HZoiGameplay_CanFindVenue');
assert.deepEqual(romance.InteractionBagTags, ['Sad', 'Uneasy', 'Cringing', 'Irritated', 'Worried']
    .map(emotion => `Lock_Emotion_${emotion}_Lv3`));
assert.deepEqual(romance.InteractionEnableConditionIds, ['HZoiGameplay_CanFindVenue', 'Not_FromRemoteCity_SelfTarget']);

const menuRowId = 'SceneZOI_Declaration_hzoi-gameplay__interaction_menu__invitations';
const menu = JSON.parse(rows('Text_UI').get(menuRowId).Text);
assert.equal(menu.schema_version, 1);
assert.equal(menu.owner, 'hzoi-gameplay');
assert.equal(menu.kind, 'interaction_menu');
const [furnitureMenu, groundMenu, romanceMenu] = menu.data.entries;
const trigger = readJson(path.join(patchFolder, '../../ui/venue-invitation/uimod_manifest.json'))
    .triggers.find(({type}) => type === 'interaction_menu');
assert.equal(furnitureMenu.id, '_UIMod_HZoiGameplay_4BD2AC16/venue-invitation~' + trigger.id);
assert.deepEqual(trigger.filter.objectCategory, ['Bed', 'Sofa']);
assert.equal(furnitureMenu.icon, trigger.icon);
assert.equal(furnitureMenu.label, trigger.label_key);
assert.equal(groundMenu.label, bags.get(groundMenu.id).DisplayInfo.DisplayTextId);
assert.equal(romanceMenu.id, romance.Id);
assert.equal(romanceMenu.label, romance.DisplayInfo.DisplayTextId);
assert.deepEqual(menu.data.entries.map(({menu}) => menu), ['object', 'object', 'talk']);
assert.deepEqual(groundMenu.mood_locks.map(mood => `Lock_Emotion_${mood}_Lv3`),
    bags.get(groundMenu.id).InteractionBagTags);
assert.deepEqual(furnitureMenu.mood_locks, groundMenu.mood_locks);
assert.equal(romanceMenu.mood_locks, undefined, 'The native Romance row already handles mood restrictions');
const catalogDir = path.join(__dirname, 'localization');
const locales = fs.readdirSync(catalogDir).filter(file => file.endsWith('.json'));
assert.equal(locales.length, 15);
for (const rule of [...menu.data.entries, menu.data.mood_tooltip]) {
    assert.equal(Object.keys(rule.translations).length, locales.length);
    for (const file of locales) {
        assert.equal(rule.translations[path.basename(file, '.json').toLowerCase()],
            readJson(path.join(catalogDir, file)).messages[rule.label]);
    }
}

// The native table treats zero as no eligible stage. Include every EB1GrowthStep bit.
const allLifeStages = 1 | 2 | 4 | 8 | 16 | 32 | 64 | 128 | 256;
for (const bag of ['Invite', 'FindVenue', 'SelectVenue', 'Walk', 'WalkRetry']) {
    assert.equal(bags.get(`HZoiGameplay_${bag}`).AgingConditionFlags, allLifeStages);
}

const walkIcon = "/Script/Engine.Texture2D'/Game/UI/Icon/Object/Action_Move01.Action_Move01'";
for (const name of ['Walk', 'WalkRetry', 'WitnessWalk']) {
    const display = bags.get(`HZoiGameplay_${name}`).DisplayInfo;
    assert.equal(display?.Icon, walkIcon, `${name} must use the native walking icon`);
    assert.equal(display.InteractionQueueIcon, walkIcon, `${name} must set the HUD queue icon explicitly`);
    assert.equal(display.DisplayTextId, 'InteractionBag_DisplayInfo_ClickMove_Self_DisplayTextId');
}
for (const name of ['Invite', 'FindVenue', 'SelectVenue']) {
    const display = bags.get(`HZoiGameplay_${name}`).DisplayInfo;
    assert.equal(display.Icon, "/Script/Engine.Texture2D'/Game/UI/Icon/Object/Action_Talk_Mood.Action_Talk_Mood'");
    assert.equal(display.PanelIconId, 'Conversation_Icon_Mood');
}

const queueTextId = 'mod_InteractionBag_DisplayInfo_HZoiGameplay_Invite_OverrideQueueTextId';
assert.equal(invitation.DisplayInfo.OverrideQueueTextId, queueTextId);
for (const [branch, suffix] of [['Accept', ''], ['Refuse', '_Fail']]) {
    const dialogue = coop.get(`HZoiGameplay_Coop_${branch}`).TaskInfos[1];
    for (const [index, feedback] of ['', '_Feedback'].entries()) {
        const bagId = `HZoiGameplay_InviteDialogue${suffix}${feedback}`;
        const scenarios = dialogue.RolePlayingInfos[index].ScenarioInfos;
        assert.equal(scenarios[0].InteractionBagId, bagId);
        const bag = bags.get(bagId);
        assert.equal(bag.DisplayInfo.OverrideQueueTextId, queueTextId);
        assert.equal(bag.InteractionSequence[0].InteractionInfos[0].InteractionId,
            `Coop_TalkLike_Before_MakeLove${suffix}${feedback}`);
    }
}

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
    assert.equal(matches(romanceVisibility, state) && state.remote === undefined, expected.length > 0);
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
check({}, []);
check({romance: 29}, []);
check({romance: 30}, [[accept, 0.3], [refuse, 0.7]]);
check({romance: 30, emotion: 'Positive'}, [[accept, 1]]);
check({romance: 60}, [[accept, 0.3], [refuse, 0.7]]);
check({romance: 61}, [[accept, 1]]);
check({relationship: 'Youth_Lover'}, [[accept, 0.7], [refuse, 0.3]]);
check({relationship: 'engagement'}, [[accept, 0.7], [refuse, 0.3]]);
check({relationship: 'Youth_Lover', romance: -31}, []);
check({relationship: 'Youth_Lover', romance: -30}, [[accept, 0.7], [refuse, 0.3]]);
check({relationship: 'engagement', romance: -31}, []);
check({relationship: 'engagement', romance: -30}, [[accept, 0.7], [refuse, 0.3]]);
check({familyRelationship: 'Spouse', family: -31}, []);
check({familyRelationship: 'Spouse', family: -30}, [[accept, 0.7], [refuse, 0.3]]);
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
const menuPatches = options.PatchList.filter(({Enabled}) => Enabled);
assert.deepEqual(menuPatches.map(({Method, Query, Value}) => [Method, Query, Value]), [[
    'Append',
    'ObjectSelectionSet[Id=Click].SelectionSets[StateGroupId=Normal].InteractionBagList',
    [venue],
]], 'Ground capture uses the native interaction. Furniture uses the SceneZOI profile filter.');
const manifest = JSON.parse(fs.readFileSync(path.join(patchFolder, '..', '..', 'ui',
    'venue-invitation', 'uimod_manifest.json'), 'utf8'));
assert.deepEqual(manifest.triggers.filter(({type}) => type === 'interaction_menu'), [{
    id: 'scenezoi_furniture', type: 'interaction_menu', target: 'object', label_key: 'Have Sex Here',
    icon: '/Game/UI/Icon/Conversation/Conversation_Icon_Mood.Conversation_Icon_Mood',
    filter: {objectCategory: ['Bed', 'Sofa']},
}]);
assert.equal(manifest.display.input_policy, 'passthrough');

const venueBag = bags.get(venue);
assert.deepEqual(venueBag.InteractionBagTags, romance.InteractionBagTags);
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
console.log('Native relationship rules, ground action and generic furniture trigger passed.');
