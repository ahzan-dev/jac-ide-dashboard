# AI-first builder (v0, registry-only). One adaptive chat: a concrete question
# builds tiles from verified metrics; a vague one gets a clarifying question back
# ("discussion" emerges, no separate mode). Hybrid — the 11 static pages stay.
sv import from ...metrics_sv { ai_build, search_history, suggest_next, thread_list, thread_get, thread_save, thread_delete, pin_add }
import from ..dash.DynamicTile { DynamicTile }
import from ..dash.util { fmt_num }
import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..ui.button { Button }
import from ..ui.input { Input }

glob SUGGESTIONS: list[str] = [
    "How many new signups this period?",
    "Show the AI success rate over time",
    "What are the top reasons AI requests fail?",
    "Which features get used the most?",
    "How reliable are project previews?",
    "Walk me through the new-user activation funnel"
];

# Wider tiles for charts that need room; compact for single numbers.
def _span(chart: str) -> str {
    if chart == "stat" or chart == "gauge" {
        return "col-span-12 sm:col-span-6 lg:col-span-3";
    }
    if chart == "table" or chart == "retention" or chart == "stackbar" {
        return "col-span-12";
    }
    return "col-span-12 lg:col-span-6";
}

# A suggestion chip; wraps the callback so its own text is closed over on click.
def Chip(text: str, on_pick: Callable[[str], None]) -> JsxElement {
    def handle(e: MouseEvent) {
        on_pick(text);
    }
    return <Button variant="outline" size="sm" className="h-auto whitespace-normal py-1.5 text-left text-xs font-normal" onClick={handle}>{text}</Button>;
}

# Tiered "what to explore next": deeper (drill-down) → related → different (blind spots).
# NB: rendered INLINE in AskPage (not via a sub-component) — a local component rendering
# another local component compiled to a `__jacJsx is not defined` crash in this jac build.
def _tier(sugg: dict, key: str) -> list {
    if not sugg {
        return [];
    }
    v = sugg[key];
    if not v {
        return [];
    }
    return v as list;
}
def _has_suggestions(sugg: dict) -> bool {
    return (len(_tier(sugg, "deeper")) + len(_tier(sugg, "related")) + len(_tier(sugg, "different"))) > 0;
}
def _all_suggestions(sugg: dict) -> list {
    return _tier(sugg, "deeper") + _tier(sugg, "related") + _tier(sugg, "different");
}

# "What changed" since the last time this exact question was run (server-diffed).
def _changed_label(ch: dict) -> str {
    if (not ch) or ch["is_new"] {
        return "";
    }
    pv = ch["prev_value"];
    nv = ch["new_value"];
    if (pv is None) or (nv is None) {
        return "";
    }
    pvf = pv as float;
    nvf = nv as float;
    unit = " rows" if (str(ch["kind"]) == "rows") else "";
    if pvf == nvf {
        return "↔ unchanged since last run (" + fmt_num(nvf) + unit + ")";
    }
    arrow = "▲" if nvf > pvf else "▼";
    diff = nvf - pvf;
    sign = "+" if diff >= 0.0 else "";
    return "Since last run: " + fmt_num(pvf) + unit + " " + arrow + " " + fmt_num(nvf) + unit + " (" + sign + fmt_num(diff) + ")";
}

# A clickable past-search row (question + its last headline value).
def RecentRow(row: dict, on_pick: Callable[[str], None]) -> JsxElement {
    def handle(e: MouseEvent) {
        on_pick(str(row["question"]));
    }
    lv = row["last_value"];
    meta = fmt_num(lv) if (lv is not None) else "";
    return <button onClick={handle} className="flex w-full items-center justify-between gap-3 rounded px-2 py-1 text-left text-xs hover:bg-accent">
        <span className="min-w-0 flex-1 truncate">{str(row["question"])}</span>
        <span className="shrink-0 tabular-nums text-muted-foreground">{meta}</span>
    </button>;
}

