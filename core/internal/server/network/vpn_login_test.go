package network

import (
	"context"
	"net"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func newLoginTestBackend() *NetworkManagerBackend {
	return &NetworkManagerBackend{state: &BackendState{}}
}

func TestBeginVPNLoginReplacesPreviousAttempt(t *testing.T) {
	b := newLoginTestBackend()

	first, finishFirst := b.beginVPNLogin("work")
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	addr := listener.Addr().String()

	// The abandoned login holds its port until its context ends.
	go func() {
		<-first.ctx.Done()
		listener.Close()
		finishFirst()
	}()

	second, finishSecond := b.beginVPNLogin("work")
	defer finishSecond()

	assert.True(t, first.cancelled(), "a retry cancels the earlier attempt, it does not fail it")
	assert.NoError(t, second.ctx.Err())

	again, err := net.Listen("tcp", addr)
	require.NoError(t, err, "the port is free once the retry starts")
	again.Close()
}

func TestVPNLoginStateFollowsTheWait(t *testing.T) {
	b := newLoginTestBackend()
	login, finish := b.beginVPNLogin("u-1")

	b.publishVPNLogin(login, "u-1", "Work", "https://gw/login")
	require.NotNil(t, b.state.VPNLogin)
	assert.Equal(t, "Work", b.state.VPNLogin.Name)
	assert.Equal(t, "https://gw/login", b.state.VPNLogin.URL)
	assert.True(t, b.state.VPNLogin.CanExtend)

	finish()
	assert.Nil(t, b.state.VPNLogin, "the wait disappears once the login ends")
}

func TestCancelVPNLogin(t *testing.T) {
	b := newLoginTestBackend()
	assert.ErrorIs(t, b.CancelVPNLogin(), errNoVPNLoginWaiting)

	login, finish := b.beginVPNLogin("u-1")
	defer finish()
	b.publishVPNLogin(login, "u-1", "Work", "")

	require.NoError(t, b.CancelVPNLogin())
	assert.True(t, login.cancelled())
	assert.ErrorIs(t, context.Cause(login.ctx), errVPNLoginCancelled)
}

func TestCancelVPNLoginForMatchesTheTarget(t *testing.T) {
	b := newLoginTestBackend()
	login, finish := b.beginVPNLogin("Work")
	defer finish()
	b.publishVPNLogin(login, "u-1", "Work", "")

	assert.False(t, b.cancelVPNLoginFor("Other"))
	assert.NoError(t, login.ctx.Err())

	assert.True(t, b.cancelVPNLoginFor("u-1"), "the UUID matches a login started by name")
	assert.True(t, login.cancelled())
}

func TestExtendVPNLogin(t *testing.T) {
	b := newLoginTestBackend()
	login, finish := b.beginVPNLogin("u-1")
	defer finish()
	b.publishVPNLogin(login, "u-1", "Work", "")
	before := b.state.VPNLogin.Deadline

	require.NoError(t, b.ExtendVPNLogin())
	assert.Equal(t, before+vpnLoginExtension.Milliseconds(), b.state.VPNLogin.Deadline)

	for b.ExtendVPNLogin() == nil {
	}
	assert.False(t, b.state.VPNLogin.CanExtend)
	assert.Equal(t, login.started.Add(vpnLoginMaxWait).UnixMilli(), b.state.VPNLogin.Deadline)
	assert.NoError(t, login.ctx.Err())
}

func TestVPNLoginTimesOut(t *testing.T) {
	b := newLoginTestBackend()
	login, finish := b.beginVPNLogin("u-1")
	defer finish()

	login.mu.Lock()
	login.timer.Reset(10 * time.Millisecond)
	login.mu.Unlock()

	<-login.ctx.Done()
	assert.ErrorIs(t, context.Cause(login.ctx), errVPNLoginTimedOut)
	assert.False(t, login.cancelled(), "a timeout is a failure the user should see")
}

func TestVPNConnectCancelled(t *testing.T) {
	assert.True(t, vpnConnectCancelled(errVPNLoginCancelled))
	assert.False(t, vpnConnectCancelled(errVPNLoginTimedOut))
}
