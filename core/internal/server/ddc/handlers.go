package ddc

import (
	"encoding/json"
	"fmt"
	"net"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/server/models"
	"github.com/AvengeMedia/DankMaterialShell/core/internal/server/params"
)

func HandleRequest(conn net.Conn, req models.Request, m *Manager) {
	switch req.Method {
	case "ddc.getState":
		handleGetState(conn, req, m)
	case "ddc.getFeature":
		handleGetFeature(conn, req, m)
	case "ddc.setFeature":
		handleSetFeature(conn, req, m)
	case "ddc.resetDefaults":
		handleResetDefaults(conn, req, m)
	case "ddc.rescan":
		handleRescan(conn, req, m)
	case "ddc.subscribe":
		handleSubscribe(conn, req, m)
	default:
		models.RespondError(conn, req.ID, "unknown method: "+req.Method)
	}
}

func handleGetState(conn net.Conn, req models.Request, m *Manager) {
	models.Respond(conn, req.ID, m.GetState())
}

func handleGetFeature(conn net.Conn, req models.Request, m *Manager) {
	device, err := params.String(req.Params, "device")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	code, err := params.Int(req.Params, "code")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	feature, err := m.GetFeature(device, byte(code))
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	models.Respond(conn, req.ID, feature)
}

func handleSetFeature(conn net.Conn, req models.Request, m *Manager) {
	device, err := params.String(req.Params, "device")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	code, err := params.Int(req.Params, "code")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	value, err := params.Int(req.Params, "value")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	if err := m.SetFeature(device, byte(code), value); err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	models.Respond(conn, req.ID, models.SuccessResult{
		Success: true,
		Message: fmt.Sprintf("set VCP 0x%02X to %d", code, value),
	})
}

func handleResetDefaults(conn net.Conn, req models.Request, m *Manager) {
	device, err := params.String(req.Params, "device")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	resetType, err := params.String(req.Params, "type")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	if err := m.ResetDefaults(device, resetType); err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	models.Respond(conn, req.ID, models.SuccessResult{
		Success: true,
		Message: fmt.Sprintf("reset %s defaults", resetType),
	})
}

func handleRescan(conn net.Conn, req models.Request, m *Manager) {
	if err := m.ScanDevices(); err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}
	models.Respond(conn, req.ID, m.GetState())
}

func handleSubscribe(conn net.Conn, req models.Request, m *Manager) {
	clientID := fmt.Sprintf("ddc-%d", req.ID)

	ch := m.Subscribe(clientID)
	defer m.Unsubscribe(clientID)

	initialState := m.GetState()
	if err := json.NewEncoder(conn).Encode(models.Response[State]{
		ID:     req.ID,
		Result: &initialState,
	}); err != nil {
		return
	}

	for state := range ch {
		if err := json.NewEncoder(conn).Encode(models.Response[State]{
			ID:     req.ID,
			Result: &state,
		}); err != nil {
			return
		}
	}
}
