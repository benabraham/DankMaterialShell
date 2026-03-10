package ddc

type VCPType string
type VCPCategory string

const (
	VCPTypeContinuous    VCPType = "continuous"
	VCPTypeNonContinuous VCPType = "non_continuous"
	VCPTypeBoolean       VCPType = "boolean"

	CategoryColor   VCPCategory = "color"
	CategoryAudio   VCPCategory = "audio"
	CategoryImage   VCPCategory = "image"
	CategoryInput   VCPCategory = "input"
	CategoryDisplay VCPCategory = "display"
	CategoryGame    VCPCategory = "game"
)

type VCPCodeDef struct {
	Code     byte        `json:"code"`
	Name     string      `json:"name"`
	Type     VCPType     `json:"type"`
	Category VCPCategory `json:"category"`
	Icon     string      `json:"icon"`
}

type FeatureInfo struct {
	Code            byte         `json:"code"`
	Name            string       `json:"name"`
	Type            VCPType      `json:"type"`
	Category        VCPCategory  `json:"category"`
	Icon            string       `json:"icon"`
	Current         int          `json:"current"`
	Max             int          `json:"max"`
	Min             int          `json:"min,omitempty"`
	DisplayOffset   int          `json:"displayOffset,omitempty"`
	DisplayMultiply int          `json:"displayMultiply,omitempty"`
	Unit            string       `json:"unit,omitempty"`
	PermittedValues []ValueLabel `json:"permittedValues,omitempty"`
}

type ValueLabel struct {
	Value int    `json:"value"`
	Label string `json:"label"`
}

type DeviceCapabilities struct {
	DeviceID        string        `json:"deviceId"`
	Bus             int           `json:"bus"`
	Name            string        `json:"name"`
	Model           string        `json:"model,omitempty"`
	Features        []FeatureInfo `json:"features"`
	SupportedResets []string      `json:"supportedResets,omitempty"`
}

type State struct {
	Devices  []DeviceCapabilities `json:"devices"`
	Scanning bool                 `json:"scanning"`
}
