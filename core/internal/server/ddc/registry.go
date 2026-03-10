package ddc

import (
	"fmt"
	"sort"
)

var KnownVCPCodes = []VCPCodeDef{
	{Code: 0x10, Name: "Brightness", Type: VCPTypeContinuous, Category: CategoryImage, Icon: "brightness_high"},
	{Code: 0x12, Name: "Contrast", Type: VCPTypeContinuous, Category: CategoryImage, Icon: "contrast"},
	{Code: 0x72, Name: "Gamma", Type: VCPTypeContinuous, Category: CategoryImage, Icon: "tonality"},
	{Code: 0x87, Name: "Sharpness", Type: VCPTypeContinuous, Category: CategoryImage, Icon: "deblur"},
	{Code: 0x62, Name: "Hardware Volume", Type: VCPTypeContinuous, Category: CategoryAudio, Icon: "volume_up"},
	{Code: 0x8D, Name: "Hardware Mute", Type: VCPTypeBoolean, Category: CategoryAudio, Icon: "volume_off"},
	{Code: 0x91, Name: "Bass", Type: VCPTypeContinuous, Category: CategoryAudio, Icon: "graphic_eq"},
	{Code: 0x93, Name: "Treble", Type: VCPTypeContinuous, Category: CategoryAudio, Icon: "graphic_eq"},
	{Code: 0xDC, Name: "Display Mode", Type: VCPTypeNonContinuous, Category: CategoryColor, Icon: "display_settings"},
	{Code: 0x8A, Name: "Color Saturation", Type: VCPTypeContinuous, Category: CategoryColor, Icon: "water_drop"},
	{Code: 0x14, Name: "Color Temperature", Type: VCPTypeNonContinuous, Category: CategoryColor, Icon: "thermostat"},
	{Code: 0x0C, Name: "Color Temperature", Type: VCPTypeContinuous, Category: CategoryColor, Icon: "thermostat"},
	{Code: 0x16, Name: "Red Gain", Type: VCPTypeContinuous, Category: CategoryColor, Icon: "palette"},
	{Code: 0x18, Name: "Green Gain", Type: VCPTypeContinuous, Category: CategoryColor, Icon: "palette"},
	{Code: 0x1A, Name: "Blue Gain", Type: VCPTypeContinuous, Category: CategoryColor, Icon: "palette"},
	{Code: 0x6C, Name: "Black Level Red", Type: VCPTypeContinuous, Category: CategoryColor, Icon: "brightness_low"},
	{Code: 0x6E, Name: "Black Level Green", Type: VCPTypeContinuous, Category: CategoryColor, Icon: "brightness_low"},
	{Code: 0x70, Name: "Black Level Blue", Type: VCPTypeContinuous, Category: CategoryColor, Icon: "brightness_low"},
	{Code: 0x4A, Name: "Saturation", Type: VCPTypeContinuous, Category: CategoryColor, Icon: "water_drop"},
	{Code: 0x86, Name: "Aspect Control", Type: VCPTypeNonContinuous, Category: CategoryDisplay, Icon: "aspect_ratio"},
	{Code: 0x60, Name: "Input Source", Type: VCPTypeNonContinuous, Category: CategoryDisplay, Icon: "input"},
	{Code: 0xCC, Name: "OSD Language", Type: VCPTypeNonContinuous, Category: CategoryDisplay, Icon: "language"},
	// ASUS-specific codes
	{Code: 0xEF, Name: "Shadow Boost", Type: VCPTypeNonContinuous, Category: CategoryImage, Icon: "shadow"},
	{Code: 0xF0, Name: "Blue Light Filter", Type: VCPTypeNonContinuous, Category: CategoryImage, Icon: "night_sight_max"},
	{Code: 0xEC, Name: "Crosshair", Type: VCPTypeNonContinuous, Category: CategoryGame, Icon: "my_location"},
	{Code: 0xF9, Name: "Dynamic Crosshair", Type: VCPTypeBoolean, Category: CategoryGame, Icon: "my_location"},
	{Code: 0xF5, Name: "Sniper Mode", Type: VCPTypeNonContinuous, Category: CategoryGame, Icon: "zoom_in"},
	{Code: 0xF6, Name: "FPS Counter", Type: VCPTypeNonContinuous, Category: CategoryGame, Icon: "speed"},
	{Code: 0xEE, Name: "Countdown Timer", Type: VCPTypeNonContinuous, Category: CategoryGame, Icon: "timer"},
	{Code: 0xEA, Name: "Power Indicator", Type: VCPTypeBoolean, Category: CategoryDisplay, Icon: "light_mode"},
	{Code: 0xE9, Name: "Key Lock", Type: VCPTypeBoolean, Category: CategoryDisplay, Icon: "lock"},
	{Code: 0xEB, Name: "Power Key Lock", Type: VCPTypeBoolean, Category: CategoryDisplay, Icon: "lock"},
	{Code: 0xF4, Name: "USB Hub Standby Power", Type: VCPTypeBoolean, Category: CategoryDisplay, Icon: "usb"},
}

