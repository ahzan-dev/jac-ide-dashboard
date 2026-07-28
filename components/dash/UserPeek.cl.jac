# User 360 drill-down panel — opens under any table when a user cell is clicked.
# Phase 1 (PostHog-only): profile, 30-day counters, cost by model, projects,
# recent activity. Spec: .docs/posthog/USER_360_BUILD_SPEC.md.
sv import from ...metrics_sv { user_360 }
import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..ui.badge { Badge }
import from ..ui.button { Button }
import from ..ui.skeleton { Skeleton }
import from ..ui.table { Table, TableHeader, TableBody, TableRow, TableHead, TableCell }

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

# Small generic table (no search/sort — the parent DataTable has that; this is
# the compact drill-down rendering). :pub — ProjectPeek reuses it.
def:pub MiniTable(block: dict) -> JsxElement {
    cols = block.get("columns", []) as list;
    rows = block.get("rows", []) as list;
    heads: list = [];
    for c in cols {
        heads = heads + [str(c).replace("_", " ")];
    }
    frows: list = [];
    ri = 0;
    for r in rows {
        cells: list = [];
        ci = 0;
        for cell in (r as list) {
            cells = cells + [{"k": str(ci), "v": "" if cell is None else str(cell)}];
            ci = ci + 1;
        }
        frows = frows + [{"k": "m" + str(ri), "cells": cells}];
        ri = ri + 1;
    }
    return <div className="max-h-64 overflow-auto">
        <Table>
            <TableHeader>
                <TableRow>
                    {for h in heads {
                        <TableHead key={h} className="text-xs">{h}</TableHead>
                    }}
                </TableRow>
            </TableHeader>
            <TableBody>
                {if len(frows) == 0 {
                    <TableRow><TableCell className="text-xs text-muted-foreground">none in window</TableCell></TableRow>
                }}
                {for fr in frows {
                    <TableRow key={str(fr["k"])}>
                        {for cc in fr["cells"] {
                            <TableCell key={str(cc["k"])} className="text-sm">{str(cc["v"])}</TableCell>
                        }}
                    </TableRow>
                }}
            </TableBody>
        </Table>
    </div>;
}

def:pub UserPeek(user: str, env: str, on_close: Callable[[], None], date_from: str = "", date_to: str = "") -> JsxElement {
    has loading: bool = True;
    has d: dict = {};

    async can with (user, date_from, date_to) entry {
        loading = True;
        try {
            d = (await user_360(user, env, date_from, date_to)) as dict;
        } except Exception {
            d = {};
        }
        loading = False;
    }
    def close(e: MouseEvent) {
        on_close();
    }

    prof = _row0(d.get("profile", {}) as dict);
    summ = _row0(d.get("summary", {}) as dict);
    ident = str(prof.get("email", "")) if str(prof.get("email", "")) else str(prof.get("display_name", ""));
    if ident == "" {
        ident = user;
    }
    dn = str(prof.get("display_name", ""));
    plan = str(prof.get("plan", ""));
    wlabel = str(d.get("window", "last 30 days"));
    sub = "first seen " + str(prof.get("first_seen", "—")) + " · last seen " + str(prof.get("last_seen", "—"))
        + " · " + str(prof.get("events", 0)) + " events (" + wlabel + ")";
    stats: list = [];
    for k in ["signed_up", "projects", "ai_turns", "ai_done", "ai_failed", "cost_usd", "previews", "deploys_ok", "deploys_failed", "gh_ok", "upgrades"] {
        v = summ.get(k);
        vs = str(v);
        stats = stats + [{"k": k.replace("_", " "), "v": "0" if (v is None) or (vs == "undefined") or (vs == "null") else vs}];
    }
    err = str(d.get("error", ""));
    replays: list = [];
    rb = d.get("replays", {}) as dict;
    replay_err = str(rb.get("error", "") or "");
    for rr in (rb.get("rows", []) as list) {
        rl = rr as list;
        if len(rl) == 3 {
            replays = replays + [{
                "label": "▶ " + str(rl[0]) + " UTC · " + str(rl[1]) + "s",
                "href": "https://us.posthog.com/project/425465/replay/" + str(rl[2])
            }];
        }
    }

    return <Card className="mt-2 border-primary/30">
        <CardHeader className="pb-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="flex items-center gap-2">
                    <CardTitle className="text-base font-semibold">👤 {ident}</CardTitle>
                    {if (dn != "") and (dn != ident) {
                        <span className="text-xs text-muted-foreground">({dn})</span>
                    }}
                    {if plan != "" {
                        <Badge variant="outline">{plan}</Badge>
                    }}
                </div>
                <Button variant="ghost" size="sm" className="h-6 px-2 text-xs" onClick={close}>✕ Close</Button>
            </div>
            <CardDescription className="text-sm">{sub} · drill-down window: {wlabel} · env: {env}</CardDescription>
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
                            <div key={"st" + str(si)} className="rounded-md border border-border px-2 py-1">
                                <span className="text-[11px] uppercase tracking-wide text-muted-foreground">{str(st["k"])} </span>
                                <span className="text-sm font-semibold tabular-nums">{str(st["v"])}</span>
                            </div>
                        }}
                    </div>
                    <div className="grid grid-cols-12 gap-3">
                        <div className="col-span-12 lg:col-span-4">
                            <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">Cost by model</p>
                            <MiniTable block={d.get("models", {}) as dict} />
                        </div>
                        <div className="col-span-12 lg:col-span-8">
                            <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">Projects by AI spend</p>
                            <MiniTable block={d.get("projects", {}) as dict} />
                        </div>
                        <div className="col-span-12">
                            <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">Session replays (PostHog player)</p>
                            {if replay_err != "" {
                                <p className="text-xs text-destructive">{replay_err}</p>
                            } elif len(replays) == 0 {
                                <p className="text-xs text-muted-foreground">No recordings for this user.</p>
                            }}
                            <div className="flex flex-wrap gap-2">
                                {for (rpi, rp) in enumerate(replays) {
                                    <a key={"rp" + str(rpi)} href={str(rp["href"])} target="_blank" className="rounded-md border border-border px-2 py-1 text-xs text-primary hover:bg-accent">{str(rp["label"])}</a>
                                }}
                            </div>
                        </div>
                        <div className="col-span-12">
                            <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">Recent activity (latest 40 events)</p>
                            <MiniTable block={d.get("timeline", {}) as dict} />
                        </div>
                    </div>
                </div>
            }}
        </CardContent>
    </Card>;
}
