package ddc

import (
	"fmt"
	"os"
	"sync"
	"time"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/ddci2c"
	"github.com/AvengeMedia/DankMaterialShell/core/internal/log"
	"github.com/AvengeMedia/DankMaterialShell/core/pkg/syncmap"
)

type pendingSet struct {
	value int
}

type Manager struct {
	busManager *ddci2c.BusManager

	capCache  syncmap.Map[string, *DeviceCapabilities]
	scanMutex sync.Mutex
	lastScan  time.Time

	stateMutex sync.RWMutex
	state      State

	subscribers syncmap.Map[string, chan State]

	debounceMutex   sync.Mutex
	debounceTimers  map[string]*time.Timer
	debouncePending map[string]pendingSet

	stopChan    chan struct{}
	retryActive bool

	pollMutex    sync.Mutex
	pollTicker   *time.Ticker
	pollStopChan chan struct{}
}

func NewManager(bm *ddci2c.BusManager) (*Manager, error) {
	m := &Manager{
		busManager:      bm,
		debounceTimers:  make(map[string]*time.Timer),
		debouncePending: make(map[string]pendingSet),
		stopChan:        make(chan struct{}),
	}

	if err := m.ScanDevices(); err != nil {
		log.Warnf("DDC initial scan: %v", err)
	}

	return m, nil
}

func (m *Manager) StartRetryScans() {
	go func() {
		delays := []time.Duration{2 * time.Second, 5 * time.Second, 10 * time.Second, 20 * time.Second}

		m.retryActive = true
		m.stateMutex.Lock()
		m.state.Scanning = true
		m.stateMutex.Unlock()
		m.NotifySubscribers()

		prevDeviceCount := len(m.GetState().Devices)

		for _, delay := range delays {
			select {
			case <-time.After(delay):
			case <-m.stopChan:
				return
			}

			if err := m.ScanDevices(); err != nil {
				log.Warnf("DDC retry scan: %v", err)
			}

			currentCount := len(m.GetState().Devices)
			if currentCount > prevDeviceCount {
				log.Infof("DDC retry scan found %d new device(s)", currentCount-prevDeviceCount)
				prevDeviceCount = currentCount
			}
		}

		m.retryActive = false
		m.stateMutex.Lock()
		m.state.Scanning = false
		m.stateMutex.Unlock()
		m.NotifySubscribers()
	}()
}

func (m *Manager) ScanDevices() error {
	m.scanMutex.Lock()
	defer m.scanMutex.Unlock()

	if !m.retryActive {
		m.stateMutex.Lock()
		m.state.Scanning = true
		m.stateMutex.Unlock()
		m.NotifySubscribers()
	}

	devices := make([]DeviceCapabilities, 0)

	for i := 0; i < 32; i++ {
		busPath := fmt.Sprintf("/dev/i2c-%d", i)
		if _, err := os.Stat(busPath); os.IsNotExist(err) {
			continue
		}

		if ddci2c.IsIgnorableI2CBus(i) {
			continue
		}

		name, ok := m.busManager.ProbeDevice(i)
		if !ok {
			continue
		}

		deviceID := fmt.Sprintf("ddc:i2c-%d", i)

		devCaps := DeviceCapabilities{
			DeviceID: deviceID,
			Bus:      i,
			Name:     name,
		}

		// Try reading capabilities string first
		var parsedCaps *ddci2c.ParsedCapabilities
		capsStr, err := m.busManager.GetCapabilityString(i, ddci2c.DDCCI_ADDR)
		if err == nil && capsStr != "" {
			parsedCaps, err = ddci2c.ParseCapabilities(capsStr)
			if err != nil {
				log.Debugf("DDC caps parse error for i2c-%d: %v", i, err)
				parsedCaps = nil
			} else {
				devCaps.Model = parsedCaps.Model
			}
		}

		features := m.probeFeatures(i, parsedCaps)
		devCaps.Features = features

		// Check which factory reset commands are available
		for resetType, code := range resetCodes {
			if parsedCaps == nil || parsedCaps.HasVCPCode(code) {
				devCaps.SupportedResets = append(devCaps.SupportedResets, resetType)
			}
		}

		if len(features) > 0 {
			devices = append(devices, devCaps)
			m.capCache.Store(deviceID, &devCaps)
			log.Infof("DDC device %s (%s): %d features", deviceID, name, len(features))
		}
	}

	m.lastScan = time.Now()

	m.stateMutex.Lock()
	m.state = State{
		Devices:  devices,
		Scanning: m.retryActive,
	}
	m.stateMutex.Unlock()

	m.NotifySubscribers()

	return nil
}

