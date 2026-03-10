package ddci2c

import (
	"encoding/binary"
	"errors"
	"fmt"
	"strings"
	"syscall"
	"time"

	"golang.org/x/sys/unix"
)

const (
	I2C_SLAVE       = 0x0703
	DDCCI_ADDR      = 0x37
	DDCCI_VCP_GET   = 0x01
	DDCCI_VCP_SET   = 0x03
	DDC_SOURCE_ADDR = 0x51
	EDID_ADDR       = 0x50

	DDCCI_CAP_REQUEST = 0xF3
	DDCCI_CAP_REPLY   = 0xE3
)

func flushInput(fd int) {
	for i := 0; i < 3; i++ {
		dummy := make([]byte, 32)
		n, _ := syscall.Read(fd, dummy)
		if n == 0 {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
}

var errInvalidEDID = errors.New("invalid edid")

func setI2CAddr(fd, addr int) error {
	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), I2C_SLAVE, uintptr(addr)); errno != 0 {
		return errno
	}
	return nil
}

func detectX37(fd int) bool {
	if n, err := syscall.Read(fd, make([]byte, 1)); err == nil && n == 1 {
		return true
	}
	_, err := syscall.Write(fd, nil)
	return err == nil
}

func readBusEDID(fd int) ([]byte, error) {
	if err := setI2CAddr(fd, EDID_ADDR); err != nil {
		return nil, err
	}
	var err error
	consecutiveEIO := 0
	for _, size := range []int{128, 128, 256, 256} {
		edid := make([]byte, size)
		if err = readEDIDOnce(fd, edid); err == nil {
			return edid[:128], nil
		}
		switch {
		case errors.Is(err, syscall.ENXIO), errors.Is(err, syscall.EOPNOTSUPP), errors.Is(err, syscall.ETIMEDOUT):
			return nil, err
		case errors.Is(err, syscall.EIO):
			consecutiveEIO++
			if consecutiveEIO >= 2 {
				return nil, err
			}
		default:
			consecutiveEIO = 0
		}
	}
	return nil, err
}

func readEDIDOnce(fd int, edid []byte) error {
	if _, err := syscall.Write(fd, []byte{0x00}); err != nil {
		return err
	}
	n, err := syscall.Read(fd, edid)
	if err != nil {
		return err
	}
	if n < 128 || !isValidEDID(edid[:128]) {
		return errInvalidEDID
	}
	return nil
}

func DDCCIChecksum(payload []byte) byte {
	sum := byte(0x6E)
	for _, b := range payload {
		sum ^= b
	}
	return sum
}

func GetVCPFeatureRaw(fd int, vcp byte) (*VCPReply, error) {
	data := []byte{
		DDCCI_VCP_GET,
		vcp,
	}

	payload := []byte{
		DDC_SOURCE_ADDR,
		byte(len(data)) | 0x80,
	}
	payload = append(payload, data...)
	payload = append(payload, DDCCIChecksum(payload))

	n, err := syscall.Write(fd, payload)
	if err != nil || n != len(payload) {
		return nil, fmt.Errorf("write i2c: %w", err)
	}

	time.Sleep(50 * time.Millisecond)

	response := make([]byte, 12)
	n, err = syscall.Read(fd, response)
	if err != nil || n < 8 {
		return nil, fmt.Errorf("read i2c: %w", err)
	}

	if response[0] != 0x6E || response[2] != 0x02 {
		return nil, fmt.Errorf("invalid ddc response")
	}

	resultCode := response[3]
	if resultCode != 0x00 {
		return nil, fmt.Errorf("vcp feature not supported")
	}

	responseVCP := response[4]
	if responseVCP != vcp {
		return nil, fmt.Errorf("vcp mismatch: wanted 0x%02x, got 0x%02x", vcp, responseVCP)
	}

	maxHigh := response[6]
	maxLow := response[7]
	currentHigh := response[8]
	currentLow := response[9]

	max := int(binary.BigEndian.Uint16([]byte{maxHigh, maxLow}))
	current := int(binary.BigEndian.Uint16([]byte{currentHigh, currentLow}))

	return &VCPReply{
		VCP:     vcp,
		Max:     max,
		Current: current,
	}, nil
}

func SetVCPFeatureRaw(fd int, vcp byte, value int) error {
	data := []byte{
		DDCCI_VCP_SET,
		vcp,
		byte(value >> 8),
		byte(value & 0xFF),
	}

	payload := []byte{
		DDC_SOURCE_ADDR,
		byte(len(data)) | 0x80,
	}
	payload = append(payload, data...)
	payload = append(payload, DDCCIChecksum(payload))

	n, err := syscall.Write(fd, payload)
	if err != nil || n != len(payload) {
		return fmt.Errorf("write i2c: wrote %d/%d: %w", n, len(payload), err)
	}

	time.Sleep(50 * time.Millisecond)

	return nil
}

func ReadCapabilityStringRaw(fd int) (string, error) {
	var result strings.Builder
	offset := 0

	for {
		flushInput(fd)

		data := []byte{
			DDCCI_CAP_REQUEST,
			byte(offset >> 8),
			byte(offset & 0xFF),
		}

		payload := []byte{
			DDC_SOURCE_ADDR,
			byte(len(data)) | 0x80,
		}
		payload = append(payload, data...)
		payload = append(payload, DDCCIChecksum(payload))

		n, err := syscall.Write(fd, payload)
		if err != nil || n != len(payload) {
			return "", fmt.Errorf("write caps request: %w", err)
		}

		time.Sleep(50 * time.Millisecond)

		pollFds := []unix.PollFd{
			{
				Fd:     int32(fd),
				Events: unix.POLLIN,
			},
		}

		pollResult, err := unix.Poll(pollFds, 200)
		if err != nil {
			return "", fmt.Errorf("poll caps: %w", err)
		}
		if pollResult == 0 {
			if result.Len() > 0 {
				break
			}
			return "", fmt.Errorf("caps poll timeout")
		}
		if pollFds[0].Revents&unix.POLLIN == 0 {
			break
		}

		response := make([]byte, 64)
		n, err = syscall.Read(fd, response)
		if err != nil || n < 4 {
			return "", fmt.Errorf("read caps: %w", err)
		}

		if response[0] != 0x6E {
			return "", fmt.Errorf("invalid caps response header")
		}

		msgLen := int(response[1] & 0x7F)
		if msgLen < 3 || n < msgLen+3 {
			break
		}

		if response[2] != DDCCI_CAP_REPLY {
			return "", fmt.Errorf("unexpected caps reply opcode: 0x%02x", response[2])
		}

		fragStart := 5
		fragEnd := 2 + msgLen
		if fragEnd > n-1 {
			fragEnd = n - 1
		}

		if fragStart >= fragEnd {
			break
		}

		fragment := response[fragStart:fragEnd]
		for _, b := range fragment {
			if b == 0 {
				return result.String(), nil
			}
			result.WriteByte(b)
		}

		offset += fragEnd - fragStart

		if msgLen < 32 {
			break
		}
	}

	return result.String(), nil
}
