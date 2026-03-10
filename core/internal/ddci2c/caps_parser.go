package ddci2c

import (
	"fmt"
	"strconv"
	"strings"
)

// ParsedCapabilities holds the parsed DDC capability string.
type ParsedCapabilities struct {
	Model    string
	VCPCodes []VCPCapEntry
}

// VCPCapEntry represents a single VCP code entry from the capabilities string.
type VCPCapEntry struct {
	Code   byte
	Values []byte // for non-continuous types; empty for continuous
}

// ParseCapabilities parses a DDC capabilities string.
// Format: (prot(monitor)type(LCD)model(U2722D)vcp(10 12 14(04 05 08) 60(0F 11 12) ...))
func ParseCapabilities(raw string) (*ParsedCapabilities, error) {
	if raw == "" {
		return nil, fmt.Errorf("empty capabilities string")
	}

	result := &ParsedCapabilities{}

	result.Model = extractField(raw, "model")
	vcpStr := extractField(raw, "vcp")

	if vcpStr != "" {
		entries, err := parseVCPCodes(vcpStr)
		if err != nil {
			return nil, fmt.Errorf("parse vcp codes: %w", err)
		}
		result.VCPCodes = entries
	}

	return result, nil
}

// extractField extracts the content of a named field from the capabilities string.
// For "model(U2722D)" it returns "U2722D".
func extractField(raw, field string) string {
	key := field + "("
	idx := strings.Index(raw, key)
	if idx < 0 {
		return ""
	}

	start := idx + len(key)
	depth := 1
	end := start

	for end < len(raw) && depth > 0 {
		switch raw[end] {
		case '(':
			depth++
		case ')':
			depth--
		}
		if depth > 0 {
			end++
		}
	}

	if depth != 0 {
		return ""
	}

	return raw[start:end]
}

// parseVCPCodes parses the VCP codes section.
// Input: "10 12 14(04 05 08) 60(0F 11 12)"
func parseVCPCodes(vcpStr string) ([]VCPCapEntry, error) {
	var entries []VCPCapEntry
	vcpStr = strings.TrimSpace(vcpStr)
	i := 0

	for i < len(vcpStr) {
		// Skip whitespace
		for i < len(vcpStr) && vcpStr[i] == ' ' {
			i++
		}
		if i >= len(vcpStr) {
			break
		}

		// Read hex code (2 characters)
		codeEnd := i
		for codeEnd < len(vcpStr) && vcpStr[codeEnd] != ' ' && vcpStr[codeEnd] != '(' {
			codeEnd++
		}

		codeStr := vcpStr[i:codeEnd]
		code, err := strconv.ParseUint(codeStr, 16, 8)
		if err != nil {
			i = codeEnd
			continue
		}

		entry := VCPCapEntry{Code: byte(code)}
		i = codeEnd

		// Check for values in parentheses
		if i < len(vcpStr) && vcpStr[i] == '(' {
			i++ // skip '('
			valStart := i
			depth := 1
			for i < len(vcpStr) && depth > 0 {
				switch vcpStr[i] {
				case '(':
					depth++
				case ')':
					depth--
				}
				if depth > 0 {
					i++
				}
			}

			valStr := strings.TrimSpace(vcpStr[valStart:i])
			if valStr != "" {
				for _, vs := range strings.Fields(valStr) {
					val, err := strconv.ParseUint(vs, 16, 8)
					if err != nil {
						continue
					}
					entry.Values = append(entry.Values, byte(val))
				}
			}

			if i < len(vcpStr) {
				i++ // skip ')'
			}
		}

		entries = append(entries, entry)
	}

	return entries, nil
}

// HasVCPCode checks if the parsed capabilities include a specific VCP code.
func (pc *ParsedCapabilities) HasVCPCode(code byte) bool {
	for _, entry := range pc.VCPCodes {
		if entry.Code == code {
			return true
		}
	}
	return false
}

// GetVCPEntry returns the VCP capability entry for a specific code.
func (pc *ParsedCapabilities) GetVCPEntry(code byte) (VCPCapEntry, bool) {
	for _, entry := range pc.VCPCodes {
		if entry.Code == code {
			return entry, true
		}
	}
	return VCPCapEntry{}, false
}
