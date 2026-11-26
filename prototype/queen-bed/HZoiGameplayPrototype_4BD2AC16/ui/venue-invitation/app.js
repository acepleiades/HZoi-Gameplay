// Forward the exact native object-menu target to the gameplay invitation.
(function () {
    'use strict';
    var writing = false;
    function close() {
        writing = false;
        inzoi.view.hide();
    }

    inzoi.trigger.onActivated(function (event) {
        if (writing || !event) return;
        if (event.triggerId === 'invite_ready') return close();
        if (event.triggerId !== 'scenezoi_furniture') return;
        var target = String(event.targetEntityId);
        if (!/^[1-9]\d*$/.test(target)) return close();
        writing = true;
        return inzoi.cli.execute('entity.get_possessed').then(function (reply) {
            if (!reply || reply.success === false) return;
            var result = reply.data !== undefined ? reply.data : reply;
            if (typeof result === 'string') result = JSON.parse(result);
            var initiator = String(result && result.entity_id);
            if (!/^[1-9]\d*$/.test(initiator)) return;
            var nonce = 'invite-' + Date.now() + '-' + Math.floor(Math.random() * 1000000);
            return inzoi.cli.execute('uimod.cfg_save', {
                mod_id: 'HZoiGameplayPrototype_4BD2AC16',
                section: 'gameplay',
                key: 'furniture_invite',
                value: [nonce, initiator, target].join('|')
            });
        }).then(close, close);
    });
    close();
})();