# Observability: a collapsible "How this was built" panel showing what byLLM chose —
# mode, its reasoning, and the exact metrics (with windows) or env-injected SQL it ran.
# This is how you catch "why is the number different" (e.g. a metric using the picker
# range instead of literally 'today').
def PlanDisclosure(plan: dict) -> JsxElement {
    has open: bool = False;
    def toggle(e: MouseEvent) {
        open = not open;
    }
    mode = str(plan["mode"]) if plan["mode"] else "";
    reasoning = str(plan["reasoning"]) if plan["reasoning"] else "";
    sql = str(plan["sql"]) if plan["sql"] else "";
    mets = (plan["metrics"] as list) if plan["metrics"] else [];
    return <div className="max-w-[85%] self-start">
        <button onClick={toggle} className="text-[11px] text-muted-foreground hover:text-foreground">{("▾ " if open else "▸ ") + "How this was built"}</button>
        {if open {
            <div className="mt-1 flex flex-col gap-1.5 rounded-md border border-border bg-muted/40 p-2.5 text-[11px] leading-relaxed">
                <div><span className="font-medium">Mode:</span> {mode}</div>
                {if reasoning {
                    <div><span className="font-medium">Reasoning:</span> {reasoning}</div>
                }}
                {if len(mets) > 0 {
                    <div className="flex flex-col gap-0.5">
                        <span className="font-medium">Verified metrics used:</span>
                        {for (pi, mm) in enumerate(mets) {
                            <span key={"pm" + str(pi)} className="text-muted-foreground">• {str((mm as dict)["title"]) + " (" + str((mm as dict)["key"]) + ") — window " + str((mm as dict)["window"])}</span>
                        }}
                    </div>
                }}
                {if sql {
                    <div className="flex flex-col gap-0.5">
                        <span className="font-medium">Query (env-filtered, as executed):</span>
                        <pre className="overflow-x-auto whitespace-pre-wrap rounded bg-background p-2 font-mono text-[10px] leading-snug">{sql}</pre>
                    </div>
                }}
            </div>
        }}
    </div>;
}

# A built tile with a Pin control; pins the tile's recipe to the dashboard (localStorage).
def PinnableTile(tile: dict, on_pin: Callable[[dict], None]) -> JsxElement {
    has pinned: bool = False;
    def do_pin(e: MouseEvent) {
        on_pin(tile["recipe"] as dict);
        pinned = True;
    }
    return <div className="flex flex-col gap-1">
        <div className="flex justify-end">
            <Button size="sm" variant="ghost" className="h-6 gap-1 px-2 text-xs text-muted-foreground" onClick={do_pin} disabled={pinned}>{"📌 Pinned" if pinned else "📌 Pin"}</Button>
        </div>
        <DynamicTile chart={str(tile["chart"])} title={str(tile["title"])} data={tile["data"]} loading={False} />
    </div>;
}

# A conversation row in the thread rail. active = the currently-open thread.
def ThreadRow(thread: dict, active: bool, on_open: Callable[[str], None], on_del: Callable[[str], None]) -> JsxElement {
    def open_h(e: MouseEvent) {
        on_open(str(thread["id"]));
    }
    def del_h(e: MouseEvent) {
        on_del(str(thread["id"]));
    }
    tone = "bg-accent font-medium text-foreground" if active else "text-muted-foreground hover:bg-accent/50";
    return <div className={"group flex w-full items-center gap-1 rounded px-2 py-1.5 text-xs " + tone}>
        <button onClick={open_h} className="min-w-0 flex-1 truncate text-left" title={str(thread["title"])}>{str(thread["title"])}</button>
        <button onClick={del_h} className="shrink-0 px-1 text-muted-foreground opacity-0 hover:text-destructive group-hover:opacity-100" title="Delete conversation">✕</button>
    </div>;
}

