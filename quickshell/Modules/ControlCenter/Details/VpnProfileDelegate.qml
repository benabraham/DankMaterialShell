import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.Services
import qs.DCommon.Widgets

CcListRow {
    id: root

    required property var profile
    property bool isExpanded: false
    property bool showsEditButton: false
    readonly property bool isTransient: !!profile?.transient
    readonly property bool canExpand: profile?.canExpand !== false
    readonly property bool canDelete: profile?.canDelete !== false
    // Plugin VPNs keep the credentials panel: the editor only covers their General and IP settings.
    readonly property bool editorReplacesPanel: showsEditButton && !isTransient && profile?.type === "wireguard"

    signal toggleExpand
    signal deleteRequested
    signal editRequested

    readonly property bool isActive: DMSNetworkService.vpnStateForUuid(profile?.uuid) === "activated"
    readonly property bool isConnecting: DMSNetworkService.isVpnConnectingUuid(profile?.uuid)
    readonly property bool isWaitingLogin: DMSNetworkService.isVpnLoginWaitingUuid(profile?.uuid)
    readonly property var login: isWaitingLogin ? DMSNetworkService.vpnLogin : null
    property real now: Date.now()
    readonly property int loginSecondsLeft: login ? Math.max(0, Math.ceil((login.deadline - now) / 1000)) : 0

    function formatSecondsLeft(seconds) {
        const minutes = Math.floor(seconds / 60);
        const rest = seconds % 60;
        return minutes + ":" + (rest < 10 ? "0" : "") + rest;
    }

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.isWaitingLogin
        onTriggered: root.now = Date.now()
    }
    readonly property bool hasError: !isConnecting && DMSNetworkService.vpnError !== "" && DMSNetworkService.vpnErrorUuid === (profile?.uuid ?? "")
    readonly property var configData: (!isTransient && isExpanded) ? VPNService.editConfig : null
    readonly property var configFields: buildConfigFields()

    function buildConfigFields() {
        if (!configData)
            return [];
        const fields = [];
        const data = configData.data || {};
        if (data.remote)
            fields.push({
                "label": I18n.tr("Server"),
                "value": data.remote
            });
        if (configData.username || data.username)
            fields.push({
                "label": I18n.tr("Username"),
                "value": configData.username || data.username
            });
        if (data.cipher)
            fields.push({
                "label": I18n.tr("Cipher"),
                "value": data.cipher
            });
        if (data.auth)
            fields.push({
                "label": I18n.tr("Auth"),
                "value": data.auth
            });
        if (data["proto-tcp"] === "yes" || data["proto-tcp"] === "no")
            fields.push({
                "label": I18n.tr("Protocol"),
                "value": data["proto-tcp"] === "yes" ? "TCP" : "UDP"
            });
        if (data["tunnel-mtu"])
            fields.push({
                "label": "MTU",
                "value": data["tunnel-mtu"]
            });
        if (data["connection-type"])
            fields.push({
                "label": I18n.tr("Auth type"),
                "value": data["connection-type"]
            });
        return fields;
    }

    iconName: isConnecting ? "" : (isActive ? "vpn_lock" : (hasError ? "error" : "vpn_key_off"))
    iconColor: hasError ? Theme.error : contentColor
    active: isActive
    title: profile?.name ?? ""
    subtitle: isWaitingLogin ? I18n.tr("Waiting for login, %1 left", "vpn row subtitle while a browser login waits, %1 is m:ss").arg(formatSecondsLeft(loginSecondsLeft)) : isConnecting ? I18n.tr("Connecting...") : (hasError ? DMSNetworkService.vpnError : VPNService.getVpnTypeFromProfile(profile))
    subtitleColor: isConnecting ? Theme.warning : (hasError ? Theme.error : Theme.surfaceVariantText)
    enabled: !(DMSNetworkService.isBusy && !isConnecting)
    clickable: true
    onClicked: DMSNetworkService.toggle(profile.uuid)

    leading: DSpinner {
        size: Theme.iconSizeMedium
        strokeWidth: CcMetrics.spinnerStroke
        color: Theme.warning
        visible: root.isConnecting
        running: visible
    }

    DActionButton {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.isWaitingLogin && !!root.login?.url
        buttonSize: Theme.buttonHeightXS
        iconSize: Theme.iconSizeMedium
        iconName: "open_in_browser"
        Accessible.name: I18n.tr("Open the login page again")
        tooltipText: I18n.tr("Open the login page again")
        iconColor: root.contentColor
        onClicked: DMSNetworkService.reopenVpnLogin()
    }

    DActionButton {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.isWaitingLogin && !!root.login?.canExtend
        buttonSize: Theme.buttonHeightXS
        iconSize: Theme.iconSizeMedium
        iconName: "more_time"
        Accessible.name: I18n.tr("Wait 5 more minutes")
        tooltipText: I18n.tr("Wait 5 more minutes")
        iconColor: root.contentColor
        onClicked: DMSNetworkService.extendVpnLogin()
    }

    DActionButton {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.isWaitingLogin
        buttonSize: Theme.buttonHeightXS
        iconSize: Theme.iconSizeMedium
        iconName: "close"
        Accessible.name: I18n.tr("Cancel login")
        tooltipText: I18n.tr("Cancel login")
        iconColor: root.contentColor
        onClicked: DMSNetworkService.cancelVpnLogin()
    }

    DActionButton {
        anchors.verticalCenter: parent.verticalCenter
        visible: (root.isActive || root.isConnecting) && !root.isWaitingLogin
        buttonSize: Theme.buttonHeightXS
        iconSize: Theme.iconSizeMedium
        iconName: "link_off"
        Accessible.name: I18n.tr("Disconnect")
        tooltipText: I18n.tr("Disconnect")
        iconColor: root.contentColor
        enabled: !DMSNetworkService.isBusy
        onClicked: DMSNetworkService.toggle(root.profile.uuid)
    }

    DActionButton {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.showsEditButton && !root.isTransient
        buttonSize: Theme.buttonHeightXS
        iconSize: Theme.iconSizeMedium
        iconName: "edit"
        tooltipText: I18n.tr("Edit")
        Accessible.name: I18n.tr("Edit")
        iconColor: root.contentColor
        onClicked: root.editRequested()
    }

    DActionButton {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.canExpand && !root.editorReplacesPanel
        buttonSize: Theme.buttonHeightXS
        iconSize: Theme.iconSizeMedium
        iconName: root.isExpanded ? "expand_less" : "expand_more"
        Accessible.name: root.isExpanded ? I18n.tr("Collapse") : I18n.tr("Expand")
        iconColor: Theme.surfaceText
        onClicked: root.toggleExpand()
    }

    DActionButton {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.canDelete
        buttonSize: Theme.buttonHeightXS
        iconSize: Theme.iconSizeMedium
        iconName: "delete"
        iconColor: Theme.error
        Accessible.name: I18n.tr("Delete")
        onClicked: root.deleteRequested()
    }

    body: Column {
        width: parent.width
        spacing: Theme.spacingS
        visible: root.isExpanded

        DSpinner {
            anchors.horizontalCenter: parent.horizontalCenter
            size: Theme.iconSizeMedium
            strokeWidth: CcMetrics.spinnerStroke
            visible: VPNService.configLoading
            running: visible
        }

        Flow {
            width: parent.width
            spacing: Theme.spacingXS
            visible: !root.isTransient && !VPNService.configLoading && root.configData !== null

            Repeater {
                model: root.configFields

                DDetailChip {
                    required property var modelData

                    label: modelData.label
                    value: modelData.value
                    color: Theme.chipSurface
                    border.width: 0
                }
            }
        }

        DToggle {
            width: parent.width
            text: I18n.tr("Autoconnect")
            checked: root.configData ? (root.configData.autoconnect || false) : false
            visible: !VPNService.configLoading && root.configData !== null
            onToggled: checked => VPNService.updateConfig(root.profile.uuid, {
                    autoconnect: checked
                })
        }

        Column {
            width: parent.width
            spacing: Theme.spacingXS
            visible: !root.isTransient && !VPNService.configLoading && root.profile?.type !== "wireguard" && (root.hasError || !root.profile?.pluginLogin)

            StyledText {
                text: root.hasError ? DMSNetworkService.vpnError : I18n.tr("Credentials", "noun, label above vpn username and password fields")
                font.pixelSize: Theme.fontSizeSmall
                color: root.hasError ? Theme.error : Theme.surfaceVariantText
            }

            DTextField {
                id: usernameField
                visible: !root.profile?.pluginLogin
                width: parent.width
                placeholderText: I18n.tr("Username")
                text: (root.configData && (root.configData.username || (root.configData.data && root.configData.data.username))) || ""
            }

            DTextField {
                id: passwordField
                visible: !root.profile?.pluginLogin
                width: parent.width
                placeholderText: I18n.tr("Password")
                echoMode: TextInput.Password
                showPasswordToggle: true
                normalBorderColor: root.hasError ? Theme.error : Theme.outlineMedium
            }

            DButton {
                text: I18n.tr("Save credentials")
                visible: !root.profile?.pluginLogin
                buttonHeight: Theme.buttonHeightXS
                enabled: passwordField.text.length > 0
                onClicked: {
                    VPNService.setCredentials(root.profile.uuid, usernameField.text, passwordField.text, true);
                    passwordField.text = "";
                }
            }
        }
    }
}
