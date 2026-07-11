pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common

Singleton {
    id: root

    property int refCount: 0
    property bool available: false
    property bool scanning: false
    property var devices: []
    property string currentDevice: ""
    property var featureValues: ({})
    property int stateVersion: 0

    signal stateChanged

    onRefCountChanged: {
        if (refCount > 0) {
            ensureSubscription();
        } else if (refCount === 0 && DMSService.activeSubscriptions.includes("ddc")) {
            DMSService.removeSubscription("ddc");
        }
    }

    function ensureSubscription() {
        if (refCount <= 0)
            return;
        if (!DMSService.isConnected)
            return;
        if (DMSService.activeSubscriptions.includes("ddc"))
            return;
        if (DMSService.activeSubscriptions.includes("all"))
            return;
        DMSService.addSubscription("ddc");
        if (available)
            getState();
    }

    property bool stateInitialized: false
    readonly property string socketPath: Quickshell.env("DMS_SOCKET")

    Component.onCompleted: {
        if (socketPath && socketPath.length > 0)
            checkDMSCapabilities();
    }

    Connections {
        target: DMSService

        function onConnectionStateChanged() {
            if (DMSService.isConnected) {
                checkDMSCapabilities();
                ensureSubscription();
            }
        }
    }

    Connections {
        target: DMSService
        enabled: DMSService.isConnected

        function onDdcStateUpdate(data) {
            updateFromState(data);
        }

        function onCapabilitiesChanged() {
            checkDMSCapabilities();
        }
    }

    function checkDMSCapabilities() {
        if (!DMSService.isConnected)
            return;
        if (DMSService.capabilities.length === 0)
            return;
        available = DMSService.capabilities.includes("ddc");

        if (available && !stateInitialized) {
            stateInitialized = true;
            getState();
        }
    }

    function getState() {
        if (!available)
            return;
        DMSService.sendRequest("ddc.getState", null, response => {
            if (response.result)
                updateFromState(response.result);
        });
    }

    function updateFromState(state) {
        if (!state)
            return;

        scanning = state.scanning || false;

        const devs = state.devices || [];
        devices = devs;

        let vals = {};
        for (let i = 0; i < devs.length; i++) {
            const dev = devs[i];
            let devVals = {};
            const features = dev.features || [];
            for (let j = 0; j < features.length; j++) {
                const feat = features[j];
                devVals[feat.code] = feat.current;
            }
            vals[dev.deviceId] = devVals;
        }
        featureValues = vals;

        if (devs.length > 0 && (!currentDevice || !devs.some(d => d.deviceId === currentDevice)))
            currentDevice = devs[0].deviceId;

        stateVersion++;
        stateChanged();
    }

    function getFeatureValue(deviceId, code) {
        const devVals = featureValues[deviceId];
        if (!devVals)
            return 0;
        return devVals[code] || 0;
    }

    function setFeature(deviceId, code, value, callback) {
        // Skip optimistic update when callback is used (toggles/dropdowns)
        // to prevent race conditions with visibility logic
        if (!callback) {
            let vals = Object.assign({}, featureValues);
            if (!vals[deviceId])
                vals[deviceId] = {};
            vals[deviceId] = Object.assign({}, vals[deviceId]);
            vals[deviceId][code] = value;
            featureValues = vals;
            stateVersion++;
        }

        DMSService.sendRequest("ddc.setFeature", {
            "device": deviceId,
            "code": code,
            "value": value
        }, callback);
    }

    function getDeviceFeatures(deviceId) {
        let features = [];
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].deviceId === deviceId) {
                features = devices[i].features || [];
                break;
            }
        }

        const overrides = SettingsData.ddcFeatureOverrides || {};
        const devOverrides = overrides[deviceId];
        if (!devOverrides)
            return features;

        const disabled = devOverrides.disabled || [];
        if (disabled.length > 0)
            features = features.filter(f => !disabled.includes(f.code));

        const hiddenValues = devOverrides.hiddenValues || {};
        if (Object.keys(hiddenValues).length > 0) {
            features = features.map(f => {
                const hidden = hiddenValues[f.code];
                if (!hidden || !f.permittedValues) return f;
                const filtered = Object.assign({}, f);
                filtered.permittedValues = f.permittedValues.filter(pv => !hidden.includes(pv.value));
                return filtered;
            });
        }

        return features;
    }

    function getDeviceFeaturesByCategory(deviceId, category) {
        const features = getDeviceFeatures(deviceId);
        return features.filter(f => f.category === category);
    }

    readonly property var categoryOrder: ["image", "color", "audio", "display"]

    function getVisibleCategories(deviceId) {
        const features = getDeviceFeatures(deviceId);
        const seen = {};
        for (let i = 0; i < features.length; i++)
            seen[features[i].category] = true;
        return categoryOrder.filter(c => seen[c]);
    }

    function setCurrentDevice(deviceId) {
        currentDevice = deviceId;
    }

    readonly property var presets: SettingsData.ddcPresets || []
    readonly property string lastAppliedPresetId: SettingsData.ddcLastAppliedPreset || ""
    property string applyingPresetId: ""
    // Session-only snapshot of monitor values taken just before the last apply.
    // Powers "revert to previous values" and detection of tweaks made since.
    property var undoSnapshot: null

    function isDeviceConnected(deviceId) {
        return devices.some(d => d.deviceId === deviceId);
    }

    function presetTasks(preset) {
        const tasks = [];
        const entries = preset?.entries || [];
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i];
            if (!isDeviceConnected(entry.deviceId))
                continue;
            const values = entry.values || [];
            for (let j = 0; j < values.length; j++)
                tasks.push({
                    "device": entry.deviceId,
                    "code": values[j].code,
                    "value": values[j].value
                });
        }
        return tasks;
    }

    // "active"   - all preset values match the monitors, however they got there
    // "modified" - last applied and some of its values drifted since
    // "normal"   - otherwise
    function presetStatus(preset) {
        if (!preset)
            return "normal";
        const tasks = presetTasks(preset);
        if (tasks.length === 0)
            return "normal";
        if (tasks.every(t => getFeatureValue(t.device, t.code) === t.value))
            return "active";
        return preset.id === lastAppliedPresetId ? "modified" : "normal";
    }

    function enabledCodeSet(deviceId) {
        const codes = {};
        const feats = getDeviceFeatures(deviceId);
        for (let i = 0; i < feats.length; i++)
            codes[feats[i].code] = true;
        return codes;
    }

    // Diff of monitor values vs the snapshot taken when `preset` was applied.
    // tracked: codes the preset contains; untracked: other enabled features.
    function changesSinceApply(preset) {
        const result = {
            "tracked": [],
            "untracked": []
        };
        if (!preset || !undoSnapshot || undoSnapshot.presetId !== preset.id)
            return result;

        const trackedCodes = {};
        const entries = preset.entries || [];
        for (let i = 0; i < entries.length; i++) {
            const map = {};
            const values = entries[i].values || [];
            for (let j = 0; j < values.length; j++)
                map[values[j].code] = true;
            trackedCodes[entries[i].deviceId] = map;
        }

        const snapVals = undoSnapshot.values || {};
        for (const devId in snapVals) {
            if (!isDeviceConnected(devId))
                continue;
            const enabled = enabledCodeSet(devId);
            const snapDev = snapVals[devId];
            for (const codeKey in snapDev) {
                const code = Number(codeKey);
                if (!enabled[code])
                    continue;
                const current = getFeatureValue(devId, code);
                if (current === snapDev[codeKey])
                    continue;
                const change = {
                    "device": devId,
                    "code": code,
                    "from": snapDev[codeKey],
                    "to": current
                };
                if (trackedCodes[devId] && trackedCodes[devId][code])
                    result.tracked.push(change);
                else
                    result.untracked.push(change);
            }
        }
        return result;
    }

    // Refresh a preset's values from the monitors and optionally absorb
    // changed features it didn't contain yet (from changesSinceApply).
    function refreshPresetValues(preset, untrackedChanges) {
        preset.entries = preset.entries || [];
        for (let i = 0; i < untrackedChanges.length; i++) {
            const c = untrackedChanges[i];
            let entry = preset.entries.find(e => e.deviceId === c.device);
            if (!entry) {
                entry = {
                    "deviceId": c.device,
                    "values": []
                };
                preset.entries.push(entry);
            }
            entry.values = entry.values || [];
            if (!entry.values.some(v => v.code === c.code))
                entry.values.push({
                    "code": c.code,
                    "value": c.to
                });
        }
        for (let i = 0; i < preset.entries.length; i++) {
            const entry = preset.entries[i];
            if (!isDeviceConnected(entry.deviceId))
                continue;
            const values = entry.values || [];
            for (let j = 0; j < values.length; j++)
                values[j].value = getFeatureValue(entry.deviceId, values[j].code);
        }
    }

    function updatePresetFromCurrent(presetId, includeChanged) {
        const presets = JSON.parse(JSON.stringify(SettingsData.ddcPresets || []));
        const preset = presets.find(p => p.id === presetId);
        if (!preset)
            return;
        const untracked = includeChanged ? changesSinceApply(preset).untracked : [];
        refreshPresetValues(preset, untracked);
        SettingsData.set("ddcPresets", presets);
    }

    function uniquePresetName(presets, base) {
        let n = 2;
        let name = base + " " + n;
        while (presets.some(p => p.name === name))
            name = base + " " + (++n);
        return name;
    }

    // New preset from the source's codes plus any features changed since
    // apply, all at current monitor values. Becomes the last-applied preset.
    function saveAsNewPreset(presetId) {
        const presets = JSON.parse(JSON.stringify(SettingsData.ddcPresets || []));
        const source = presets.find(p => p.id === presetId);
        if (!source)
            return;
        const copy = JSON.parse(JSON.stringify(source));
        copy.id = "preset-" + Date.now();
        copy.name = uniquePresetName(presets, source.name);
        refreshPresetValues(copy, changesSinceApply(source).untracked);
        presets.push(copy);
        SettingsData.set("ddcPresets", presets);
        SettingsData.set("ddcLastAppliedPreset", copy.id);
        if (undoSnapshot)
            undoSnapshot = Object.assign({}, undoSnapshot, {
                "presetId": copy.id
            });
    }

    function snapshotValues() {
        const snap = {};
        for (const devId in featureValues)
            snap[devId] = Object.assign({}, featureValues[devId]);
        return snap;
    }

    function applyPreset(preset) {
        if (!available || applyingPresetId !== "")
            return;
        const tasks = presetTasks(preset);
        if (tasks.length === 0)
            return;

        // Only take a new snapshot when the apply will actually change
        // something, so re-clicking an active chip can't destroy the undo.
        if (tasks.some(t => getFeatureValue(t.device, t.code) !== t.value))
            undoSnapshot = {
                "presetId": preset.id,
                "values": snapshotValues()
            };
        else if (undoSnapshot)
            undoSnapshot = Object.assign({}, undoSnapshot, {
                "presetId": preset.id
            });

        applyingPresetId = preset.id;
        SettingsData.set("ddcLastAppliedPreset", preset.id);
        runTasks(tasks);
    }

    // Restore the values recorded before the last apply, then leave the preset.
    function revertToPrevious() {
        if (!available || applyingPresetId !== "" || !undoSnapshot)
            return;
        const tasks = [];
        const snapVals = undoSnapshot.values || {};
        for (const devId in snapVals) {
            if (!isDeviceConnected(devId))
                continue;
            const enabled = enabledCodeSet(devId);
            const snapDev = snapVals[devId];
            for (const codeKey in snapDev) {
                const code = Number(codeKey);
                if (!enabled[code])
                    continue;
                if (getFeatureValue(devId, code) !== snapDev[codeKey])
                    tasks.push({
                        "device": devId,
                        "code": code,
                        "value": snapDev[codeKey]
                    });
            }
        }
        undoSnapshot = null;
        SettingsData.set("ddcLastAppliedPreset", "");
        if (tasks.length === 0)
            return;
        applyingPresetId = "__revert__";
        runTasks(tasks);
    }

    function runTasks(tasks) {
        let vals = Object.assign({}, featureValues);
        for (let i = 0; i < tasks.length; i++) {
            const t = tasks[i];
            vals[t.device] = Object.assign({}, vals[t.device] || {});
            vals[t.device][t.code] = t.value;
        }
        featureValues = vals;
        stateVersion++;

        let idx = 0;
        const next = () => {
            if (idx >= tasks.length) {
                applyingPresetId = "";
                getState();
                return;
            }
            const t = tasks[idx++];
            DMSService.sendRequest("ddc.setFeature", t, next);
        };
        next();
    }

    function resetDefaults(deviceId, resetType) {
        DMSService.sendRequest("ddc.resetDefaults", {
            "device": deviceId,
            "type": resetType
        });
    }

    function rescan() {
        DMSService.sendRequest("ddc.rescan", null, response => {
            if (response.result)
                updateFromState(response.result);
        });
    }
}
