# Project 360 drill-down panel (P4) — opens under any table when a project_id
# cell is clicked. Summary counters + cost by model + recent activity.
sv import from ...metrics_sv { project_360 }
import from .UserPeek { MiniTable }
import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..ui.button { Button }
import from ..ui.skeleton { Skeleton }

def _row0(block: dict) -> dict {
    cols = block.get("columns", []) as list;
    rows = block.get("rows", []) as list;
    out: dict = {};
    if rows {
        r0 = rows[0] as list;
        i = 0;
        for c in cols {
            if i < len(r0) {
                out[str(c)] = r0[i];
            }
            i = i + 1;
        }
    }
    return out;
}

def:pub ProjectPeek(project: str, env: str, on_close: Callable[[], None]) -> JsxElement {
    has loading: bool = True;
    has d: dict = {};

    async can with (project) entry {
        loading = True;
        try {
            d = (await project_360(project, env)) as dict;
        } except Exception as e {
            d = {};
        }
        loading = False;
    }
    def close(e: MouseEvent) {
        on_close();
    }

    summ = _row0(d.get("summary", {}) as dict);
    owner = str(summ.get("owner", "unknown"));
    sub = "owner " + owner + " · first activity " + str(summ.get("first_activity", "—"))
        + " · last " + str(summ.get("last_activity", "—"))
        + " · drill-down window: last 30 days · env: " + env;
    stats: list = [];
    for k in ["users", "ai_sent", "ai_done", "ai_failed", "cost_runs", "cost_usd", "previews_requested"] {
        v = summ.get(k);
        vs = str(v);
        stats = stats + [{"k": k.replace("_", " "), "v": "0" if (v is None) or (vs == "undefined") or (vs == "null") else vs}];
    }
    err = str(d.get("error", ""));

    return <Card className="mt-2 border-primary/30">
        <CardHeader className="pb-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
                <CardTitle className="text-base font-semibold">📦 {project}</CardTitle>
                <Button variant="ghost" size="sm" className="h-6 px-2 text-xs" onClick={close}>✕ Close</Button>
            </div>
            <CardDescription className="text-sm">{sub}</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-3">
            {if loading {
                <Skeleton className="h-24 w-full" />
            } else {
                <div className="flex flex-col gap-3">
                    {if err != "" {
                        <p className="text-xs text-destructive">Partial data: {err}</p>
                    }}
                    <div className="flex flex-wrap gap-2">
                        {for (si, st) in enumerate(stats) {
                            <div key={"ps" + str(si)} className="rounded-md border border-border px-2 py-1">
                                <span className="text-[11px] uppercase tracking-wide text-muted-foreground">{str(st["k"])} </span>
                                <span className="text-sm font-semibold tabular-nums">{str(st["v"])}</span>
                            </div>
                        }}
                    </div>
                    <div className="grid grid-cols-12 gap-3">
                        <div className="col-span-12 lg:col-span-4">
                            <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">Cost by model (30d)</p>
                            <MiniTable block={d.get("models", {}) as dict} />
                        </div>
                        <div className="col-span-12 lg:col-span-8">
                            <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">Recent activity (latest 40 events)</p>
                            <MiniTable block={d.get("timeline", {}) as dict} />
                        </div>
                    </div>
                    <p className="text-xs text-muted-foreground">Deploy events carry no project id in telemetry, so per-project deploy history isn't shown (product tracking gap).</p>
                </div>
            }}
        </CardContent>
    </Card>;
}
