import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    Ref {
        service: DDCService
    }

    DankFlickable {
        anchors.fill: parent
        clip: true
        contentHeight: mainColumn.height + Theme.spacingXL
        contentWidth: width

        Column {
            id: mainColumn
            topPadding: 4

            width: Math.min(550, parent.width - Theme.spacingL * 2)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spacingXL

            SettingsCard {
                tab: "ddc"
                tags: ["ddc", "monitor", "display"]
                title: I18n.tr("DDC/CI")
                iconName: "display_settings"

                Column {
                    width: parent.width
                    spacing: Theme.spacingM

                    StyledText {
                        width: parent.width
                        text: DDCService.available ? I18n.tr("Detected monitors with DDC/CI support:") : I18n.tr("No DDC/CI monitors detected")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.Wrap
                    }

                    Repeater {
                        model: DDCService.devices

                        Column {
                            id: deviceColumn
                            required property var modelData
                            required property int index
                            property var deviceData: modelData
                            width: parent.width
                            spacing: Theme.spacingS

                            Rectangle {
                                visible: index > 0
                                width: parent.width
                                height: 1
                                color: Theme.outline
                                opacity: 0.2
                            }

                            StyledText {
                                text: (modelData.model || modelData.name || modelData.deviceId) + " (" + modelData.deviceId + ")"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }

                            Repeater {
                                model: modelData.features || []

                                RowLayout {
                                    required property var modelData
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    DankIcon {
                                        name: modelData.icon || "tune"
                                        size: 16
                                        color: Theme.surfaceVariantText
                                    }

                                    StyledText {
                                        text: modelData.name + " (0x" + modelData.code.toString(16).toUpperCase().padStart(2, "0") + ")"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        Layout.fillWidth: true
                                    }

                                    DankToggle {
                                        hideText: true
                                        checked: !isFeatureDisabled(deviceColumn.deviceData.deviceId, modelData.code)
                                        onToggled: checked => {
                                            toggleFeatureOverride(deviceColumn.deviceData.deviceId, modelData.code, !checked);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: DDCService.available
                        width: parent.width
                        height: 1
                        color: Theme.outline
                        opacity: 0.2
                    }

                    DankButton {
                        text: I18n.tr("Rescan Monitors")
                        backgroundColor: Theme.primary
                        textColor: Theme.primaryText
                        onClicked: DDCService.rescan()
                    }

                    StyledText {
                        visible: DDCService.available
                        width: parent.width
                        text: I18n.tr("Restore Factory Defaults")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        topPadding: Theme.spacingS
                    }

                    Repeater {
                        model: DDCService.devices

                        Column {
                            id: resetDeviceColumn
                            required property var modelData
                            property var deviceData: modelData
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                visible: DDCService.devices.length > 1
                                text: resetDeviceColumn.deviceData.model || resetDeviceColumn.deviceData.name || resetDeviceColumn.deviceData.deviceId
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }

                            Flow {
                                width: parent.width
                                spacing: Theme.spacingS

                                Repeater {
                                    model: [
                                        { type: "luminance", label: I18n.tr("Reset Brightness"), icon: "brightness_high" },
                                        { type: "geometry", label: I18n.tr("Reset Geometry"), icon: "aspect_ratio" },
                                        { type: "color", label: I18n.tr("Reset Color"), icon: "palette" }
                                    ]

                                    DankButton {
                                        required property var modelData
                                        visible: (resetDeviceColumn.deviceData.supportedResets || []).includes(modelData.type)
                                        iconName: modelData.icon
                                        iconSize: 14
                                        text: modelData.label
                                        backgroundColor: Theme.surfaceVariant
                                        textColor: Theme.surfaceVariantText
                                        onClicked: DDCService.resetDefaults(
                                            resetDeviceColumn.deviceData.deviceId,
                                            modelData.type
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }

            SettingsCard {
                tab: "ddc"
                tags: ["ddc", "monitor", "preset", "profile"]
                title: I18n.tr("Presets")
                iconName: "instant_mix"

                Column {
                    width: parent.width
                    spacing: Theme.spacingM

                    StyledText {
                        width: parent.width
                        text: I18n.tr("Presets apply saved monitor settings with one click from the control center. A preset can span multiple monitors.")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.Wrap
                    }

                    Repeater {
                        model: SettingsData.ddcPresets

                        Column {
                            id: presetColumn
                            required property var modelData
                            required property int index
                            property var presetData: modelData
                            width: parent.width
                            spacing: Theme.spacingS

                            Rectangle {
                                visible: presetColumn.index > 0
                                width: parent.width
                                height: 1
                                color: Theme.outline
                                opacity: 0.2
                            }

                            RowLayout {
                                width: parent.width
                                spacing: Theme.spacingS

                                DankTextField {
                                    Layout.fillWidth: true
                                    text: presetColumn.presetData.name || ""
                                    placeholderText: I18n.tr("Preset name")
                                    onEditingFinished: renamePreset(presetColumn.presetData.id, text)
                                }

                                DankActionButton {
                                    iconName: "delete"
                                    iconColor: Theme.error
                                    onClicked: removePreset(presetColumn.presetData.id)
                                }
                            }

                            Repeater {
                                model: DDCService.devices

                                Column {
                                    id: presetDeviceColumn
                                    required property var modelData
                                    property var deviceData: modelData
                                    readonly property var entry: presetEntry(presetColumn.presetData, modelData.deviceId)
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    DankToggle {
                                        width: parent.width
                                        text: presetDeviceColumn.deviceData.model || presetDeviceColumn.deviceData.name || presetDeviceColumn.deviceData.deviceId
                                        checked: presetDeviceColumn.entry !== undefined
                                        onToggled: checked => {
                                            setDeviceIncluded(presetColumn.presetData.id, presetDeviceColumn.deviceData.deviceId, checked);
                                        }
                                    }

                                    Repeater {
                                        model: presetDeviceColumn.entry?.values || []

                                        RowLayout {
                                            id: valueRow
                                            required property var modelData
                                            readonly property var featureDef: findFeature(presetDeviceColumn.deviceData, modelData.code)
                                            width: parent.width
                                            spacing: Theme.spacingS

                                            Item {
                                                Layout.preferredWidth: Theme.spacingL
                                            }

                                            StyledText {
                                                visible: (valueRow.featureDef?.type ?? "") !== "non_continuous"
                                                text: valueRow.featureDef?.name ?? ("0x" + valueRow.modelData.code.toString(16).toUpperCase().padStart(2, "0"))
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceVariantText
                                                Layout.preferredWidth: 120
                                                elide: Text.ElideRight
                                            }

                                            DankSlider {
                                                readonly property var def: valueRow.featureDef
                                                readonly property bool isGamma: valueRow.modelData.code === 0x72

                                                visible: (def?.type ?? "") === "continuous"
                                                Layout.fillWidth: true
                                                minimum: isGamma ? 80 : (def?.min ?? 0)
                                                maximum: isGamma ? 160 : ((def?.max ?? 0) > 0 ? def.max : 100)
                                                step: isGamma ? 20 : 1
                                                value: valueRow.modelData.value
                                                unit: def?.unit ?? ""
                                                valueOverride: isGamma ? value / 100 + 1.0 : ((def?.displayMultiply ?? 0) > 0 ? (def?.displayOffset ?? 0) + value * def.displayMultiply : -1)
                                                valueDecimals: isGamma ? 1 : 0
                                                onSliderDragFinished: finalValue => {
                                                    updatePresetValue(presetColumn.presetData.id, presetDeviceColumn.deviceData.deviceId, valueRow.modelData.code, finalValue);
                                                }
                                            }

                                            DankDropdown {
                                                readonly property var def: valueRow.featureDef

                                                visible: (def?.type ?? "") === "non_continuous"
                                                Layout.fillWidth: true
                                                text: def?.name ?? ""
                                                currentValue: {
                                                    const vals = def?.permittedValues ?? [];
                                                    for (let i = 0; i < vals.length; i++) {
                                                        if (vals[i].value === valueRow.modelData.value)
                                                            return vals[i].label;
                                                    }
                                                    return "0x" + valueRow.modelData.value.toString(16).toUpperCase().padStart(2, "0");
                                                }
                                                options: (def?.permittedValues ?? []).map(v => v.label)
                                                onValueChanged: value => {
                                                    const vals = def?.permittedValues ?? [];
                                                    for (let i = 0; i < vals.length; i++) {
                                                        if (vals[i].label === value) {
                                                            updatePresetValue(presetColumn.presetData.id, presetDeviceColumn.deviceData.deviceId, valueRow.modelData.code, vals[i].value);
                                                            break;
                                                        }
                                                    }
                                                }
                                            }

                                            DankToggle {
                                                visible: (valueRow.featureDef?.type ?? "") === "boolean"
                                                hideText: true
                                                checked: valueRow.modelData.value !== 0
                                                onToggled: checked => {
                                                    updatePresetValue(presetColumn.presetData.id, presetDeviceColumn.deviceData.deviceId, valueRow.modelData.code, checked ? 1 : 0);
                                                }
                                            }

                                            DankActionButton {
                                                iconName: "close"
                                                buttonSize: 24
                                                iconSize: 14
                                                onClicked: removePresetValue(presetColumn.presetData.id, presetDeviceColumn.deviceData.deviceId, valueRow.modelData.code);
                                            }
                                        }
                                    }

                                    RowLayout {
                                        visible: presetDeviceColumn.entry !== undefined && availableFeatures(presetDeviceColumn.deviceData, presetDeviceColumn.entry).length > 0
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        Item {
                                            Layout.preferredWidth: Theme.spacingL
                                        }

                                        DankDropdown {
                                            Layout.fillWidth: true
                                            text: I18n.tr("Add setting")
                                            currentValue: ""
                                            options: availableFeatures(presetDeviceColumn.deviceData, presetDeviceColumn.entry).map(f => featureLabel(f))
                                            onValueChanged: value => {
                                                const feats = availableFeatures(presetDeviceColumn.deviceData, presetDeviceColumn.entry);
                                                for (let i = 0; i < feats.length; i++) {
                                                    if (featureLabel(feats[i]) === value) {
                                                        addPresetValue(presetColumn.presetData.id, presetDeviceColumn.deviceData.deviceId, feats[i].code);
                                                        break;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Repeater {
                                model: (presetColumn.presetData.entries || []).filter(e => !DDCService.isDeviceConnected(e.deviceId))

                                RowLayout {
                                    required property var modelData
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    StyledText {
                                        text: modelData.deviceId + " (" + I18n.tr("not connected") + ")"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    DankActionButton {
                                        iconName: "close"
                                        buttonSize: 24
                                        iconSize: 14
                                        onClicked: setDeviceIncluded(presetColumn.presetData.id, modelData.deviceId, false)
                                    }
                                }
                            }
                        }
                    }

                    DankButton {
                        text: I18n.tr("Add Preset")
                        iconName: "add"
                        backgroundColor: Theme.primary
                        textColor: Theme.primaryText
                        enabled: DDCService.available
                        onClicked: addPreset()
                    }
                }
            }
        }
    }

    function presetsCopy() {
        return JSON.parse(JSON.stringify(SettingsData.ddcPresets || []));
    }

    function savePresets(presets) {
        SettingsData.set("ddcPresets", presets);
    }

    function addPreset() {
        const presets = presetsCopy();
        presets.push({
            "id": "preset-" + Date.now(),
            "name": I18n.tr("Preset") + " " + (presets.length + 1),
            "icon": "instant_mix",
            "entries": []
        });
        savePresets(presets);
    }

    function removePreset(presetId) {
        savePresets(presetsCopy().filter(p => p.id !== presetId));
        if (SettingsData.ddcLastAppliedPreset === presetId)
            SettingsData.set("ddcLastAppliedPreset", "");
    }

    function renamePreset(presetId, name) {
        const presets = presetsCopy();
        const preset = presets.find(p => p.id === presetId);
        if (!preset || !name || preset.name === name)
            return;
        preset.name = name;
        savePresets(presets);
    }

    function presetEntry(preset, deviceId) {
        return (preset.entries || []).find(e => e.deviceId === deviceId);
    }

    function findFeature(device, code) {
        return (device.features || []).find(f => f.code === code);
    }

    function featureLabel(feature) {
        return feature.name + " (0x" + feature.code.toString(16).toUpperCase().padStart(2, "0") + ")";
    }

    function availableFeatures(device, entry) {
        if (!entry)
            return [];
        const used = (entry.values || []).map(v => v.code);
        return (device.features || []).filter(f => !used.includes(f.code));
    }

    function setDeviceIncluded(presetId, deviceId, included) {
        const presets = presetsCopy();
        const preset = presets.find(p => p.id === presetId);
        if (!preset)
            return;
        preset.entries = preset.entries || [];
        const idx = preset.entries.findIndex(e => e.deviceId === deviceId);
        if (included && idx === -1) {
            preset.entries.push({
                "deviceId": deviceId,
                "values": []
            });
        } else if (!included && idx !== -1) {
            preset.entries.splice(idx, 1);
        } else {
            return;
        }
        savePresets(presets);
    }

    function addPresetValue(presetId, deviceId, code) {
        const presets = presetsCopy();
        const entry = presetEntry(presets.find(p => p.id === presetId) || {}, deviceId);
        if (!entry)
            return;
        entry.values = entry.values || [];
        if (entry.values.some(v => v.code === code))
            return;
        entry.values.push({
            "code": code,
            "value": DDCService.getFeatureValue(deviceId, code)
        });
        savePresets(presets);
    }

    function updatePresetValue(presetId, deviceId, code, value) {
        const presets = presetsCopy();
        const entry = presetEntry(presets.find(p => p.id === presetId) || {}, deviceId);
        const item = (entry?.values || []).find(v => v.code === code);
        if (!item || item.value === value)
            return;
        item.value = value;
        savePresets(presets);
    }

    function removePresetValue(presetId, deviceId, code) {
        const presets = presetsCopy();
        const entry = presetEntry(presets.find(p => p.id === presetId) || {}, deviceId);
        if (!entry)
            return;
        entry.values = (entry.values || []).filter(v => v.code !== code);
        savePresets(presets);
    }

    function isFeatureDisabled(deviceId, code) {
        const overrides = SettingsData.ddcFeatureOverrides || {};
        const devOverrides = overrides[deviceId];
        if (!devOverrides)
            return false;
        const disabled = devOverrides.disabled || [];
        return disabled.includes(code);
    }

    function toggleFeatureOverride(deviceId, code, disable) {
        let overrides = JSON.parse(JSON.stringify(SettingsData.ddcFeatureOverrides || {}));
        if (!overrides[deviceId])
            overrides[deviceId] = {};
        if (!overrides[deviceId].disabled)
            overrides[deviceId].disabled = [];

        let disabled = overrides[deviceId].disabled;
        const idx = disabled.indexOf(code);

        if (disable && idx === -1) {
            disabled.push(code);
        } else if (!disable && idx !== -1) {
            disabled.splice(idx, 1);
        }

        if (disabled.length === 0)
            delete overrides[deviceId];

        SettingsData.set("ddcFeatureOverrides", overrides);
    }
}
