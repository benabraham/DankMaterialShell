import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

Rectangle {
    id: root

    implicitHeight: (monitorDropdown.visible ? monitorDropdown.height + Theme.spacingS : 0) + (categoryTabItem.visible ? categoryTabItem.height + Theme.spacingS : 0) + controlsColumn.implicitHeight + Theme.spacingM * 2
    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHigh

    readonly property string deviceId: DDCService.currentDevice
    readonly property var visibleCategories: DDCService.getVisibleCategories(deviceId)
    property int currentCategoryIndex: 0
    readonly property string currentCategory: visibleCategories.length > 0 ? visibleCategories[currentCategoryIndex] || visibleCategories[0] : ""
    readonly property var filteredFeatures: DDCService.getDeviceFeaturesByCategory(deviceId, currentCategory)
    readonly property int version: DDCService.stateVersion

    readonly property var categoryInfo: ({
        "color": { "text": I18n.tr("Color"), "icon": "palette" },
        "audio": { "text": I18n.tr("Audio"), "icon": "volume_up" },
        "image": { "text": I18n.tr("Image"), "icon": "tune" },
        "display": { "text": I18n.tr("Settings"), "icon": "settings" },
        "game": { "text": I18n.tr("Game"), "icon": "sports_esports" }
    })

    function getCategoryTabs() {
        let tabs = [];
        for (let i = 0; i < visibleCategories.length; i++) {
            const cat = visibleCategories[i];
            const info = categoryInfo[cat] || { "text": cat, "icon": "settings" };
            tabs.push({ "text": info.text, "icon": info.icon });
        }
        return tabs;
    }

    DankDropdown {
        id: monitorDropdown
        visible: DDCService.devices.length > 1
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacingM
        text: I18n.tr("Monitor")
        currentValue: {
            for (let i = 0; i < DDCService.devices.length; i++) {
                if (DDCService.devices[i].deviceId === deviceId) {
                    const dev = DDCService.devices[i];
                    return dev.model || dev.name || dev.deviceId;
                }
            }
            return deviceId;
        }
        options: {
            let opts = [];
            for (let i = 0; i < DDCService.devices.length; i++) {
                const dev = DDCService.devices[i];
                opts.push(dev.model || dev.name || dev.deviceId);
            }
            return opts;
        }
        onValueChanged: value => {
            for (let i = 0; i < DDCService.devices.length; i++) {
                const dev = DDCService.devices[i];
                const label = dev.model || dev.name || dev.deviceId;
                if (label === value) {
                    DDCService.setCurrentDevice(dev.deviceId);
                    break;
                }
            }
        }
    }

    Item {
        id: categoryTabItem
        visible: visibleCategories.length > 1
        anchors.top: monitorDropdown.visible ? monitorDropdown.bottom : parent.top
        anchors.topMargin: Theme.spacingS
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.spacingM
        anchors.rightMargin: Theme.spacingM
        height: visible ? categoryTabBar.tabHeight + 12 : 0

        DankTabBar {
            id: categoryTabBar
            width: parent.width
            model: getCategoryTabs()
            currentIndex: currentCategoryIndex
            onTabClicked: index => {
                currentCategoryIndex = index;
            }
        }
    }

    DankFlickable {
        anchors.top: categoryTabItem.visible ? categoryTabItem.bottom : (monitorDropdown.visible ? monitorDropdown.bottom : parent.top)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: Theme.spacingM
        anchors.leftMargin: Theme.spacingM
        anchors.rightMargin: Theme.spacingM
        anchors.bottomMargin: Theme.spacingM
        contentHeight: controlsColumn.height
        clip: true

        Column {
            id: controlsColumn
            width: parent.width
            spacing: Theme.spacingS

            Repeater {
                model: filteredFeatures

                Loader {
                    required property var modelData
                    required property int index
                    width: controlsColumn.width

                    readonly property bool hiddenByPreset: {
                        const preset = DDCService.getFeatureValue(deviceId, 0x14);
                        if (preset === 0) return false; // no preset feature on device
                        // sRGB: hide color preset dropdown and all color adjustments
                        if (preset === 0x01) {
                            const srgbHidden = [0x12, 0x14, 0x0C, 0x16, 0x18, 0x1A, 0x6C, 0x6E, 0x70, 0x8A, 0x4A];
                            return srgbHidden.includes(modelData.code);
                        }
                        // Hide temp slider when any preset is active
                        if (modelData.code === 0x0C) return true;
                        // Hide RGB gain/black level unless User mode
                        const rgbCodes = [0x16, 0x18, 0x1A, 0x6C, 0x6E, 0x70];
                        if (rgbCodes.includes(modelData.code))
                            return preset !== 0x0B && preset !== 0x0C && preset !== 0x0D;
                        return false;
                    }
                    visible: !hiddenByPreset
                    active: !hiddenByPreset

                    sourceComponent: {
                        if (modelData.type === "continuous")
                            return sliderDelegate;
                        if (modelData.type === "non_continuous")
                            return dropdownDelegate;
                        if (modelData.type === "boolean")
                            return toggleDelegate;
                        return null;
                    }
                }
            }
        }
    }

    Component {
        id: sliderDelegate

        Column {
            width: parent?.width ?? 0
            spacing: 2

            Row {
                visible: modelData.code !== 0x0C
                spacing: Theme.spacingS
                leftPadding: Theme.spacingXS

                DankIcon {
                    name: modelData.icon || "tune"
                    size: 16
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: modelData.name || ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            DankSlider {
                readonly property int displayMult: modelData.displayMultiply || 0
                readonly property int displayOff: modelData.displayOffset || 0
                readonly property bool isGamma: modelData.code === 0x72

                width: parent.width
                minimum: isGamma ? 80 : (modelData.min || 0)
                maximum: isGamma ? 160 : (modelData.max > 0 ? modelData.max : 100)
                step: isGamma ? 20 : 1
                value: DDCService.getFeatureValue(deviceId, modelData.code)
                leftIcon: modelData.icon || "tune"
                showValue: true
                unit: modelData.unit || ""
                valueOverride: isGamma ? value / 100 + 1.0 : (displayMult > 0 ? displayOff + value * displayMult : -1)
                valueDecimals: isGamma ? 1 : 0

                onSliderValueChanged: newValue => {
                    DDCService.setFeature(deviceId, modelData.code, newValue);
                }
            }
        }
    }

    Component {
        id: dropdownDelegate

        Row {
            property bool pending: false

            width: parent?.width ?? 0
            spacing: Theme.spacingS
            leftPadding: Theme.spacingXS
            opacity: pending ? 0.6 : 1.0

            DankIcon {
                name: modelData.icon || "settings"
                size: 18
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            DankDropdown {
                width: parent.width - Theme.spacingS - 18 - Theme.spacingXS * 2
                text: modelData.name || ""
                enabled: !parent.pending
                currentValue: {
                    const vals = modelData.permittedValues || [];
                    const current = DDCService.getFeatureValue(deviceId, modelData.code);
                    for (let i = 0; i < vals.length; i++) {
                        if (vals[i].value === current)
                            return vals[i].label;
                    }
                    return "0x" + current.toString(16).toUpperCase().padStart(2, "0");
                }
                options: {
                    const vals = modelData.permittedValues || [];
                    return vals.map(v => v.label);
                }
                onValueChanged: value => {
                    if (parent.pending) return;
                    const vals = modelData.permittedValues || [];
                    for (let i = 0; i < vals.length; i++) {
                        if (vals[i].label === value) {
                            parent.pending = true;
                            DDCService.setFeature(deviceId, modelData.code, vals[i].value, () => {
                                parent.pending = false;
                            });
                            break;
                        }
                    }
                }
            }
        }
    }

    Component {
        id: toggleDelegate

        DankToggle {
            property bool pending: false

            width: parent?.width ?? 0
            text: modelData.name || ""
            checked: DDCService.getFeatureValue(deviceId, modelData.code) !== 0
            enabled: modelData.code !== 0xEB || DDCService.getFeatureValue(deviceId, 0xE9) === 0
            toggling: pending
            onToggled: checked => {
                if (pending) return;
                pending = true;
                DDCService.setFeature(deviceId, modelData.code, checked ? 1 : 0, () => {
                    pending = false;
                });
            }
        }
    }
}
