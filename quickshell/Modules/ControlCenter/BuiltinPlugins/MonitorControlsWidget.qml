import QtQuick
import qs.Common
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

    ccDetailContent: Component {
        MonitorControlsDetail {}
    }
}
