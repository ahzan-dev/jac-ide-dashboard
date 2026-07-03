import from "@jac/runtime" { jacLogin }
import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..ui.input { Input }
import from ..ui.label { Label }
import from ..ui.button { Button }

def:pub LoginPage(on_login: Callable[[], None]) -> JsxElement {
    has username: str = "";
    has password: str = "";
    has err: str = "";
    has busy: bool = False;

    async def do_login() {
        busy = True;
        err = "";
        ok: bool = False;
        try {
            ok = await jacLogin(username, password);
            if ok {
                on_login();
            } else {
                err = "Invalid credentials.";
            }
        } except Exception as e {
            err = "Login error.";
        }
        busy = False;
    }
    def on_username(e: ChangeEvent) { username = e.target.value; }
    def on_password(e: ChangeEvent) { password = e.target.value; }
    def on_key(e: KeyboardEvent) {
        if e.key == "Enter" {
            do_login();
        }
    }

    return <div className="flex min-h-svh items-center justify-center bg-background p-6">
        <Card className="w-full max-w-sm">
            <CardHeader>
                <div className="flex items-center gap-2">
                    <div className="size-2.5 rounded-full bg-primary"></div>
                    <CardTitle>JacHammer Analytics</CardTitle>
                </div>
                <CardDescription>Internal · admin access only. This dashboard shows revenue &amp; cost data.</CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-3">
                <div className="flex flex-col gap-1.5">
                    <Label htmlFor="u">Username</Label>
                    <Input id="u" value={username} onChange={on_username} onKeyDown={on_key} placeholder="admin" />
                </div>
                <div className="flex flex-col gap-1.5">
                    <Label htmlFor="p">Password</Label>
                    <Input id="p" type="password" value={password} onChange={on_password} onKeyDown={on_key} />
                </div>
                <Button className="mt-1" onClick={do_login} disabled={busy}>{"Signing in…" if busy else "Sign in"}</Button>
                {if err {
                    <p className="text-xs text-destructive">{err}</p>
                }}
            </CardContent>
        </Card>
    </div>;
}