func (m *Manager) probeFeatures(bus int, caps *ddci2c.ParsedCapabilities) []FeatureInfo {
	var features []FeatureInfo

	for _, codeDef := range KnownVCPCodes {
		reply, err := m.busManager.GetVCPFeature(bus, ddci2c.DDCCI_ADDR, codeDef.Code)
		if err != nil {
			log.Debugf("DDC i2c-%d: VCP 0x%02X not supported: %v", bus, codeDef.Code, err)
			continue
		}

		feature := FeatureInfo{
			Code:     codeDef.Code,
			Name:     codeDef.Name,
			Type:     codeDef.Type,
			Category: codeDef.Category,
			Icon:     codeDef.Icon,
			Current:  reply.Current,
			Max:      reply.Max,
		}

		// Color Temperature (0x0C): read increment from VCP 0x0B
		if codeDef.Code == 0x0C {
			if incReply, err := m.busManager.GetVCPFeature(bus, ddci2c.DDCCI_ADDR, 0x0B); err == nil && incReply.Current > 0 {
				feature.DisplayMultiply = incReply.Current
				feature.DisplayOffset = 3000
				feature.Unit = "K"
			}
		}

		// For non-continuous types, get permitted values
		if codeDef.Type == VCPTypeNonContinuous {
			var rawValues []byte
			if caps != nil {
				if entry, ok := caps.GetVCPEntry(codeDef.Code); ok {
					rawValues = entry.Values
				}
			}
			feature.PermittedValues = GetPermittedValueLabels(codeDef.Code, rawValues)
		}

		features = append(features, feature)
	}

	// Derive color temperature slider bounds from color presets
	var colorTempIdx, colorPresetIdx = -1, -1
	for i, f := range features {
		switch f.Code {
		case 0x0C:
			colorTempIdx = i
		case 0x14:
			colorPresetIdx = i
		}
	}
	if colorTempIdx >= 0 && colorPresetIdx >= 0 && features[colorTempIdx].DisplayMultiply > 0 {
		increment := features[colorTempIdx].DisplayMultiply
		minK, maxK := 0, 0
		for _, pv := range features[colorPresetIdx].PermittedValues {
			if k, ok := PresetTemperatures[pv.Value]; ok {
				if minK == 0 || k < minK {
					minK = k
				}
				if k > maxK {
					maxK = k
				}
			}
		}
		if minK > 0 && maxK > 0 {
			minStep := (minK - 3000) / increment
			maxStep := (maxK - 3000) / increment
			if minStep < 0 {
				minStep = 0
			}
			if maxStep > features[colorTempIdx].Max {
				maxStep = features[colorTempIdx].Max
			}
			features[colorTempIdx].Min = minStep
			features[colorTempIdx].Max = maxStep
		}
	}

	return features
}

func (m *Manager) GetState() State {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	return m.state
}

func (m *Manager) GetFeature(deviceID string, code byte) (*FeatureInfo, error) {
	cached, ok := m.capCache.Load(deviceID)
	if !ok {
		return nil, fmt.Errorf("device not found: %s", deviceID)
	}

	reply, err := m.busManager.GetVCPFeature(cached.Bus, ddci2c.DDCCI_ADDR, code)
	if err != nil {
		return nil, fmt.Errorf("get vcp 0x%02X: %w", code, err)
	}

	codeDef, ok := GetCodeDef(code)
	if !ok {
		return nil, fmt.Errorf("unknown vcp code: 0x%02X", code)
	}

	feature := &FeatureInfo{
		Code:     code,
		Name:     codeDef.Name,
		Type:     codeDef.Type,
		Category: codeDef.Category,
		Icon:     codeDef.Icon,
		Current:  reply.Current,
		Max:      reply.Max,
	}

	// Color Temperature: copy display metadata from cached feature
	if code == 0x0C {
		for _, f := range cached.Features {
			if f.Code == 0x0C {
				feature.Min = f.Min
				feature.DisplayMultiply = f.DisplayMultiply
				feature.DisplayOffset = f.DisplayOffset
				feature.Unit = f.Unit
				break
			}
		}
	}

	return feature, nil
}

