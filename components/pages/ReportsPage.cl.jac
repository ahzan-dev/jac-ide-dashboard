# Report Studio (R1) — snapshot reports built from registry recipes.
# List view: existing reports + a "New report" inline form (native datetime-local
# inputs — sub-day windows are the point; Popover/Calendar freeze this build).
# Detail view: ordered sections (header / text / tile / table) rendered from the
# FROZEN snapshot (report_build), so a submitted report's numbers never drift.
# Gotcha discipline: JSX slots stay trivial — all branching/formatting happens in
# component BODIES (SectionBlock) or precomputed dicts, never inside a for-slot.
sv import from ...metrics_sv {
    report_list, report_create, report_get, report_build, report_delete,
    report_generate, report_share, report_unshare, report_export_md,
    window_list, window_add
}
import from ..dash.DynamicTile { DynamicTile }
import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..ui.button { Button }
import from ..ui.badge { Badge }
import from ..ui.input { Input }
import from ..ui.label { Label }
import from ..ui.skeleton { Skeleton }
import from ..ui.select { Select, SelectTrigger, SelectValue, SelectContent, SelectGroup, SelectItem }
import from ..ui.table { Table, TableHeader, TableBody, TableRow, TableHead, TableCell }
import from ..dash.util { iso_days_ago }

def _span(chart: str) -> str {
    if chart == "stat" or chart == "gauge" {
        return "col-span-12 sm:col-span-6 lg:col-span-3";
    }
    if chart == "table" or chart == "retention" or chart == "stackbar" {
        return "col-span-12";
    }
    return "col-span-12 lg:col-span-6";
}

def OpenBtn(rid: str, on_open: Callable[[str], None]) -> JsxElement {
    def h(e: MouseEvent) {
        on_open(rid);
    }
    return <Button size="sm" variant="outline" onClick={h}>Open</Button>;
}

# Named-window quick-pick chip: clicking fills the form's from/to inputs.
def WindowChip(w: dict, on_pick: Callable[[str, str], None]) -> JsxElement {
    def h(e: MouseEvent) {
        on_pick(str(w["from"]), str(w["to"]));
    }
    return <Button size="sm" variant="secondary" className="h-7 text-xs" onClick={h}>{str(w["label"])}</Button>;
}

# One report section. All type-branching lives HERE (component body), so the
# page's for-loop slot stays a single trivial element. :pub — PublicReport
# renders shared snapshots with the exact same blocks.
def:pub SectionBlock(fr: dict) -> JsxElement {
    typ = str(fr["type"]);
    title = str(fr["title"]);
    if typ == "header" {
        return <div className="col-span-12 mt-2">
            <h3 className="border-b border-border pb-1 text-sm font-semibold">{title}</h3>
        </div>;
    }
    if typ == "text" {
        return <div className="col-span-12">
            <Card>
                <CardHeader className="pb-2"><CardTitle className="text-xs text-muted-foreground">{title}</CardTitle></CardHeader>
                <CardContent><p className="whitespace-pre-wrap text-sm">{str(fr["md"])}</p></CardContent>
            </Card>
        </div>;
    }
    if fr["built"] as bool {
        ch = str(fr["chart"]);
        return <div className={_span(ch)}>
            <DynamicTile chart={ch} title={title} data={fr["data"]} loading={False} />
        </div>;
    }
    return <div className="col-span-12 lg:col-span-6">
        <Card><CardHeader><CardDescription className="text-xs">"{title}" — not built yet. Click Rebuild.</CardDescription></CardHeader></Card>
    </div>;
}

