// The menu entry hands off to SceneZOI's native picker; this view has no controls.
(function () {
    'use strict';
    var mod = 'HZoiGameplayPrototype_4BD2AC16';
    var writing = false;
    function decode(result) {
        if (result && result.success === false) throw new Error(result.message);
        var value = result && result.data !== undefined ? result.data : result;
        return typeof value === 'string' ? JSON.parse(value) : value;
    }
    function close() {
        writing = false;
        inzoi.view.hide();
    }
    inzoi.trigger.onActivated(function (event) {
        if (!event) return;
        if (event.triggerId === 'hzoi_menu_ready') {
            if (!writing) close();
            return;
        }
        if (event.triggerId !== 'hzoi_venue_invite' || writing) return;
        var bed = String(event.targetEntityId);
        if (!/^[1-9]\d*$/.test(bed)) return close();
        writing = true;
        return inzoi.cli.execute('entity.get_possessed').then(decode).then(function (current) {
            var controlled = String(current.entity_id);
            if (!/^[1-9]\d*$/.test(controlled)) throw new Error('No controlled Zoi');
            var nonce = 'invite-' + Date.now() + '-' + Math.floor(Math.random() * 1000000);
            return inzoi.cli.execute('uimod.cfg_save', {
                mod_id: mod, section: 'gameplay', key: 'invite', value: [nonce, controlled, bed].join('|')
            });
        }).then(close, function () {
            close();
            return inzoi.cli.execute('toast.show', { message: 'Could not open the HZoi partner picker.', immediate: true });
        });
    });
    close();
})();
