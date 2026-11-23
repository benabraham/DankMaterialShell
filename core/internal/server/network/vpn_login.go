package network

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-shell/core/internal/log"
)

// A VPN login can wait minutes on the user: a browser page, a login window or
// a password prompt. Only one runs at a time. A new attempt cancels the one
// before it, so a retry never collides with a login the user abandoned (a
// Fortinet SAML retry used to fail on the still-bound redirect port).
//
// Browser logins publish their wait in the network state as vpnLogin, so the
// UI can show the time left and offer to reopen the page, extend or cancel.

const (
	vpnLoginTimeout   = 5 * time.Minute
	vpnLoginExtension = 5 * time.Minute
	vpnLoginMaxWait   = 30 * time.Minute
	// vpnLoginHandover bounds how long a new attempt waits for the cancelled
	// one to let go of its resources.
	vpnLoginHandover = 10 * time.Second
)

var (
	errVPNLoginTimedOut  = errors.New("login timed out")
	errNoVPNLoginWaiting = errors.New("no VPN login is waiting")
)

// VPNLoginState is a browser login waiting on the user.
type VPNLoginState struct {
	UUID string `json:"uuid"`
	Name string `json:"name"`
	// URL reopens the login page; empty when the login runs its own window.
	URL string `json:"url,omitempty"`
	// Deadline is when the login gives up, in Unix milliseconds.
	Deadline int64 `json:"deadline"`
	// CanExtend is false once the login has reached vpnLoginMaxWait.
	CanExtend bool `json:"canExtend"`
}

type vpnLoginAttempt struct {
	ctx    context.Context
	cancel context.CancelCauseFunc
	done   chan struct{}
	// target is what the caller asked for: a UUID or a profile name.
	target string

	mu        sync.Mutex
	timer     *time.Timer
	started   time.Time
	deadline  time.Time
	published *VPNLoginState
	// browser is the command line that opened the login page, reused on reopen.
	browser string
}

// cancelled reports whether the attempt was cancelled by the user or replaced
// by a newer attempt, as opposed to failing or timing out.
func (a *vpnLoginAttempt) cancelled() bool {
	return errors.Is(context.Cause(a.ctx), errVPNLoginCancelled)
}