var knownVCPCodeMap map[byte]VCPCodeDef

func init() {
	knownVCPCodeMap = make(map[byte]VCPCodeDef, len(KnownVCPCodes))
	for _, def := range KnownVCPCodes {
		knownVCPCodeMap[def.Code] = def
	}
}

func GetCodeDef(code byte) (VCPCodeDef, bool) {
	def, ok := knownVCPCodeMap[code]
	return def, ok
}

var InputSourceValues = map[int]string{
	0x01: "VGA-1",
	0x02: "VGA-2",
	0x03: "DVI-1",
	0x04: "DVI-2",
	0x05: "Composite-1",
	0x06: "Composite-2",
	0x07: "S-Video-1",
	0x08: "S-Video-2",
	0x09: "Tuner-1",
	0x0A: "Tuner-2",
	0x0B: "Tuner-3",
	0x0C: "Component-1",
	0x0D: "Component-2",
	0x0E: "Component-3",
	0x0F: "DisplayPort-1",
	0x10: "DisplayPort-2",
	0x11: "HDMI-1",
	0x12: "HDMI-2",
	0x53: "HDMI-3",
	0x54: "HDMI-4",
}

var ColorPresetValues = map[int]string{
	0x01: "sRGB",
	0x02: "Native",
	0x03: "4000K",
	0x04: "5000K",
	0x05: "6500K",
	0x06: "7500K",
	0x07: "8200K",
	0x08: "9300K",
	0x09: "10000K",
	0x0A: "11500K",
	0x0B: "User 1",
	0x0C: "User 2",
	0x0D: "User 3",
}

var PresetTemperatures = map[int]int{
	0x03: 4000,
	0x04: 5000,
	0x05: 6500,
	0x06: 7500,
	0x07: 8200,
	0x08: 9300,
	0x09: 10000,
	0x0A: 11500,
}

var DisplayModeValues = map[int]string{
	0x00: "Standard",
	0x01: "Productivity",
	0x02: "Multimedia",
	0x03: "Cinema",
	0x04: "User 1",
	0x05: "Game",
	0x06: "User 3",
	0x07: "Dynamic Contrast",
	0x08: "Sports",
	0x09: "Nature",
	0x0B: "Scenery",
	0x0D: "sRGB",
	0x0E: "User",
	0x0F: "Game",
	0x11: "Racing",
	0x12: "RTS/RPG",
	0x13: "FPS",
	0x14: "MOBA",
	0x20: "Racing 20",
}

var DisplayScalingValues = map[int]string{
	0x01: "1:1",
	0x02: "Full",
	0x03: "Max Vertical, No Distortion",
	0x04: "Max Horizontal, No Distortion",
	0x05: "Max Vertical, Distorted",
	0x06: "Max Horizontal, Distorted",
	0x07: "Linear Expansion",
	0x08: "Non-Linear Expansion",
	0x0B: "Equivalent",
	0x0D: "16:9 24\"",
	0x0E: "16:9 27\"",
	0x0F: "21:9 34\"",
}

