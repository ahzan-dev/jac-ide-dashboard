# AI-first builder (v0, registry-only). One adaptive chat: a concrete question
# builds tiles from verified metrics; a vague one gets a clarifying question back
# ("discussion" emerges, no separate mode). Hybrid — the 11 static pages stay.
sv import from ...metrics_sv { ai_build, search_history, suggest_next, thread_list, thread_get, thread_save, thread_delete, pin_add, report_from_thread, ask_feedback }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { PinIcon, File01Icon, SparklesIcon, PlusSignIcon, Cancel01Icon, Mic01Icon, ThumbsUpIcon, ThumbsDownIcon }
import from ..dash.DynamicTile { DynamicTile }
import from ..dash.util { fmt_num }
import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..ui.button { Button }
import from ..ui.input { Input }

# Synchronous (non-reactive) guards — `has` state writes are async, so a rapid
# double-Enter used to see busy=False twice and fire ai_build twice (creating a
# DUPLICATE thread), and switching threads mid-build let the finished build
# clobber the newly opened conversation. `busy` stays for the UI; this is truth.
glob ASK_LOCK: dict = {"busy": False, "gen": 0};

# The live SpeechRecognition instance (module state — survives re-renders, not reactive).
glob MIC: dict = {"rec": None};

glob SUGGESTIONS: list[str] = [
    "How many new signups this period?",
    "Show the AI success rate over time",
    "What are the top reasons AI requests fail?",
    "Which features get used the most?",
    "How reliable are project previews?",
    "Walk me through the new-user activation funnel"
];

# Bound the thread snapshot: tables can carry up to 200 rows per tile, and every
# save rewrites the whole message list into the Thread node — cap stored rows so
# long conversations don't balloon the per-thread document. Copies, never mutates
# (the same dicts are being rendered).
def _slim_messages(msgs: list) -> list {
    out = [];
    for m in msgs {
        md = m as dict;
        tiles = (md.get("tiles", []) or []) as list;
        if len(tiles) == 0 {
            out = out + [md];
            continue;
        }
        nts = [];
        for t in tiles {
            td = t as dict;
            dd = (td.get("data", {}) or {}) as dict;
            rows = (dd.get("rows", []) or []) as list;
            if len(rows) > 50 {
                nts = nts + [{**td, "data": {**dd, "rows": rows[:50]}}];
            } else {
                nts = nts + [td];
            }
        }
        out = out + [{**md, "tiles": nts}];
    }
    return out;
}

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
            <Button size="sm" variant="ghost" className="h-6 gap-1 px-2 text-xs text-muted-foreground" onClick={do_pin} disabled={pinned}><HugeiconsIcon icon={PinIcon} className="size-3" /> {"Pinned" if pinned else "Pin"}</Button>
        </div>
        <DynamicTile chart={str(tile["chart"])} title={str(tile["title"])} data={tile["data"]} loading={False} />
    </div>;
}

