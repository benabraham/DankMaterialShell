package ddci2c

// VCPReply holds the response from a DDC/CI VCP feature query.
type VCPReply struct {
	VCP     byte
	Current int
	Max     int
}
