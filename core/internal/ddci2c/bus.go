package ddci2c

import (
	"fmt"
	"os"
	"sync"
	"syscall"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/log"
)

// BusManager provides thread-safe access to I2C buses with per-bus mutexes.
type BusManager struct {
	mutexes sync.Map // map[int]*sync.Mutex — per-bus locks
}

func NewBusManager() *BusManager {
	return &BusManager{}
}

func (bm *BusManager) getBusMutex(bus int) *sync.Mutex {
	val, _ := bm.mutexes.LoadOrStore(bus, &sync.Mutex{})
	return val.(*sync.Mutex)
}

// WithBus acquires the per-bus mutex, opens the I2C device, sets the slave
// address, calls fn with the file descriptor, then cleans up.
// This is the core primitive — all I2C access goes through it.
func (bm *BusManager) WithBus(bus, addr int, fn func(fd int) error) error {
	mu := bm.getBusMutex(bus)
	mu.Lock()
	defer mu.Unlock()

	busPath := fmt.Sprintf("/dev/i2c-%d", bus)
	fd, err := syscall.Open(busPath, syscall.O_RDWR, 0)
	if err != nil {
		return fmt.Errorf("open %s: %w", busPath, err)
	}
	defer syscall.Close(fd)

	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), I2C_SLAVE, uintptr(addr)); errno != 0 {
		return fmt.Errorf("set i2c slave addr 0x%02x: %w", addr, errno)
	}

	return fn(fd)
}

// GetVCPFeature reads a VCP feature value from a DDC/CI device, thread-safe.
func (bm *BusManager) GetVCPFeature(bus, addr int, vcp byte) (*VCPReply, error) {
	var reply *VCPReply
	err := bm.WithBus(bus, addr, func(fd int) error {
		var e error
		reply, e = GetVCPFeatureRaw(fd, vcp)
		return e
	})
	return reply, err
}

// SetVCPFeature writes a VCP feature value to a DDC/CI device, thread-safe.
func (bm *BusManager) SetVCPFeature(bus, addr int, vcp byte, value int) error {
	return bm.WithBus(bus, addr, func(fd int) error {
		return SetVCPFeatureRaw(fd, vcp, value)
	})
}

// GetAndSetVCPFeature performs an atomic get-then-set in a single bus session.
// One fd session, one mutex hold. Returns the reply from the get operation.
func (bm *BusManager) GetAndSetVCPFeature(bus, addr int, getVcp, setVcp byte, setValue int) (*VCPReply, error) {
	var reply *VCPReply
	err := bm.WithBus(bus, addr, func(fd int) error {
		var e error
		reply, e = GetVCPFeatureRaw(fd, getVcp)
		if e != nil {
			return e
		}
		return SetVCPFeatureRaw(fd, setVcp, setValue)
	})
	return reply, err
}

// GetCapabilityString reads the DDC capabilities string from a device.
func (bm *BusManager) GetCapabilityString(bus, addr int) (string, error) {
	var caps string
	err := bm.WithBus(bus, addr, func(fd int) error {
		var e error
		caps, e = ReadCapabilityStringRaw(fd)
		return e
	})
	return caps, err
}

// ProbeDevice tests if an I2C bus has a DDC-capable device.
// Returns the device name and whether the device was found.
func (bm *BusManager) ProbeDevice(bus int) (string, bool) {
	if IsIgnorableI2CBus(bus) {
		return "", false
	}

	busPath := fmt.Sprintf("/dev/i2c-%d", bus)
	if _, err := os.Stat(busPath); os.IsNotExist(err) {
		return "", false
	}

	err := bm.WithBus(bus, DDCCI_ADDR, func(fd int) error {
		dummy := make([]byte, 32)
		syscall.Read(fd, dummy) //nolint:errcheck

		writebuf := []byte{0x00}
		n, err := syscall.Write(fd, writebuf)
		if err == nil && n == len(writebuf) {
			return nil
		}

		readbuf := make([]byte, 4)
		n, err = syscall.Read(fd, readbuf)
		if err != nil || n == 0 {
			return fmt.Errorf("x37 unresponsive")
		}
		return nil
	})

	if err != nil {
		return "", false
	}

	name := GetDDCName(bus)
	log.Debugf("found DDC device on i2c-%d", bus)
	return name, true
}

// GetDDCName reads the DDC device name from sysfs.
func GetDDCName(bus int) string {
	sysfsPath := fmt.Sprintf("/sys/class/i2c-adapter/i2c-%d/name", bus)
	data, err := os.ReadFile(sysfsPath)
	if err != nil {
		return fmt.Sprintf("I2C-%d", bus)
	}

	name := string(data)
	// Trim whitespace manually to avoid importing strings just for this
	for len(name) > 0 && (name[len(name)-1] == '\n' || name[len(name)-1] == '\r' || name[len(name)-1] == ' ' || name[len(name)-1] == '\t') {
		name = name[:len(name)-1]
	}
	if name == "" {
		name = fmt.Sprintf("I2C-%d", bus)
	}

	return name
}
