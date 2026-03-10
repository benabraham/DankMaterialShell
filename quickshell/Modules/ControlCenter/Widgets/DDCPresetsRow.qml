import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root

    Ref {
        service: DDCService
    }

    DankIcon {
        id: leadIcon
        name: "instant_mix"
        size: Theme.iconSize - 4
        color: Theme.surfaceText
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
    }

    StyledText {
        visible: DDCService.presets.length === 0
        anchors.left: leadIcon.right
        anchors.leftMargin: Theme.spacingM
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: DDCService.available ? I18n.tr("No presets configured") : I18n.tr("DDC/CI not available")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        elide: Text.ElideRight
    }

    Flickable {
        visible: DDCService.presets.length > 0
        anchors.left: leadIcon.right
        anchors.leftMargin: Theme.spacingM
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        height: 36
        contentWidth: chipsRow.width
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Row {
            id: chipsRow
            height: parent.height
            spacing: Theme.spacingS

            Repeater {
                model: DDCService.presets

                DDCPresetChip {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    preset: modelData
                }
            }
        }
    }
}