# A conversation row in the thread rail. active = the currently-open thread.
# Delete is TWO-step (✕ → "sure?") — it's irreversible and used to fire instantly.
# NB: rows MUST be keyed by thread ID (never list index) and the message loop keys
# include thread_id — index keys made React reuse a deleted row's armed=True state
# for the NEXT thread ("sure?" appearing unclicked) and leaked pinned state across
# thread switches.
def ThreadRow(thread: dict, active: bool, on_open: Callable[[str], None], on_del: Callable[[str], None]) -> JsxElement {
    has armed: bool = False;

    def open_h(e: MouseEvent) {
        armed = False;
        on_open(str(thread["id"]));
    }
    def del_h(e: MouseEvent) {
        if armed {
            on_del(str(thread["id"]));
            return;
        }
        armed = True;
    }
    tone = "bg-accent font-medium text-foreground" if active else "text-muted-foreground hover:bg-accent/50";
    del_cls = "shrink-0 px-1 text-destructive opacity-100" if armed else "shrink-0 px-1 text-muted-foreground opacity-0 hover:text-destructive group-hover:opacity-100";
    return <div className={"group flex w-full items-center gap-1 rounded px-2 py-1.5 text-xs " + tone}>
        <button onClick={open_h} className="min-w-0 flex-1 truncate text-left" title={str(thread["title"])}>{str(thread["title"])}</button>
        <button onClick={del_h} className={del_cls} title={"Click again to delete" if armed else "Delete conversation"}>{if armed { <span>sure?</span> } else { <HugeiconsIcon icon={Cancel01Icon} className="size-3" /> }}</button>
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
    has compiling: bool = False;         # thread -> report in flight
    has compiled_msg: str = "";          # result note after compiling
    has listening: bool = False;         # mic capture active
    has mic_err: str = "";               # mic unavailable / permission message

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
        ASK_LOCK["gen"] = (ASK_LOCK["gen"] as int) + 1;
        try {
            r = (await thread_get(tid)) as dict;
            messages = r["messages"] as list[dict];
            thread_id = tid;
            show_recent = False;
        } except Exception {
            return;
        }
    }
    async def drop_thread(tid: str) -> None {
        try {
            await thread_delete(tid);
        } except Exception {
            return;
        }
        if tid == thread_id {
            ASK_LOCK["gen"] = (ASK_LOCK["gen"] as int) + 1;
            messages = [];
            thread_id = "";
        }
        await load_threads();
    }
    # Saves to an EXPLICIT thread id (never re-reads reactive state after an await —
    # that's the stale-snapshot trap that cross-wrote conversations). Returns the id.
    async def save_thread(tid: str, msgs: list) -> str {
        title = "New chat";
        for m in msgs {
            md = m as dict;
            if str(md["role"]) == "user" {
                title = str(md["text"])[:48];
                break;
            }
        }
        rid = "";
        try {
            slim = _slim_messages(msgs);
            r = (await thread_save(tid, title, slim)) as dict;
            rid = str(r["id"]);
        } except Exception {
            return "";
        }
        await load_threads();
        return rid;
    }
    async can with entry {
        await load_meta();
        tl = await load_threads();
        if len(tl) > 0 {
            await do_open(str((tl[0] as dict)["id"]));
        }
    }

    # Core worker: takes the question EXPLICITLY (never re-reads `draft` after a
    # just-committed write — that would read the stale render snapshot). Guarded by
    # the synchronous ASK_LOCK (double-submit) and a generation counter (a build
    # that finishes AFTER the user switched/deleted threads must not clobber the
    # view — its answer still saves to the thread it belongs to).
    async def run_build(q: str) -> None {
        text = q.strip();
        if (not text) or (ASK_LOCK["busy"] as bool) {
            return;
        }
        ASK_LOCK["busy"] = True;
        gen = ASK_LOCK["gen"] as int;
        tid = thread_id;
        draft = "";
        convo = messages + [{"role": "user", "text": text, "tiles": [], "title": ""}];
        messages = convo;
        busy = True;
        reply = "Something went wrong running this question — please try again.";
        tiles = [];
        ttl = "";
        pl = {};
        ch = {};
        ok = False;
        try {
            res = await ai_build(text, env, date_from, date_to);
            r = res as dict;
            ok = True;
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
            if r["changed"] {
                ch = r["changed"] as dict;
            }
        } except Exception {
            ok = False;
        }
        final_msgs = convo + [{"role": "assistant", "text": reply, "tiles": tiles, "title": ttl, "plan": pl, "changed": ch}];
        same_view = (ASK_LOCK["gen"] as int) == gen;
        if same_view {
            messages = final_msgs;
        }
        busy = False;
        if ok {
            new_id = await save_thread(tid, final_msgs);
            if ((ASK_LOCK["gen"] as int) == gen) and (tid == "") and (new_id != "") {
                thread_id = new_id;
            }
            await load_meta();
        }
        ASK_LOCK["busy"] = False;
    }

    def pick(q: str) -> None {
        run_build(q);
    }
    def new_thread(e: MouseEvent) {
        ASK_LOCK["gen"] = (ASK_LOCK["gen"] as int) + 1;
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
    # R2: compile this thread into a snapshot report (questions/answers as text,
    # tiles as live recipes) scoped to the current env + date range.
    async def compile_report(e: MouseEvent) {
        if (thread_id == "") or busy or compiling {
            return;
        }
        compiling = True;
        compiled_msg = "";
        try {
            res = (await report_from_thread(thread_id, "", env, date_from, date_to)) as dict;
            err = str(res.get("error", ""));
            if err != "" {
                compiled_msg = "Couldn't compile: " + err;
            } else {
                compiled_msg = "Saved to Reports: \"" + str(res.get("title", "")) + "\" — open the Reports page to build & share it.";
            }
        } except Exception as e2 {
            compiled_msg = "Couldn't compile this thread into a report.";
        }
        compiling = False;
    }
    # Thumbs feedback on an answer — stores question + planner choices server-side
    # (the prompt-optimization loop: down-votes carry the exact request/response).
    async def send_feedback(mi: int, rating: str) -> None {
        md = messages[mi] as dict;
        if md["fb"] {
            return;
        }
        qtext = "";
        j = mi - 1;
        while j >= 0 {
            pj = messages[j] as dict;
            if str(pj["role"]) == "user" {
                qtext = str(pj["text"]);
                break;
            }
            j = j - 1;
        }
        pl2 = (md.get("plan", {}) or {}) as dict;
        fb_entry = {"rating": rating, "question": qtext, "reply": str(md.get("text", "")),
                    "mode": str(pl2.get("mode", "")), "keys": str(pl2.get("metrics", "")),
                    "sql": str(pl2.get("sql", ""))};
        try {
            await ask_feedback(fb_entry);
        } except Exception {
            return;
        }
        nm = [];
        k2 = 0;
        for m2 in messages {
            if k2 == mi {
                nm = nm + [{**(m2 as dict), "fb": rating}];
            } else {
                nm = nm + [m2];
            }
            k2 = k2 + 1;
        }
        messages = nm;
        if thread_id != "" {
            _ = await save_thread(thread_id, nm);
        }
    }

    # Voice input (Web Speech API) — fills the draft; the user reviews and sends.
    def toggle_mic(e: MouseEvent) {
        if listening {
            r0 = MIC["rec"];
            if r0 {
                r0.stop();
            }
            listening = False;
            return;
        }
        SR = window.SpeechRecognition or window.webkitSpeechRecognition;
        if not SR {
            mic_err = "Voice input isn't supported in this browser — try Chrome.";
            return;
        }
        mic_err = "";
        r = new(SR);
        r.lang = "en-US";
        r.interimResults = True;
        r.continuous = False;
        r.onresult = lambda (ev: any) {
            t = "";
            i = 0;
            while i < ev.results.length {
                t = t + ev.results[i][0].transcript;
                i = i + 1;
            }
            draft = t;
        };
        r.onend = lambda {
            listening = False;
        };
        r.onerror = lambda (ev: any) {
            listening = False;
            mic_err = "Mic error: " + str(ev.error);
        };
        MIC["rec"] = r;
        listening = True;
        r.start();
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

    compile_btn_label = "Compiling…" if compiling else "Compile into report";

    return <div className="mx-auto flex w-full max-w-5xl gap-4">
        <div className="flex w-48 shrink-0 flex-col gap-2 border-r border-border pr-3">
            <Button size="sm" variant="outline" className="w-full justify-start gap-1 text-xs font-normal" onClick={new_thread}><HugeiconsIcon icon={PlusSignIcon} className="size-3" /> New thread</Button>
            <div className="flex max-h-[70vh] flex-col gap-0.5 overflow-y-auto">
                {if len(threads) == 0 {
                    <span className="px-2 py-1 text-[11px] text-muted-foreground">No conversations yet</span>
                }}
                {for th in threads {
                    <ThreadRow key={str((th as dict)["id"])} thread={th as dict} active={str((th as dict)["id"]) == thread_id} on_open={open_thread} on_del={del_thread} />
                }}
            </div>
        </div>
        <div className="flex min-w-0 flex-1 flex-col gap-4">
        {if (len(messages) > 0) and (thread_id != "") {
            <div className="flex flex-wrap items-center justify-end gap-2">
                {if compiled_msg != "" {
                    <span className="text-[11px] text-muted-foreground">{compiled_msg}</span>
                }}
                <Button variant="outline" size="sm" className="h-7 gap-1 text-xs" onClick={compile_report} disabled={compiling}><HugeiconsIcon icon={File01Icon} className="size-3" /> {compile_btn_label}</Button>
            </div>
        }}
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
                            <span className="flex items-center gap-1 text-[11px] font-medium uppercase tracking-wide text-muted-foreground"><HugeiconsIcon icon={SparklesIcon} className="size-3" /> Try next</span>
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
            <div key={"m" + thread_id + "_" + str(mi)} className="flex flex-col gap-3">
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
                {if m["role"] == "assistant" {
                    <div className="flex items-center gap-1 self-start">
                        <button className={"rounded p-1 " + ("text-emerald-600" if m["fb"] == "up" else "text-muted-foreground opacity-50 hover:opacity-100")} onClick={lambda (e2: MouseEvent) { send_feedback(mi, "up"); }} disabled={bool(m["fb"])} title="Good answer"><HugeiconsIcon icon={ThumbsUpIcon} className="size-3.5" /></button>
                        <button className={"rounded p-1 " + ("text-destructive" if m["fb"] == "down" else "text-muted-foreground opacity-50 hover:opacity-100")} onClick={lambda (e2: MouseEvent) { send_feedback(mi, "down"); }} disabled={bool(m["fb"])} title="Bad answer — logs the question + generated query for review"><HugeiconsIcon icon={ThumbsDownIcon} className="size-3.5" /></button>
                    </div>
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

        {if mic_err != "" {
            <p className="text-[11px] text-destructive">{mic_err}</p>
        }}
        <div className="sticky bottom-0 flex items-center gap-2 border-t border-border bg-background pt-3">
            <Input value={draft} onChange={on_change} onKeyDown={on_key} placeholder={"Listening…" if listening else "Ask about your product metrics…"} className="flex-1" disabled={busy} />
            <Button variant="outline" size="icon" className={"shrink-0 " + ("animate-pulse border-destructive text-destructive" if listening else "text-muted-foreground")} onClick={toggle_mic} disabled={busy} title={"Stop listening" if listening else "Speak your question"}><HugeiconsIcon icon={Mic01Icon} className="size-4" /></Button>
            <Button onClick={submit} disabled={busy}>{"Building…" if busy else "Send"}</Button>
        </div>
        </div>
    </div>;
}