func (a *vpnLoginAttempt) matches(uuidOrName string) bool {
	if a.target == uuidOrName {
		return true
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.published != nil && (a.published.UUID == uuidOrName || a.published.Name == uuidOrName)
}

// beginVPNLogin starts a login attempt, cancelling the previous one. The
// returned finish must run once the attempt is over.
func (b *NetworkManagerBackend) beginVPNLogin(target string) (*vpnLoginAttempt, func()) {
	ctx, cancel := context.WithCancelCause(context.Background())
	now := time.Now()
	attempt := &vpnLoginAttempt{
		ctx:      ctx,
		cancel:   cancel,
		done:     make(chan struct{}),
		target:   target,
		started:  now,
		deadline: now.Add(vpnLoginTimeout),
	}
	attempt.timer = time.AfterFunc(vpnLoginTimeout, func() { cancel(errVPNLoginTimedOut) })

	b.vpnLoginMu.Lock()
	previous := b.vpnLogin
	b.vpnLogin = attempt
	b.vpnLoginMu.Unlock()

	if previous != nil {
		log.Infof("[VPNLogin] Cancelling the previous login attempt (%s)", previous.target)
		previous.cancel(errVPNLoginCancelled)
		select {
		case <-previous.done:
		case <-time.After(vpnLoginHandover):
			log.Warnf("[VPNLogin] Previous login attempt did not stop within %s", vpnLoginHandover)
		}
	}

	var once sync.Once
	finish := func() {
		once.Do(func() {
			attempt.timer.Stop()
			cancel(context.Canceled)

			b.vpnLoginMu.Lock()
			if b.vpnLogin == attempt {
				b.vpnLogin = nil
			}
			b.vpnLoginMu.Unlock()

			b.clearVPNLoginState(attempt)
			close(attempt.done)
		})
	}
	return attempt, finish
}

// publishVPNLogin shows the attempt as a login waiting on the user.
func (b *NetworkManagerBackend) publishVPNLogin(attempt *vpnLoginAttempt, uuid, name, url string) {
	attempt.mu.Lock()
	state := &VPNLoginState{
		UUID:      uuid,
		Name:      name,
		URL:       url,
		Deadline:  attempt.deadline.UnixMilli(),
		CanExtend: attempt.deadline.Before(attempt.started.Add(vpnLoginMaxWait)),
	}
	attempt.published = state
	attempt.mu.Unlock()

	b.stateMutex.Lock()
	b.state.VPNLogin = state
	b.stateMutex.Unlock()
	b.notifyStateChange()
}

func (b *NetworkManagerBackend) clearVPNLoginState(attempt *vpnLoginAttempt) {
	attempt.mu.Lock()
	published := attempt.published
	attempt.mu.Unlock()
	if published == nil {
		return
	}

	b.stateMutex.Lock()
	cleared := b.state.VPNLogin == published
	if cleared {
		b.state.VPNLogin = nil
	}
	b.stateMutex.Unlock()
	if cleared {
		b.notifyStateChange()
	}
}

func (b *NetworkManagerBackend) notifyStateChange() {
	if b.onStateChange != nil {
		b.onStateChange()
	}
}

// waitingVPNLogin returns the attempt the UI shows as waiting, if any.
func (b *NetworkManagerBackend) waitingVPNLogin() (*vpnLoginAttempt, error) {
	b.vpnLoginMu.Lock()
	attempt := b.vpnLogin
	b.vpnLoginMu.Unlock()
	if attempt == nil || attempt.ctx.Err() != nil {
		return nil, errNoVPNLoginWaiting
	}
	attempt.mu.Lock()
	published := attempt.published
	attempt.mu.Unlock()
	if published == nil {
		return nil, errNoVPNLoginWaiting
	}
	return attempt, nil
}

// cancelVPNLoginFor cancels the running attempt if it targets this VPN.
func (b *NetworkManagerBackend) cancelVPNLoginFor(uuidOrName string) bool {
	b.vpnLoginMu.Lock()
	attempt := b.vpnLogin
	b.vpnLoginMu.Unlock()
	if attempt == nil || attempt.ctx.Err() != nil || !attempt.matches(uuidOrName) {
		return false
	}
	log.Infof("[VPNLogin] Cancelling the login for %s", uuidOrName)
	attempt.cancel(errVPNLoginCancelled)
	return true
}

// CancelVPNLogin stops the login waiting on the user.
func (b *NetworkManagerBackend) CancelVPNLogin() error {
	attempt, err := b.waitingVPNLogin()
	if err != nil {
		return err
	}
	log.Infof("[VPNLogin] Login cancelled by the user")
	attempt.cancel(errVPNLoginCancelled)
	return nil
}

// ExtendVPNLogin gives the waiting login more time, up to vpnLoginMaxWait.
func (b *NetworkManagerBackend) ExtendVPNLogin() error {
	attempt, err := b.waitingVPNLogin()
	if err != nil {
		return err
	}

	attempt.mu.Lock()
	limit := attempt.started.Add(vpnLoginMaxWait)
	if !attempt.deadline.Before(limit) {
		attempt.mu.Unlock()
		return fmt.Errorf("the login already waits the maximum of %s", vpnLoginMaxWait)
	}
	deadline := attempt.deadline.Add(vpnLoginExtension)
	if deadline.After(limit) {
		deadline = limit
	}
	// Stop fails once the timer fired: the login has already timed out.
	if !attempt.timer.Stop() {
		attempt.mu.Unlock()
		return errNoVPNLoginWaiting
	}
	attempt.deadline = deadline
	attempt.timer.Reset(time.Until(deadline))
	published := *attempt.published
	attempt.mu.Unlock()

	log.Infof("[VPNLogin] Login extended until %s", deadline.Format(time.TimeOnly))
	b.publishVPNLogin(attempt, published.UUID, published.Name, published.URL)
	return nil
}

// ReopenVPNLogin opens the waiting login's page in the browser again.
func (b *NetworkManagerBackend) ReopenVPNLogin() error {
	attempt, err := b.waitingVPNLogin()
	if err != nil {
		return err
	}
	attempt.mu.Lock()
	url := attempt.published.URL
	browser := attempt.browser
	attempt.mu.Unlock()
	if url == "" {
		return errors.New("this login has no page to reopen")
	}
	return openInBrowser(url, browser)
}