def:pub AskPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has messages: list[dict] = [];
    has draft: str = "";
    has busy: bool = False;
    has recent: list[dict] = [];         # saved searches, newest first (server, per-user)
    has suggestions: dict = {};          # tiered "what next": {deeper, related, different}
    has show_recent: bool = False;       # the recent-searches dropdown (mid-chat access)
    has thread_id: str = "";             # current conversation ("" = new/unsaved)
    has threads: list[dict] = [];        # thread list for the rail (newest first)

    # Refresh the history + suggestions (on mount and after every search).
    async def load_meta() -> None {
        try {
            recent = (await search_history()) as list[dict];
        } except Exception as e {
            recent = [];
        }
        try {
            suggestions = (await suggest_next()) as dict;
        } except Exception as e {
            suggestions = {};
        }
    }
    # Thread persistence — snapshot (frozen messages), per-user server graph.
    async def load_threads() -> list {
        try {
            tl = (await thread_list()) as list[dict];
            threads = tl;
            return tl;
        } except Exception as e {
            threads = [];
            return [];
        }
    }
    async def do_open(tid: str) -> None {
        try {
            r = (await thread_get(tid)) as dict;
            messages = r["messages"] as list[dict];
            thread_id = tid;
            show_recent = False;
        } except Exception as e {
            return;
        }
    }
    async def drop_thread(tid: str) -> None {
        try {
            await thread_delete(tid);
        } except Exception as e {
            return;
        }
        if tid == thread_id {
            messages = [];
            thread_id = "";
        }
        await load_threads();
    }
    async def save_thread(msgs: list) -> None {
        title = "New chat";
        for m in msgs {
            md = m as dict;
            if str(md["role"]) == "user" {
                title = str(md["text"])[:48];
                break;
            }
        }
        try {
            r = (await thread_save(thread_id, title, msgs)) as dict;
            thread_id = str(r["id"]);
        } except Exception as e {
            return;
        }
        await load_threads();
    }
    async can with entry {
        await load_meta();
        tl = await load_threads();
        if len(tl) > 0 {
            await do_open(str((tl[0] as dict)["id"]));
        }
    }

    # Core worker: takes the question EXPLICITLY (never re-reads `draft` after a
    # just-committed write — that would read the stale render snapshot).
    async def run_build(q: str) -> None {
        text = q.strip();
        if (not text) or busy {
            return;
        }
        draft = "";
        convo = messages + [{"role": "user", "text": text, "tiles": [], "title": ""}];
        messages = convo;
        busy = True;
        res = await ai_build(text, env, date_from, date_to);
        r = res as dict;
        reply = "";
        tiles = [];
        ttl = "";
        pl = {};
        if r["plan"] {
            pl = r["plan"] as dict;
        }
        if r["answerable"] {
            reply = str(r["reply"]);
            tiles = r["tiles"] as list;
            ttl = str(r["title"]);
        } else {
            reply = str(r["clarify"]);
        }
        ch = {};
        if r["changed"] {
            ch = r["changed"] as dict;
        }
        final_msgs = convo + [{"role": "assistant", "text": reply, "tiles": tiles, "title": ttl, "plan": pl, "changed": ch}];
        messages = final_msgs;
        busy = False;
        await save_thread(final_msgs);
        await load_meta();
    }

    def pick(q: str) -> None {
        run_build(q);
    }
    def new_thread(e: MouseEvent) {
        messages = [];
        thread_id = "";
        draft = "";
        show_recent = False;
    }
    def open_thread(tid: str) -> None {
        do_open(tid);
    }
    def del_thread(tid: str) -> None {
        drop_thread(tid);
    }
    def toggle_recent(e: MouseEvent) {
        show_recent = not show_recent;
    }
    def pick_and_close(q: str) -> None {
        show_recent = False;
        run_build(q);
    }
    async def do_pin(recipe: dict) -> None {
        try {
            await pin_add(recipe);
        } except Exception as e {
            return;
        }
    }
    def pin_tile(recipe: dict) -> None {
        do_pin(recipe);
    }
    def submit() -> None {
        run_build(draft);
    }
    def on_change(e: ChangeEvent) {
        draft = e.target.value;
    }
    def on_key(e: KeyboardEvent) {
        if e.key == "Enter" {
            run_build(draft);
        }
    }

    return <div className="mx-auto flex w-full max-w-5xl gap-4">
        <div className="flex w-48 shrink-0 flex-col gap-2 border-r border-border pr-3">
            <Button size="sm" variant="outline" className="w-full justify-start gap-1 text-xs font-normal" onClick={new_thread}>＋ New thread</Button>
            <div className="flex max-h-[70vh] flex-col gap-0.5 overflow-y-auto">
                {if len(threads) == 0 {
                    <span className="px-2 py-1 text-[11px] text-muted-foreground">No conversations yet</span>
                }}
                {for (thi, th) in enumerate(threads) {
                    <ThreadRow key={"th" + str(thi)} thread={th as dict} active={str((th as dict)["id"]) == thread_id} on_open={open_thread} on_del={del_thread} />
                }}
            </div>
        </div>
        <div className="flex min-w-0 flex-1 flex-col gap-4">
        {if len(messages) == 0 {
            <Card className="w-full">
                <CardHeader className="pb-3">
                    <CardTitle className="text-base">Ask for a dashboard</CardTitle>
                    <CardDescription className="text-xs">Describe what you want to know — I build it from our verified metrics, filtered to the selected environment and date range. If a question is too broad, I'll ask you to narrow it. Try one:</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-4">
                    {if len(recent) > 0 {
                        <div className="flex flex-col gap-1.5">
                            <span className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Recent</span>
                            <div className="flex flex-wrap gap-2">
                                {for (ri, rr) in enumerate(recent) {
                                    if ri < 8 {
                                        <Chip key={"r" + str(ri)} text={str((rr as dict)["question"])} on_pick={pick} />
                                    }
                                }}
                            </div>
                        </div>
                    }}
                    {if _has_suggestions(suggestions) {
                        <div className="flex flex-col gap-1.5">
                            <span className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">✨ Try next</span>
                            <div className="flex flex-wrap gap-2">
                                {for (gi, gs) in enumerate(_all_suggestions(suggestions)) {
                                    <Chip key={"g" + str(gi)} text={str(gs)} on_pick={pick} />
                                }}
                            </div>
                        </div>
                    }}
                    {if (len(recent) == 0) and (not _has_suggestions(suggestions)) {
                        <div className="flex flex-wrap gap-2">
                            {for (si, s) in enumerate(SUGGESTIONS) {
                                <Chip key={"s" + str(si)} text={str(s)} on_pick={pick} />
                            }}
                        </div>
                    }}
                </CardContent>
            </Card>
        }}

        {for (mi, m) in enumerate(messages) {
            <div key={"m" + str(mi)} className="flex flex-col gap-3">
                {if m["role"] == "user" {
                    <div className="max-w-[85%] self-end rounded-lg bg-primary px-3 py-2 text-sm text-primary-foreground">{str(m["text"])}</div>
                } else {
                    <div className="max-w-[85%] self-start whitespace-pre-line rounded-lg bg-muted px-3 py-2 text-sm text-foreground">{str(m["text"])}</div>
                }}
                {if (m["role"] == "assistant") and (len(m["tiles"] as list[dict]) > 0) {
                    <div className="grid grid-cols-12 gap-3">
                        {for (ti, t) in enumerate(m["tiles"] as list[dict]) {
                            <div key={"m" + str(mi) + "t" + str(ti)} className={_span(str(t["chart"]))}>
                                <PinnableTile tile={t} on_pin={pin_tile} />
                            </div>
                        }}
                    </div>
                }}
                {if (m["role"] == "assistant") and _changed_label(m["changed"] as dict) {
                    <div className="max-w-[85%] self-start text-[11px] font-medium text-muted-foreground">{_changed_label(m["changed"] as dict)}</div>
                }}
                {if (m["role"] == "assistant") and (m["plan"] as dict)["mode"] {
                    <PlanDisclosure plan={m["plan"] as dict} />
                }}
            </div>
        }}

        {if busy {
            <div className="self-start rounded-lg bg-muted px-3 py-2 text-sm text-muted-foreground">Building…</div>
        }}

        {if (len(messages) > 0) and (not busy) and _has_suggestions(suggestions) {
            <div className="flex flex-col gap-3 rounded-lg border border-border bg-muted/20 p-3.5">
                <span className="text-xs font-medium text-foreground">What to explore next</span>
                {if len(_tier(suggestions, "deeper")) > 0 {
                    <div className="flex flex-col gap-1.5">
                        <span className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Go deeper</span>
                        <div className="flex flex-wrap gap-2">
                            {for (di, ds) in enumerate(_tier(suggestions, "deeper")) {
                                <Chip key={"td" + str(di)} text={str(ds)} on_pick={pick} />
                            }}
                        </div>
                    </div>
                }}
                {if len(_tier(suggestions, "related")) > 0 {
                    <div className="flex flex-col gap-1.5">
                        <span className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Related</span>
                        <div className="flex flex-wrap gap-2">
                            {for (ei, es) in enumerate(_tier(suggestions, "related")) {
                                <Chip key={"tr" + str(ei)} text={str(es)} on_pick={pick} />
                            }}
                        </div>
                    </div>
                }}
                {if len(_tier(suggestions, "different")) > 0 {
                    <div className="flex flex-col gap-1.5">
                        <span className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Explore other areas</span>
                        <div className="flex flex-wrap gap-2">
                            {for (fi, fs) in enumerate(_tier(suggestions, "different")) {
                                <Chip key={"tf" + str(fi)} text={str(fs)} on_pick={pick} />
                            }}
                        </div>
                    </div>
                }}
            </div>
        }}

        {if (len(messages) > 0) and (len(recent) > 0) {
            <div className="flex flex-col gap-1">
                <button onClick={toggle_recent} className="self-start text-[11px] text-muted-foreground hover:text-foreground">{("▾ " if show_recent else "▸ ") + "Recent searches (" + str(len(recent)) + ")"}</button>
                {if show_recent {
                    <div className="flex max-h-52 flex-col gap-0.5 overflow-auto rounded-md border border-border bg-muted/30 p-1.5">
                        {for (hi, hh) in enumerate(recent) {
                            <RecentRow key={"h" + str(hi)} row={hh as dict} on_pick={pick_and_close} />
                        }}
                    </div>
                }}
            </div>
        }}

        <div className="sticky bottom-0 flex items-center gap-2 border-t border-border bg-background pt-3">
            <Input value={draft} onChange={on_change} onKeyDown={on_key} placeholder="Ask about your product metrics…" className="flex-1" disabled={busy} />
            <Button onClick={submit} disabled={busy}>{"Building…" if busy else "Send"}</Button>
        </div>
        </div>
    </div>;
}
