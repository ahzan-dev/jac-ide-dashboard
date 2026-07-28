# Users directory (User-360 full page, spec Phase 1) — every active person in
# the selected date range (falls back to last-30-days when the picker is empty),
# newest activity first. Clicking any user opens their full 360 panel (profile,
# counters, cost by model, projects, session replays, timeline) right below the
# table via DataTable's built-in drill-down.
sv import from ...metrics_sv { user_list }
import from ..dash.DataTable { DataTable }
import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..ui.skeleton { Skeleton }

def:pub UsersDirectoryPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has data: dict = {};
    has loading: bool = True;
    has seen: int = -999;

    async can with (env, date_from, date_to, refresh_n) entry {
        seen = refresh_n;
        loading = True;
        try {
            data = (await user_list(env, date_from, date_to)) as dict;
        } except Exception {
            data = {"columns": [], "rows": []};
        }
        loading = False;
    }

    cols = (data.get("columns", []) as list) if data else [];
    rows = (data.get("rows", []) as list) if data else [];
    wlabel = str(data.get("window", "last 30 days")) if data else "last 30 days";

    return <div className="flex flex-col gap-4">
        <Card>
            <CardHeader className="pb-2">
                <CardTitle className="text-base font-semibold">Users directory</CardTitle>
                <CardDescription className="text-sm">{"Everyone active in " + wlabel + ", newest activity first — click any user to open their full 360 (profile, cost by model, projects, session replays, activity). Window and env follow the pickers."}</CardDescription>
            </CardHeader>
            <CardContent>
                {if loading {
                    <Skeleton className="h-64 w-full" />
                } else {
                    <DataTable columns={cols} rows={rows} env={env} date_from={date_from} date_to={date_to} />
                }}
            </CardContent>
        </Card>
    </div>;
}