def:pub ReportsPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has reports: list[dict] = [];
    has loading: bool = True;
    has show_form: bool = False;
    has f_title: str = "";
    has f_from: str = iso_days_ago(7) + "T00:00";
    has f_to: str = iso_days_ago(0) + "T23:59";
    has f_template: str = "event-report";
    has f_error: str = "";
    has creating: bool = False;
    has active_id: str = "";
    has active: dict = {};
    has building: bool = False;
    has windows: list[dict] = [];
    has f_wname: str = "";
    has generating: bool = False;
    has gen_error: str = "";
    has sharing: bool = False;

    async def load_list() {
        loading = True;
        try {
            reports = (await report_list()) as list[dict];
        } except Exception as e {
            reports = [];
        }
        loading = False;
        try {
            windows = (await window_list()) as list[dict];
        } except Exception as e {
            windows = [];
        }
    }
    async can with (refresh_n) entry {
        await load_list();
    }

    async def open_report(rid: str) {
        active_id = rid;
        building = True;
        r = (await report_get(rid)) as dict;
        # First open of a never-built report: build (freeze) it right away.
        if not str(r.get("built_at", "")) {
            r = (await report_build(rid, False)) as dict;
        }
        active = r;
        building = False;
    }
    async def rebuild(e: MouseEvent) {
        if not active_id {
            return;
        }
        building = True;
        active = (await report_build(active_id, True)) as dict;
        building = False;
    }
    async def gen_ai(e: MouseEvent) {
        if not active_id {
            return;
        }
        generating = True;
        gen_error = "";
        res = (await report_generate(active_id)) as dict;
        if res.get("ok", False) as bool {
            active = (await report_get(active_id)) as dict;
        } else {
            gen_error = str(res.get("reason", "generation failed"));
        }
        generating = False;
    }
    # Share = publish a frozen (email-masked) copy to the public commons.
    async def share(e: MouseEvent) {
        if (not active_id) or sharing {
            return;
        }
        sharing = True;
        tok = str(active.get("share_token", ""));
        if tok == "" {
            await report_share(active_id, True);
        } else {
            await report_unshare(active_id);
        }
        active = (await report_get(active_id)) as dict;
        sharing = False;
    }
    async def export_md(e: MouseEvent) {
        if not active_id {
            return;
        }
        res = (await report_export_md(active_id)) as dict;
        md = str(res.get("md", ""));
        if md == "" {
            return;
        }
        blob = new(Blob, [md], {"type": "text/markdown"});
        url = URL.createObjectURL(blob);
        a = document.createElement("a");
        a.href = url;
        a.download = str(res.get("title", "report")).replace(" ", "_") + ".md";
        a.click();
        URL.revokeObjectURL(url);
    }
    def back(e: MouseEvent) {
        active_id = "";
        active = {};
        load_list();
    }
    async def remove(e: MouseEvent) {
        if not active_id {
            return;
        }
        await report_delete(active_id);
        active_id = "";
        active = {};
        await load_list();
    }

    def toggle_form(e: MouseEvent) {
        show_form = not show_form;
        f_error = "";
    }
    def on_title(e: Event) {
        f_title = e.target.value as str;
    }
    def on_from(e: Event) {
        f_from = e.target.value as str;
    }
    def on_to(e: Event) {
        f_to = e.target.value as str;
    }
    def on_template(v: str) {
        f_template = v;
    }
    def on_wname(e: Event) {
        f_wname = e.target.value as str;
    }
    def pick_window(f: str, t: str) {
        f_from = f;
        f_to = t;
    }
    async def save_window(e: MouseEvent) {
        if not f_wname {
            return;
        }
        windows = (await window_add(f_wname, f_from, f_to)) as list[dict];
        f_wname = "";
    }
    async def create(e: MouseEvent) {
        creating = True;
        f_error = "";
        res = (await report_create(f_title, f_from, f_to, env, f_template)) as dict;
        creating = False;
        if str(res.get("error", "")) {
            f_error = str(res["error"]);
            return;
        }
        show_form = False;
        f_title = "";
        await open_report(str(res["id"]));
    }

    # ---- precompute everything the JSX needs (trivial slots only) -----------
    report_rows: list[dict] = [];
    for r in reports {
        rd = r as dict;
        fdt = str(rd.get("from_dt", ""));
        tdt = str(rd.get("to_dt", ""));
        blt = str(rd.get("built_at", ""));
        report_rows = report_rows + [{
            "id": str(rd.get("id", "")), "title": str(rd.get("title", "")),
            "window": fdt[:16] + " → " + tdt[:16],
            "env": str(rd.get("env", "")),
            "built": blt if blt else "not built"
        }];
    }

    secs: list[dict] = [];
    hdr_title = "";
    hdr_sub = "";
    if active_id != "" {
        hdr_title = str(active.get("title", "Report"));
        blt2 = str(active.get("built_at", ""));
        hdr_sub = str(active.get("from_dt", ""))[:16] + " → " + str(active.get("to_dt", ""))[:16] + " UTC";
        if blt2 {
            hdr_sub = hdr_sub + " · built " + blt2 + " UTC";
        }
        if not building {
            snap = active.get("snapshot", {}) as dict;
            for s in (active.get("sections", []) as list) {
                sd = s as dict;
                sid = str(sd.get("id", ""));
                typ = str(sd.get("type", ""));
                fr = {"id": sid, "type": typ, "title": str(sd.get("title", "")), "md": str(sd.get("md", "")),
                      "chart": "", "data": {}, "built": False};
                if (typ == "tile") or (typ == "table") {
                    sn = snap.get(sid, {}) as dict;
                    if sn {
                        fr["chart"] = str(sn.get("chart", "table"));
                        fr["data"] = sn.get("data", {});
                        fr["built"] = True;
                    }
                }
                secs = secs + [fr];
            }
        }
    }

    failed_checks: list[dict] = [];
    checks_ok_text = "";
    for c in (active.get("checks", []) as list) {
        cd = c as dict;
        if cd.get("ok", True) as bool {
            checks_ok_text = checks_ok_text + "✓ " + str(cd.get("name", "")) + " passed — " + str(cd.get("detail", "")) + "  ";
        } else {
            failed_checks = failed_checks + [{"txt": "⚠ " + str(cd.get("name", "")) + ": " + str(cd.get("detail", ""))}];
        }
    }
    active_env = str(active.get("env", ""));
    win_chips: list[dict] = [];
    for w in windows {
        wd = w as dict;
        wf = str(wd.get("from_dt", "")).replace(" ", "T")[:16];
        wt = str(wd.get("to_dt", "")).replace(" ", "T")[:16];
        win_chips = win_chips + [{"label": str(wd.get("name", "")), "from": wf, "to": wt}];
    }
    new_btn_label = "Close" if show_form else "+ New report";
    create_btn_label = "Creating…" if creating else "Create & build";
    rebuild_btn_label = "Building…" if building else "Rebuild";
    gen_btn_label = "Generating…" if generating else "✨ Generate insights";
    active_token = str(active.get("share_token", ""));
    share_btn_label = "Unshare" if active_token != "" else "🔗 Share";
    if sharing {
        share_btn_label = "…";
    }
    share_url = "";
    if active_token != "" {
        share_url = str(window.location.origin) + "/report/" + active_token;
    }

    return <div className="flex flex-col gap-4">
        {if active_id == "" {
            <div className="flex flex-col gap-4">
                <div className="flex items-center justify-between">
                    <div className="flex flex-col">
                        <h2 className="text-base font-semibold">Reports</h2>
                        <p className="text-xs text-muted-foreground">Snapshot documents built from verified registry metrics — numbers are frozen at build time.</p>
                    </div>
                    <Button onClick={toggle_form}>{new_btn_label}</Button>
                </div>

                {if show_form {
                    <Card>
                        <CardHeader>
                            <CardTitle className="text-sm">New report</CardTitle>
                            <CardDescription className="text-xs">Window supports minute precision (e.g. a 7.5-hour hackathon). Times are UTC. Environment: {env}.</CardDescription>
                        </CardHeader>
                        <CardContent>
                            <div className="grid grid-cols-12 gap-3">
                                <div className="col-span-12 sm:col-span-6 flex flex-col gap-1.5">
                                    <Label className="text-xs">Title</Label>
                                    <Input value={f_title} onChange={on_title} placeholder="Hackathon report — 2026-07-26" />
                                </div>
                                <div className="col-span-12 sm:col-span-6 flex flex-col gap-1.5">
                                    <Label className="text-xs">Template</Label>
                                    <Select value={f_template} onValueChange={on_template}>
                                        <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                                        <SelectContent>
                                            <SelectGroup>
                                                <SelectItem value="event-report">Event report (hackathon / launch)</SelectItem>
                                                <SelectItem value="blank">Blank</SelectItem>
                                            </SelectGroup>
                                        </SelectContent>
                                    </Select>
                                </div>
                                <div className="col-span-12 sm:col-span-6 flex flex-col gap-1.5">
                                    <Label className="text-xs">From (UTC)</Label>
                                    <Input type="datetime-local" value={f_from} onChange={on_from} />
                                </div>
                                <div className="col-span-12 sm:col-span-6 flex flex-col gap-1.5">
                                    <Label className="text-xs">To (UTC)</Label>
                                    <Input type="datetime-local" value={f_to} onChange={on_to} />
                                </div>
                            </div>
                            <div className="mt-3 flex flex-wrap items-center gap-2 border-t border-border pt-3">
                                <span className="text-[11px] text-muted-foreground">Named windows:</span>
                                {for (wi, wc) in enumerate(win_chips) {
                                    <WindowChip key={"w" + str(wi)} w={wc} on_pick={pick_window} />
                                }}
                                <Input className="h-7 w-40 text-xs" value={f_wname} onChange={on_wname} placeholder="Save window as…" />
                                <Button size="sm" variant="outline" className="h-7 text-xs" onClick={save_window}>Save</Button>
                            </div>
                            {if f_error != "" {
                                <p className="mt-2 text-xs text-destructive">{f_error}</p>
                            }}
                            <div className="mt-3 flex justify-end">
                                <Button onClick={create} disabled={creating}>{create_btn_label}</Button>
                            </div>
                        </CardContent>
                    </Card>
                }}

                {if loading {
                    <Skeleton className="h-32 w-full" />
                } elif len(report_rows) == 0 {
                    <Card>
                        <CardHeader>
                            <CardTitle className="text-base">No reports yet</CardTitle>
                            <CardDescription className="text-xs">Create one from the event-report template — it rebuilds the full hackathon-style report (participants, cost per model/user/project, BYOK, deploys, upgrades, issues) for any window.</CardDescription>
                        </CardHeader>
                    </Card>
                } else {
                    <Card>
                        <CardContent className="pt-4">
                            <Table>
                                <TableHeader>
                                    <TableRow>
                                        <TableHead>Title</TableHead>
                                        <TableHead>Window (UTC)</TableHead>
                                        <TableHead>Env</TableHead>
                                        <TableHead>Built</TableHead>
                                        <TableHead></TableHead>
                                    </TableRow>
                                </TableHeader>
                                <TableBody>
                                    {for rr in report_rows {
                                        <TableRow key={str(rr["id"])}>
                                            <TableCell className="font-medium">{str(rr["title"])}</TableCell>
                                            <TableCell className="text-xs text-muted-foreground">{str(rr["window"])}</TableCell>
                                            <TableCell><Badge variant="outline">{str(rr["env"])}</Badge></TableCell>
                                            <TableCell className="text-xs text-muted-foreground">{str(rr["built"])}</TableCell>
                                            <TableCell className="text-right"><OpenBtn rid={str(rr["id"])} on_open={open_report} /></TableCell>
                                        </TableRow>
                                    }}
                                </TableBody>
                            </Table>
                        </CardContent>
                    </Card>
                }}
            </div>
        } else {
            <div className="flex flex-col gap-4">
                <div className="flex flex-wrap items-center justify-between gap-2">
                    <div className="flex flex-col">
                        <div className="flex items-center gap-2">
                            <h2 className="text-base font-semibold">{hdr_title}</h2>
                            <Badge variant="outline">{active_env}</Badge>
                            <Badge variant="secondary">snapshot</Badge>
                        </div>
                        <p className="text-xs text-muted-foreground">{hdr_sub}</p>
                    </div>
                    <div className="flex items-center gap-2">
                        <Button variant="ghost" size="sm" onClick={back}>← All reports</Button>
                        <Button variant="outline" size="sm" onClick={rebuild} disabled={building}>{rebuild_btn_label}</Button>
                        <Button variant="outline" size="sm" onClick={gen_ai} disabled={generating}>{gen_btn_label}</Button>
                        <Button variant="outline" size="sm" onClick={share} disabled={sharing}>{share_btn_label}</Button>
                        <Button variant="outline" size="sm" onClick={export_md}>⬇ Export .md</Button>
                        <Button variant="ghost" size="sm" className="text-muted-foreground hover:text-destructive" onClick={remove}>Delete</Button>
                    </div>
                </div>
                {if gen_error != "" {
                    <p className="text-xs text-destructive">AI insights: {gen_error}</p>
                }}
                {if share_url != "" {
                    <div className="flex flex-wrap items-center gap-2 rounded-md border border-border bg-muted/30 px-3 py-2">
                        <span className="text-[11px] font-medium">Public link (emails masked, snapshot only):</span>
                        <Input readOnly className="h-7 max-w-md flex-1 text-xs" value={share_url} />
                    </div>
                }}

                {if len(failed_checks) > 0 {
                    <div className="rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-xs text-destructive">
                        {for (ci, fc) in enumerate(failed_checks) {
                            <p key={"chk" + str(ci)}>{str(fc["txt"])}</p>
                        }}
                    </div>
                } elif checks_ok_text != "" {
                    <p className="text-[11px] text-muted-foreground">{checks_ok_text}</p>
                }}

                {if building {
                    <div className="grid grid-cols-12 gap-4">
                        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><Skeleton className="h-32 w-full" /></div>
                        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><Skeleton className="h-32 w-full" /></div>
                        <div className="col-span-12"><Skeleton className="h-48 w-full" /></div>
                    </div>
                } else {
                    <div className="grid grid-cols-12 gap-4">
                        {for fr in secs {
                            <SectionBlock key={str(fr["id"])} fr={fr} />
                        }}
                    </div>
                }}
            </div>
        }}
    </div>;
}
