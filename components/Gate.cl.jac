sv import from ..metrics_sv { verify_session }
import from "@jac/runtime" { jacIsLoggedIn, jacLogout }
import from .AppShell { AppShell }
import from .pages.LoginPage { LoginPage }

# Auth boundary: unauthenticated → login; authenticated → the dashboard.
# The real security is server-side (data endpoints are def:priv → 401 without a token);
# this routes the UI and validates a stored token on load (present ≠ valid).
def:pub Gate() -> JsxElement {
    has authed: bool = False;
    has checked: bool = False;

    async can with entry {
        if jacIsLoggedIn() {
            try {
                await verify_session();
                authed = True;
            } except Exception as e {
                jacLogout();
                authed = False;
            }
        }
        checked = True;
    }

    def on_login() {
        authed = True;
    }
    def on_logout() {
        jacLogout();
        authed = False;
    }

    if not checked {
        return <div className="min-h-svh bg-background"></div>;
    }
    if not authed {
        return <LoginPage on_login={on_login} />;
    }
    return <AppShell on_logout={on_logout} />;
}
