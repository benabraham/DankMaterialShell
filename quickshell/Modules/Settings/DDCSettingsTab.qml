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
        }
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
