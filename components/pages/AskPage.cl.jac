# AI-first builder (v0, registry-only). One adaptive chat: a concrete question
# builds tiles from verified metrics; a vague one gets a clarifying question back
# ("discussion" emerges, no separate mode). Hybrid — the 11 static pages stay.
sv import from ...metrics_sv { ai_build }
import from ..dash.DynamicTile { DynamicTile }
import from ..dash.util { pins_add }
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

def:pub AskPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has messages: list[dict] = [];
    has draft: str = "";
    has busy: bool = False;

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
        messages = convo + [{"role": "assistant", "text": reply, "tiles": tiles, "title": ttl, "plan": pl}];
        busy = False;
    }

    def pick(q: str) -> None {
        run_build(q);
    }
    def pin_tile(recipe: dict) -> None {
        pins_add(recipe);
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

    return <div className="mx-auto flex w-full max-w-4xl flex-col gap-4">
        {if len(messages) == 0 {
            <Card className="w-full">
                <CardHeader className="pb-3">
                    <CardTitle className="text-base">Ask for a dashboard</CardTitle>
                    <CardDescription className="text-xs">Describe what you want to know — I build it from our verified metrics, filtered to the selected environment and date range. If a question is too broad, I'll ask you to narrow it. Try one:</CardDescription>
                </CardHeader>
                <CardContent>
                    <div className="flex flex-wrap gap-2">
                        {for (si, s) in enumerate(SUGGESTIONS) {
                            <Chip key={"s" + str(si)} text={str(s)} on_pick={pick} />
                        }}
                    </div>
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
                {if (m["role"] == "assistant") and (m["plan"] as dict)["mode"] {
                    <PlanDisclosure plan={m["plan"] as dict} />
                }}
            </div>
        }}

        {if busy {
            <div className="self-start rounded-lg bg-muted px-3 py-2 text-sm text-muted-foreground">Building…</div>
        }}

        <div className="sticky bottom-0 flex items-center gap-2 border-t border-border bg-background pt-3">
            <Input value={draft} onChange={on_change} onKeyDown={on_key} placeholder="Ask about your product metrics…" className="flex-1" disabled={busy} />
            <Button onClick={submit} disabled={busy}>{"Building…" if busy else "Send"}</Button>
        </div>
    </div>;
}