var OSDLanguageValues = map[int]string{
	0x01: "Chinese (Traditional)",
	0x02: "English",
	0x03: "French",
	0x04: "German",
	0x05: "Italian",
	0x06: "Japanese",
	0x07: "Korean",
	0x08: "Portuguese",
	0x09: "Russian",
	0x0A: "Spanish",
	0x0B: "Swedish",
	0x0C: "Turkish",
	0x0D: "Chinese (Simplified)",
	0x0E: "Portuguese (Brazil)",
	0x0F: "Arabic",
	0x10: "Bulgarian",
	0x11: "Croatian",
	0x12: "Czech",
	0x13: "Danish",
	0x14: "Dutch",
	0x15: "Estonian",
	0x16: "Finnish",
	0x17: "Greek",
	0x18: "Hebrew",
	0x19: "Hindi",
	0x1A: "Hungarian",
	0x1B: "Latvian",
	0x1C: "Lithuanian",
	0x1D: "Norwegian",
	0x1E: "Polish",
	0x1F: "Romanian",
	0x20: "Serbian",
	0x21: "Slovak",
	0x22: "Slovenian",
	0x23: "Thai",
	0x24: "Ukrainian",
	0x25: "Vietnamese",
}

var ShadowBoostValues = map[int]string{
	0x00: "Off",
	0x01: "Level 1",
	0x02: "Level 2",
	0x03: "Level 3",
	0xFF: "Dynamic",
}

var BlueLightFilterValues = map[int]string{
	0x00: "Off",
	0x01: "Level 1",
	0x02: "Level 2",
	0x03: "Level 3",
	0x04: "Level 4",
}

var CrosshairValues = map[int]string{
	0x00: "Off",
	0x06: "Cross (Red)",
	0x07: "Circle (Red)",
	0x08: "Dot (Red)",
	0x09: "Cross (Green)",
	0x0A: "Circle (Green)",
	0x0B: "Dot (Green)",
}

var SniperModeValues = map[int]string{
	0x0000: "Off",
	0x0204: "1.2x (Red)",
	0x0304: "1.2x (Green)",
	0x0201: "1.5x (Red)",
	0x0301: "1.5x (Green)",
	0x0203: "2.0x (Red)",
	0x0303: "2.0x (Green)",
}

var FPSCounterValues = map[int]string{
	0x00: "Off",
	0x01: "Number",
	0x02: "Bar",
}

var CountdownTimerValues = map[int]string{
	0x00: "Off",
	0x1E: "30 min",
	0x28: "40 min",
	0x32: "50 min",
	0x3C: "60 min",
	0x5A: "90 min",
}

func GetPermittedValueLabels(code byte, rawValues []byte) []ValueLabel {
	var labelMap map[int]string

	switch code {
	case 0x60:
		labelMap = InputSourceValues
	case 0x14:
		labelMap = ColorPresetValues
	case 0x86:
		labelMap = DisplayScalingValues
	case 0xCC:
		labelMap = OSDLanguageValues
	case 0xDC:
		labelMap = DisplayModeValues
	case 0xEF:
		labelMap = ShadowBoostValues
	case 0xF0:
		labelMap = BlueLightFilterValues
	case 0xEC:
		labelMap = CrosshairValues
	case 0xF5:
		labelMap = SniperModeValues
	case 0xF6:
		labelMap = FPSCounterValues
	case 0xEE:
		labelMap = CountdownTimerValues
	default:
		labels := make([]ValueLabel, len(rawValues))
		for i, v := range rawValues {
			labels[i] = ValueLabel{Value: int(v), Label: fmt.Sprintf("0x%02X", v)}
		}
		return labels
	}

	if len(rawValues) > 0 {
		labels := make([]ValueLabel, 0, len(rawValues))
		for _, v := range rawValues {
			label, ok := labelMap[int(v)]
			if !ok {
				label = fmt.Sprintf("0x%02X", v)
			}
			labels = append(labels, ValueLabel{Value: int(v), Label: label})
		}
		return labels
	}

	labels := make([]ValueLabel, 0, len(labelMap))
	for val, label := range labelMap {
		labels = append(labels, ValueLabel{Value: val, Label: label})
	}
	sort.Slice(labels, func(i, j int) bool { return labels[i].Value < labels[j].Value })
	return labels
}
