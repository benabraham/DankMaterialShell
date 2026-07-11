import QtQuick
import QtQuick.Controls
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
    readonly property bool isLastApplied: (preset?.id ?? "") === DDCService.lastAppliedPresetId
    readonly property var sessionChanges: {
        DDCService.stateVersion;
        DDCService.undoSnapshot;
        return DDCService.changesSinceApply(preset);
    }
    readonly property bool canRevert: isLastApplied && (sessionChanges.tracked.length > 0 || sessionChanges.untracked.length > 0)
    readonly property bool hasNewTweaks: isLastApplied && sessionChanges.untracked.length > 0
    readonly property bool applying: DDCService.applyingPresetId !== "" && DDCService.applyingPresetId === (preset?.id ?? "")

    spacing: Theme.spacingXS

    DankButton {
        id: mainButton
        anchors.verticalCenter: parent.verticalCenter
        text: root.preset?.name ?? I18n.tr("Preset")
        iconName: root.applying ? "hourglass_empty" : (root.status === "modified" ? "edit" : (root.preset?.icon || "instant_mix"))
        iconSize: 14
        buttonHeight: 32
        horizontalPadding: Theme.spacingM
        backgroundColor: {
            if (root.status === "active")
                return Theme.primary;
            if (root.status === "modified")
                return Theme.primaryContainer;
            return Theme.surfaceVariant;
        }
        textColor: {
            if (root.status === "active")
                return Theme.primaryText;
            if (root.status === "modified")
                return Theme.surfaceText;
            return Theme.surfaceVariantText;
        }
        enabled: DDCService.applyingPresetId === ""
        opacity: root.applying ? 0.6 : 1.0
        onClicked: DDCService.applyPreset(root.preset)

        Rectangle {
            visible: root.status === "active" && root.hasNewTweaks
            width: 6
            height: 6
            radius: 3
            color: Theme.primaryText
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 4
            anchors.rightMargin: 4
        }
    }

    DankActionButton {
        visible: root.isLastApplied && (root.status === "modified" || root.canRevert || root.hasNewTweaks)
        anchors.verticalCenter: parent.verticalCenter
        iconName: "more_vert"
        buttonSize: 32
        iconSize: 16
        iconColor: Theme.primary
        tooltipText: I18n.tr("Preset options")
        onClicked: presetMenu.open()
    }

    function buildMenuItems() {
        const items = [];
        const untracked = sessionChanges.untracked.length;
        if (canRevert)
            items.push({
                "icon": "undo",
                "label": I18n.tr("Revert to previous values"),
                "action": "revert"
            });
        if (status === "modified")
            items.push({
                "icon": "save",
                "label": I18n.tr("Update preset"),
                "action": "update"
            });
        if (untracked > 0)
            items.push({
                "icon": "playlist_add",
                "label": status === "modified" ? I18n.tr("Update + add changed (%1)").arg(untracked) : I18n.tr("Add changed settings (%1)").arg(untracked),
                "action": "updateAdd"
            });
        if (status === "modified" || untracked > 0)
            items.push({
                "icon": "add_circle",
                "label": I18n.tr("Save as new preset"),
                "action": "saveAsNew"
            });
        return items;
    }

    function runMenuAction(action) {
        presetMenu.close();
        switch (action) {
        case "revert":
            DDCService.revertToPrevious();
            break;
        case "update":
            DDCService.updatePresetFromCurrent(preset.id, false);
            break;
        case "updateAdd":
            DDCService.updatePresetFromCurrent(preset.id, true);
            break;
        case "saveAsNew":
            DDCService.saveAsNewPreset(preset.id);
            break;
        }
    }

    Popup {
        id: presetMenu

        property var menuItems: []

        y: mainButton.height + Theme.spacingXS
        width: 240
        implicitHeight: menuColumn.implicitHeight + Theme.spacingS * 2
        padding: 0
        margins: Theme.spacingS
        onAboutToShow: menuItems = root.buildMenuItems()

        background: Rectangle {
            color: Theme.floatingSurface
            radius: Theme.cornerRadius
            border.color: BlurService.borderColor
            border.width: BlurService.borderWidth
        }

        contentItem: Column {
            id: menuColumn
            padding: Theme.spacingS
            spacing: Theme.spacingXS

            Repeater {
                model: presetMenu.menuItems

                Rectangle {
                    id: itemRect
                    required property var modelData
                    width: presetMenu.width - Theme.spacingS * 2
                    height: 32
                    radius: Theme.cornerRadius
                    color: itemArea.containsMouse ? BlurService.hoverColor(Theme.widgetBaseHoverColor) : Theme.withAlpha(BlurService.hoverColor(Theme.widgetBaseHoverColor), 0)

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS

                        DankIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: itemRect.modelData.icon
                            size: Theme.iconSizeSmall
                            color: Theme.surfaceText
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: itemRect.modelData.label
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: itemArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runMenuAction(itemRect.modelData.action)
                    }
                }
            }
        }
    }
}