var resetCodes = map[string]byte{
	"all":       0x04,
	"luminance": 0x05,
	"geometry":  0x06,
	"color":     0x08,
}

func (m *Manager) ResetDefaults(deviceID string, resetType string) error {
	cached, ok := m.capCache.Load(deviceID)
	if !ok {
		return fmt.Errorf("device not found: %s", deviceID)
	}

	code, ok := resetCodes[resetType]
	if !ok {
		return fmt.Errorf("unknown reset type: %s", resetType)
	}

	if err := m.busManager.SetVCPFeature(cached.Bus, ddci2c.DDCCI_ADDR, code, 0x01); err != nil {
		return fmt.Errorf("reset %s: %w", resetType, err)
	}

	log.Infof("DDC reset %s on %s (VCP 0x%02X)", resetType, deviceID, code)

	// Re-read features to get updated values
	go func() {
		time.Sleep(500 * time.Millisecond)
		m.ScanDevices() //nolint:errcheck // fire-and-forget rescan after reset
	}()

	return nil
}

func (m *Manager) SetFeature(deviceID string, code byte, value int) error {
	cached, ok := m.capCache.Load(deviceID)
	if !ok {
		return fmt.Errorf("device not found: %s", deviceID)
	}

	codeDef, ok := GetCodeDef(code)
	if !ok {
		return fmt.Errorf("unknown vcp code: 0x%02X", code)
	}

	// Clamp continuous values to valid range
	if codeDef.Type == VCPTypeContinuous {
		if value < 0 {
			value = 0
		}
		for _, feat := range cached.Features {
			if feat.Code == code && feat.Max > 0 && value > feat.Max {
				value = feat.Max
				break
			}
		}
		return m.setFeatureDebounced(cached, code, value)
	}

	// Non-continuous and boolean fire immediately
	return m.setFeatureImmediate(cached, code, value)
}

func (m *Manager) setFeatureDebounced(dev *DeviceCapabilities, code byte, value int) error {
	key := fmt.Sprintf("%s:0x%02X", dev.DeviceID, code)

	m.debounceMutex.Lock()
	m.debouncePending[key] = pendingSet{value: value}

	if timer, exists := m.debounceTimers[key]; exists {
		timer.Reset(200 * time.Millisecond)
	} else {
		m.debounceTimers[key] = time.AfterFunc(200*time.Millisecond, func() {
			m.debounceMutex.Lock()
			pending, exists := m.debouncePending[key]
			if exists {
				delete(m.debouncePending, key)
			}
			delete(m.debounceTimers, key)
			m.debounceMutex.Unlock()

			if !exists {
				return
			}

			if err := m.setFeatureImmediate(dev, code, pending.value); err != nil {
				log.Debugf("DDC debounced set failed %s 0x%02X: %v", dev.DeviceID, code, err)
			}
		})
	}
	m.debounceMutex.Unlock()

	// Optimistic update in state
	m.updateFeatureInState(dev.DeviceID, code, value)

	return nil
}

func (m *Manager) setFeatureImmediate(dev *DeviceCapabilities, code byte, value int) error {
	if err := m.busManager.SetVCPFeature(dev.Bus, ddci2c.DDCCI_ADDR, code, value); err != nil {
		return fmt.Errorf("set vcp 0x%02X to %d: %w", code, value, err)
	}

	log.Debugf("DDC set %s VCP 0x%02X to %d", dev.DeviceID, code, value)

	m.updateFeatureInState(dev.DeviceID, code, value)
	m.NotifySubscribers()
	m.resetPollTicker()

	// Re-read non-continuous features to catch linked changes
	// (e.g. changing Display Mode may update Color Preset)
	go m.refreshLinkedFeatures(dev, code)

	return nil
}

// Features that may change as side effects of other settings
// (e.g. changing Display Mode updates Color Preset)
var linkedFeatureCodes = []byte{0x14, 0xDC}

