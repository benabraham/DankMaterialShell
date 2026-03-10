import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    Ref {
        service: DDCService
    }

    ccWidgetIcon: DDCService.available ? "display_settings" : "desktop_access_disabled"
    ccWidgetPrimaryText: I18n.tr("DDC/CI")
    ccWidgetSecondaryText: {
        const count = DDCService.devices.length;
        if (DDCService.scanning && count === 0)
            return I18n.tr("Scanning...");
        if (count === 0)
            return I18n.tr("No monitors");
        if (count === 1)
            return I18n.tr("1 monitor");
        return count + " " + I18n.tr("monitors");
    }
    ccWidgetIsActive: DDCService.available && DDCService.devices.length > 0
    ccWidgetIsToggle: false

    readonly property var presetActions: {
        DDCService.stateVersion;
        DDCService.lastAppliedPresetId;
        return DDCService.presets.map(preset => ({
                    text: preset.name,
                    icon: preset.icon || "instant_mix",
                    active: DDCService.presetStatus(preset) === "active",
                    enabled: DDCService.applyingPresetId === "",
                    trigger: () => DDCService.applyPreset(preset)
                }));
    }
    ccDetailHeight: CcMetrics.detailHeightMonitorControls + (DDCService.presets.length > 3 ? CcMetrics.detailHeightPresetRow * 2 : DDCService.presets.length > 0 ? CcMetrics.detailHeightPresetRow : 0)

    ccDetailContent: Component {
        MonitorControlsDetail {}
    }

    ccExpandedContent: Component {
        CcTileActions {
            actions: root.presetActions
        }
    }
}
