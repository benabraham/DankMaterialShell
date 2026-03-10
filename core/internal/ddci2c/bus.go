package ddci2c

import (
	"errors"
	"fmt"
	"os"
	"sync"
	"syscall"
	"time"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/log"
	"golang.org/x/sys/unix"
)

// ddcutil's DEFAULT_FLOCK_POLL_MILLISEC and DEFAULT_FLOCK_MAX_WAIT_MILLISEC (src/base/parms.h).
const (
	busLockPoll = 100 * time.Millisecond
	busLockWait = 3 * time.Second
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

	fd, err := openBus(bus)
	if err != nil {
		return err
	}
	defer syscall.Close(fd)

	if err := setI2CAddr(fd, addr); err != nil {
		return fmt.Errorf("set i2c slave addr 0x%02x: %w", addr, err)
	}

	return fn(fd)
}

// Based on ddcutil's i2c_open_bus() cross-instance lock (src/base/flock.c): ddcutil, other dms
// processes and this one take turns on a bus.
func openBus(bus int) (int, error) {
	// Without O_CLOEXEC a process spawned mid-probe inherits the fd and the flock with it.
	fd, err := syscall.Open(fmt.Sprintf("/dev/i2c-%d", bus), syscall.O_RDWR|syscall.O_CLOEXEC, 0)
	if err != nil {
		return -1, fmt.Errorf("open i2c-%d: %w", bus, err)
	}
	deadline := time.Now().Add(busLockWait)
	for {
		err = unix.Flock(fd, unix.LOCK_EX|unix.LOCK_NB)
		if err == nil {
			return fd, nil
		}
		if !errors.Is(err, unix.EWOULDBLOCK) || time.Now().After(deadline) {
			syscall.Close(fd)
			return -1, fmt.Errorf("lock i2c-%d: %w", bus, err)
		}
		time.Sleep(busLockPoll)
	}
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
func (bm *BusManager) ProbeDevice(bus int, readEDID bool) (string, bool) {
	if IsIgnorableI2CBus(bus) {
		return "", false
	}

	busPath := fmt.Sprintf("/dev/i2c-%d", bus)
	if _, err := os.Stat(busPath); os.IsNotExist(err) {
		return "", false
	}

	err := bm.WithBus(bus, DDCCI_ADDR, func(fd int) error {
		if readEDID {
			edid, err := readBusEDID(fd)
			if err != nil {
				return err
			}
			if isLaptopEDID(edid) {
				return errors.New("laptop panel")
			}
			if err := setI2CAddr(fd, DDCCI_ADDR); err != nil {
				return err
			}
		}
		if !detectX37(fd) {
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