func (m *Manager) refreshLinkedFeatures(dev *DeviceCapabilities, writtenCode byte) {
	time.Sleep(50 * time.Millisecond)

	changed := false
	for _, code := range linkedFeatureCodes {
		if code == writtenCode {
			continue
		}

		m.stateMutex.RLock()
		var currentValue int
		var found bool
		for _, d := range m.state.Devices {
			if d.DeviceID != dev.DeviceID {
				continue
			}
			for _, f := range d.Features {
				if f.Code == code {
					currentValue = f.Current
					found = true
					break
				}
			}
			break
		}
		m.stateMutex.RUnlock()

		if !found {
			continue
		}

		reply, err := m.busManager.GetVCPFeature(dev.Bus, ddci2c.DDCCI_ADDR, code)
		if err != nil {
			continue
		}
		if reply.Current != currentValue {
			m.updateFeatureInState(dev.DeviceID, code, reply.Current)
			changed = true
		}
	}

	if changed {
		m.NotifySubscribers()
	}
	m.resetPollTicker()
}

func (m *Manager) resetPollTicker() {
	m.pollMutex.Lock()
	if m.pollTicker != nil {
		m.pollTicker.Reset(5 * time.Second)
	}
	m.pollMutex.Unlock()
}

func (m *Manager) updateFeatureInState(deviceID string, code byte, value int) {
	m.stateMutex.Lock()
	defer m.stateMutex.Unlock()

	for i, dev := range m.state.Devices {
		if dev.DeviceID != deviceID {
			continue
		}
		for j, feat := range dev.Features {
			if feat.Code == code {
				m.state.Devices[i].Features[j].Current = value
				return
			}
		}
		return
	}
}

func (m *Manager) Subscribe(id string) chan State {
	ch := make(chan State, 16)
	m.subscribers.Store(id, ch)
	m.checkStartPolling()
	return ch
}

func (m *Manager) Unsubscribe(id string) {
	if val, ok := m.subscribers.LoadAndDelete(id); ok {
		close(val)
	}
	m.checkStopPolling()
}

func (m *Manager) NotifySubscribers() {
	m.stateMutex.RLock()
	state := m.state
	m.stateMutex.RUnlock()

	m.subscribers.Range(func(key string, ch chan State) bool {
		select {
		case ch <- state:
		default:
		}
		return true
	})
}

func (m *Manager) hasSubscribers() bool {
	has := false
	m.subscribers.Range(func(_ string, _ chan State) bool {
		has = true
		return false
	})
	return has
}

func (m *Manager) checkStartPolling() {
	m.pollMutex.Lock()
	defer m.pollMutex.Unlock()

	if m.pollTicker != nil {
		return
	}
	if !m.hasSubscribers() {
		return
	}

	m.pollTicker = time.NewTicker(5 * time.Second)
	m.pollStopChan = make(chan struct{})
	go m.pollLoop()
}

func (m *Manager) checkStopPolling() {
	m.pollMutex.Lock()
	defer m.pollMutex.Unlock()

	if m.pollTicker == nil {
		return
	}
	if m.hasSubscribers() {
		return
	}

	m.pollTicker.Stop()
	m.pollTicker = nil
	close(m.pollStopChan)
}

func (m *Manager) pollLoop() {
	for {
		select {
		case <-m.pollTicker.C:
			m.pollValues()
		case <-m.pollStopChan:
			return
		case <-m.stopChan:
			return
		}
	}
}

func (m *Manager) pollValues() {
	// Skip if debounced writes are pending
	m.debounceMutex.Lock()
	hasPending := len(m.debouncePending) > 0
	m.debounceMutex.Unlock()
	if hasPending {
		return
	}

	m.stateMutex.RLock()
	devices := m.state.Devices
	m.stateMutex.RUnlock()

	changed := false

	for _, dev := range devices {
		for _, feat := range dev.Features {
			reply, err := m.busManager.GetVCPFeature(dev.Bus, ddci2c.DDCCI_ADDR, feat.Code)
			if err != nil {
				continue
			}

			if reply.Current != feat.Current {
				m.updateFeatureInState(dev.DeviceID, feat.Code, reply.Current)
				changed = true
			}
		}
	}

	if changed {
		m.NotifySubscribers()
	}
}

func (m *Manager) Close() {
	close(m.stopChan)

	m.pollMutex.Lock()
	if m.pollTicker != nil {
		m.pollTicker.Stop()
		m.pollTicker = nil
		close(m.pollStopChan)
	}
	m.pollMutex.Unlock()

	m.subscribers.Range(func(key string, ch chan State) bool {
		close(ch)
		m.subscribers.Delete(key)
		return true
	})
}
