import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Row {
    id: root

    property var preset: null

    readonly property string status: {
        DDCService.stateVersion;
        DDCService.lastAppliedPresetId;
        return DDCService.presetStatus(preset);
    }
    readonly property bool applying: DDCService.applyingPresetId !== "" && DDCService.applyingPresetId === (preset?.id ?? "")

    spacing: Theme.spacingXS

    DankButton {
        anchors.verticalCenter: parent.verticalCenter
        text: root.preset?.name ?? I18n.tr("Preset")
        iconName: root.applying ? "hourglass_empty" : (root.status === "modified" ? "edit" : (root.preset?.icon || "instant_mix"))
        iconSize: 14
        buttonHeight: 32
        horizontalPadding: Theme.spacingM
        backgroundColor: {
            if (root.status === "selected")
                return Theme.primary;
            if (root.status === "modified")
                return Theme.primaryContainer;
            return Theme.surfaceVariant;
        }
        textColor: {
            if (root.status === "selected")
                return Theme.primaryText;
            if (root.status === "modified")
                return Theme.surfaceText;
            return Theme.surfaceVariantText;
        }
        enabled: DDCService.applyingPresetId === ""
        opacity: root.applying ? 0.6 : 1.0
        onClicked: DDCService.applyPreset(root.preset)
    }

    DankActionButton {
        visible: root.status === "modified"
        anchors.verticalCenter: parent.verticalCenter
        iconName: "save"
        buttonSize: 32
        iconSize: 16
        iconColor: Theme.primary
        tooltipText: I18n.tr("Update preset with current values")
        onClicked: DDCService.updatePresetFromCurrent(root.preset.id)
    }
}
