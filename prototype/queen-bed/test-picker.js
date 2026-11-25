// Run with Node. This checks the UIMod menu handoff to the native picker.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ui = path.join(__dirname, 'HZoiGameplayPrototype_4BD2AC16/ui/partner-picker');
const manifest = JSON.parse(fs.readFileSync(path.join(ui, 'uimod_manifest.json'), 'utf8'));
assert.equal(manifest.display.input_policy, 'passthrough');

async function check() {
    let activate, hidden = 0;
    const writes = [];
    const inzoi = {
        cli: { async execute(cmd, args) {
            if (cmd === 'entity.get_possessed') return { data: '{"entity_id":20}' };
            assert.equal(cmd, 'uimod.cfg_save');
            writes.push(args);
            return {};
        }},
        trigger: { onActivated(callback) { activate = callback; } },
        view: { hide() { hidden++; } },
    };
    vm.runInNewContext(fs.readFileSync(path.join(ui, 'app.js'), 'utf8'), { inzoi });
    await activate({ triggerId: 'hzoi_menu_ready' });
    const first = activate({ triggerId: 'hzoi_venue_invite', targetEntityId: 120 });
    await activate({ triggerId: 'hzoi_venue_invite', targetEntityId: 121 });
    await first;
    assert.equal(writes.length, 1);
    assert.equal(writes[0].key, 'invite');
    assert.match(writes[0].value, /^invite-\d+-\d+\|20\|120$/);
    assert.equal(hidden, 3);
}
check().then(() => console.log('Venue menu dispatch passes through and opens exactly one picker.'))
    .catch(error => { console.error(error); process.exitCode = 1; });
