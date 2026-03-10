package ddci2c

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/log"
)

// IsIgnorableI2CBus checks if an I2C bus should be skipped during DDC probing.
// Based on ddcutil's sysfs_is_ignorable_i2c_device() (sysfs_base.c:1441)
func IsIgnorableI2CBus(busno int) bool {
	name := GetI2CDeviceSysfsName(busno)
	driver := GetI2CSysfsDriver(busno)

	if name != "" && IsIgnorableI2CDeviceName(name, driver) {
		log.Debugf("i2c-%d: ignoring '%s' (driver: %s)", busno, name, driver)
		return true
	}

	class := GetI2CDeviceSysfsClass(busno)
	if class != 0 {
		classHigh := class & 0xFFFF0000
		ignorable := (classHigh != 0x030000 && classHigh != 0x0A0000)
		if ignorable {
			log.Debugf("i2c-%d: ignoring class 0x%08x", busno, class)
		}
		return ignorable
	}

	return false
}

// IsIgnorableI2CDeviceName checks if the device name should be ignored.
// Based on ddcutil's ignorable_i2c_device_sysfs_name() (sysfs_base.c:1408)
func IsIgnorableI2CDeviceName(name, driver string) bool {
	ignorablePrefixes := []string{
		"SMBus",
		"Synopsys DesignWare",
		"soc:i2cdsi",
		"smu",
		"mac-io",
		"u4",
		"AMDGPU SMU",
	}

	for _, prefix := range ignorablePrefixes {
		if strings.HasPrefix(name, prefix) {
			return true
		}
	}

	if driver == "nouveau" && !strings.HasPrefix(name, "nvkm-") {
		return true
	}

	return false
}

// GetI2CDeviceSysfsName reads the sysfs name for an I2C bus.
// Based on ddcutil's get_i2c_device_sysfs_name() (sysfs_base.c:1175)
func GetI2CDeviceSysfsName(busno int) string {
	path := fmt.Sprintf("/sys/bus/i2c/devices/i2c-%d/name", busno)
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

// GetI2CDeviceSysfsClass reads the PCI class for an I2C device.
// Based on ddcutil's get_i2c_device_sysfs_class() (sysfs_base.c:1380)
func GetI2CDeviceSysfsClass(busno int) uint32 {
	classPath := fmt.Sprintf("/sys/bus/i2c/devices/i2c-%d/device/class", busno)
	data, err := os.ReadFile(classPath)
	if err != nil {
		classPath = fmt.Sprintf("/sys/bus/i2c/devices/i2c-%d/device/device/device/class", busno)
		data, err = os.ReadFile(classPath)
		if err != nil {
			return 0
		}
	}

	classStr := strings.TrimSpace(string(data))
	classStr = strings.TrimPrefix(classStr, "0x")

	class, err := strconv.ParseUint(classStr, 16, 32)
	if err != nil {
		return 0
	}

	return uint32(class)
}

// GetI2CSysfsDriver reads the kernel driver for an I2C bus.
// Based on ddcutil's get_i2c_sysfs_driver_by_busno() (sysfs_base.c:1284)
func GetI2CSysfsDriver(busno int) string {
	devicePath := fmt.Sprintf("/sys/bus/i2c/devices/i2c-%d", busno)
	adapterPath, err := FindI2CAdapter(devicePath)
	if err != nil {
		return ""
	}

	driverLink := filepath.Join(adapterPath, "driver")
	target, err := os.Readlink(driverLink)
	if err != nil {
		return ""
	}

	return filepath.Base(target)
}

// FindI2CAdapter traverses sysfs to find the I2C adapter device path.
func FindI2CAdapter(devicePath string) (string, error) {
	currentPath := devicePath

	for depth := 0; depth < 10; depth++ {
		if _, err := os.Stat(filepath.Join(currentPath, "name")); err == nil {
			return currentPath, nil
		}

		deviceLink := filepath.Join(currentPath, "device")
		target, err := os.Readlink(deviceLink)
		if err != nil {
			break
		}

		if !filepath.IsAbs(target) {
			target = filepath.Join(filepath.Dir(currentPath), target)
		}
		currentPath = filepath.Clean(target)
	}

	return "", fmt.Errorf("could not find adapter for %s", devicePath)
}
