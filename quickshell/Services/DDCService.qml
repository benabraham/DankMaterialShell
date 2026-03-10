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
