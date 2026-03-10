package ddc

import (
	"fmt"
	"math"
)

// SetBrightnessPercent scales percent to the monitor's own brightness range, which is not always 0-100.
func (m *Manager) SetBrightnessPercent(deviceID string, percent int) error {
	cached, ok := m.capCache.Load(deviceID)
	if !ok {
		return fmt.Errorf("device not found: %s", deviceID)
	}
	for _, feat := range cached.Features {
		if feat.Code != VCPBrightness {
			continue
		}
		if feat.Max <= 0 {
			return fmt.Errorf("%s reported max brightness %d", deviceID, feat.Max)
		}
		return m.SetFeature(deviceID, VCPBrightness, rawFromPercent(percent, feat.Max))
	}
	return fmt.Errorf("%s has no brightness control", deviceID)
}

func rawFromPercent(percent, maxValue int) int {
	percent = min(max(percent, 0), 100)
	return int(math.Round(float64(percent*maxValue) / 100))
}

func PercentFromRaw(raw, maxValue int) int {
	if maxValue <= 0 {
		return 0
	}
	return min(int(math.Round(float64(raw*100)/float64(maxValue))), 100)
}
