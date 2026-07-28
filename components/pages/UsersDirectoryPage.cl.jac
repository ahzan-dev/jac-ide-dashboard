# Users directory (User-360 full page, spec Phase 1) — every active person of
# the last 30 days by recency. Clicking any user opens their full 360 panel
# (profile, counters, cost by model, projects, session replays, timeline)
# right below the table via DataTable's built-in drill-down.
sv import from ...metrics_sv { user_list }
import from ..dash.DataTable { DataTable }
import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..ui.skeleton { Skeleton }

def:pub UsersDirectoryPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has data: dict = {};
    has loading: bool = True;
    has seen: int = -999;

    async can with (env, refresh_n) entry {
        if refresh_n == seen {
            return;
        }
        seen = refresh_n;
        loading = True;
        try {
            data = (await user_list(env)) as dict;
        } except Exception as e {
            data = {"columns": [], "rows": []};
        }
        loading = False;
    }

    cols = (data.get("columns", []) as list) if data else [];
    rows = (data.get("rows", []) as list) if data else [];

    return <div className="flex flex-col gap-4">
        <Card>
            <CardHeader className="pb-2">
                <CardTitle className="text-base font-semibold">Users directory</CardTitle>
                <CardDescription className="text-sm">Everyone active in the last 30 days, newest activity first — click any user to open their full 360 (profile, cost by model, projects, session replays, activity). Fixed 30-day window; env follows the picker.</CardDescription>
            </CardHeader>
            <CardContent>
                {if loading {
                    <Skeleton className="h-64 w-full" />
                } else {
                    <DataTable columns={cols} rows={rows} env={env} />
                }}
            </CardContent>
        </Card>
    </div>;
}
