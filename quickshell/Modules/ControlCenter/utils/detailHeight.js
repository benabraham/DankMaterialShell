function detailHeightForSection(section, maxHeight, pluginInstance, ddcPresetCount) {
    if (!section)
        return 0;
    if (section === "wifi" || section === "bluetooth"
            || section === "builtin_vpn" || section === "builtin_tailscale")
        return Math.min(350, maxHeight);
    if (section.startsWith("brightnessSlider_"))
        return Math.min(400, maxHeight);
    if (section === "builtin_monitorControls") {
        const presetExtra = ddcPresetCount > 0 ? (ddcPresetCount > 3 ? 96 : 48) : 0;
        return Math.min(500 + presetExtra, maxHeight);
    }
    if (section.startsWith("plugin_")) {
        const h = pluginInstance ? pluginInstance.ccDetailHeight : 0;
        return Math.min(h > 0 ? h : 250, maxHeight);
    }
    return Math.min(250, maxHeight);
}
