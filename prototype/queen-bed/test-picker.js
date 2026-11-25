// Run with Node. This checks the UIMod menu handoff to the native picker.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ui = path.join(__dirname, 'HZoiGameplayPrototype_4BD2AC16/ui/partner-picker');
const manifest = JSON.parse(fs.readFileSync(path.join(ui, 'uimod_manifest.json'), 'utf8'));
assert.equal(manifest.display.input_policy, 'passthrough');

async function check() {
    let activate, hidden = 0, fail = false, language = 'ja-JP_mod';
    const writes = [], toasts = [];
    const inzoi = {
        cli: { async execute(cmd, args) {
            if (cmd === 'entity.get_possessed') {
                if (fail) throw new Error('Injected picker failure');
                return { data: '{"entity_id":20}' };
            }
            if (cmd === 'gameplay.get_settings') return { data: {language} };
            if (cmd === 'toast.show') { toasts.push(args.message); return {}; }
            assert.equal(cmd, 'uimod.cfg_save');
            writes.push(args);
            return {};
        }},
        trigger: { onActivated(callback) { activate = callback; } },
        view: { hide() { hidden++; } },
    };
    const context = { inzoi, window: {} };
    for (const script of ['translations.js', 'app.js']) {
        vm.runInNewContext(fs.readFileSync(path.join(ui, script), 'utf8'), context);
    }
    await activate({ triggerId: 'hzoi_menu_ready' });
    const first = activate({ triggerId: 'hzoi_venue_invite', targetEntityId: 120 });
    await activate({ triggerId: 'hzoi_venue_invite', targetEntityId: 121 });
    await first;
    assert.equal(writes.length, 1);
    assert.equal(writes[0].key, 'invite');
    assert.match(writes[0].value, /^invite-\d+-\d+\|20\|120$/);
    assert.equal(hidden, 3);
    fail = true;
    await activate({ triggerId: 'hzoi_venue_invite', targetEntityId: 120 });
    assert.equal(toasts[0], "HZoi の相手選択画面を開けませんでした。");
    language = 'unknown';
    await activate({ triggerId: 'hzoi_venue_invite', targetEntityId: 121 });
    assert.equal(toasts[1], 'Could not open the HZoi partner picker.');
    assert.equal(writes.length, 1);
}
check().then(() => console.log('Venue menu dispatch passes through and opens exactly one picker.'))
    .catch(error => { console.error(error); process.exitCode = 1; });
