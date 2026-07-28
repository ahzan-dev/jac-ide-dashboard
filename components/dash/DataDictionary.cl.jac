sv import from ...metrics_sv { event_usage, event_liveness }
import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..ui.input { Input }
import from ..ui.table { Table, TableHeader, TableBody, TableRow, TableHead, TableCell }
import from ..ui.badge { Badge }

# The CORE event contract (from .docs/posthog/EVENT_CATALOG.md).
# Event rows carry NO hardcoded status — 🟢/🔴 is DERIVED from live prod counts
# (event_liveness, last 14d) so the dictionary can't drift from reality again
# (it used to mark ai_response_rated 🔴 while Feedback showed a live helpful rate).
# Only the two non-event rows (super-prop / person-prop) keep a manual status.
glob EVENTS: list = [
    {"cat": "Acquisition", "event": "auth_signup_succeeded", "props": "method, source, signup_trigger", "powers": "Signups, activation, retention cohort, trigger breakdown"},
    {"cat": "Acquisition", "event": "auth_succeeded", "props": "method, is_new_user", "powers": "Active signed-in users"},
    {"cat": "Acquisition", "event": "auth_sso_clicked", "props": "provider", "powers": "Channel / provider split"},
    {"cat": "Activation", "event": "app_loaded", "props": "—", "powers": "Active-user heartbeat, time-spent"},
    {"cat": "Activation", "event": "ide_opened", "props": "—", "powers": "WAU / returning / lifecycle"},
    {"cat": "Activation", "event": "ide_session_ended", "props": "duration_active_ms", "powers": "Typical session length (focused time)"},
    {"cat": "Activation", "event": "project_created", "props": "source", "powers": "Projects, activation funnel"},
    {"cat": "AI engine", "event": "ai_message_sent", "props": "prompt_length, task_category, project_id, conversation_id, turn_number", "powers": "Gen requested, funnel, task-mix"},
    {"cat": "AI engine", "event": "ai_message_completed", "props": "duration_ms, files_changed, model, conversation_id, turn_number", "powers": "North Star, TTFV, gen-success, latency, model mix, first-try"},
    {"cat": "AI engine", "event": "ai_message_failed", "props": "reason, at_phase, duration_ms", "powers": "Failure breakdown"},
    {"cat": "AI engine", "event": "ai_user_aborted", "props": "duration_ms", "powers": "Give-up signal"},
    {"cat": "AI engine", "event": "ai_message_reverted", "props": "—", "powers": "Acceptance signal (kept = not reverted)"},
    {"cat": "AI engine", "event": "ai_message_blocked_quota", "props": "—", "powers": "Quota friction (issues log)"},
    {"cat": "AI engine", "event": "ai_response_rated", "props": "rating, message_id, files_changed", "powers": "AI Quality: helpful-rate, ratings trend"},
    {"cat": "AI engine", "event": "ai_response_edited", "props": "—", "powers": "Manual-edit acceptance signal (Impact)"},
    {"cat": "AI engine", "event": "ai_issue_reported", "props": "category, message_id", "powers": "Feedback / roadmap signal"},
    {"cat": "AI engine", "event": "ai_turn_transcript", "props": "prompt, response", "powers": "Transcript analytics — flag-gated (JAC_STORE_AI_TRANSCRIPTS unset on prod)"},
    {"cat": "Preview", "event": "preview_start_requested", "props": "was_prepared", "powers": "Reliability denominator"},
    {"cat": "Preview", "event": "preview_ready", "props": "duration_ms", "powers": "North Star, reliability numerator"},
    {"cat": "Preview", "event": "preview_start_failed", "props": "reason, phase", "powers": "Reliability failures"},
    {"cat": "Deploy", "event": "deploy_sandbox_clicked", "props": "—", "powers": "Deploy intent"},
    {"cat": "Deploy", "event": "deploy_sandbox_succeeded", "props": "status", "powers": "Deploy success (sandbox)"},
    {"cat": "Deploy", "event": "deploy_sandbox_failed", "props": "reason", "powers": "Deploy failures (sandbox)"},
    {"cat": "Deploy", "event": "deploy_production_clicked", "props": "has_subdomain, has_domain, has_cert_email", "powers": "Deploy intent (production)"},
    {"cat": "Deploy", "event": "deploy_production_succeeded", "props": "status, has_custom_domain", "powers": "Deploy success (production)"},
    {"cat": "Deploy", "event": "deploy_production_failed", "props": "reason", "powers": "Deploy failures (production)"},
    {"cat": "Monetization", "event": "upgrade_checkout_clicked", "props": "plan", "powers": "Upgrade intent (leading revenue)"},
    {"cat": "Monetization", "event": "upgrade_checkout_succeeded", "props": "plan, plan_from, interval, amount_usd, is_first_upgrade", "powers": "Paid conversions, upgrade revenue (Revenue page)"},
    {"cat": "Monetization", "event": "upgrade_checkout_failed", "props": "reason", "powers": "Checkout friction (issues log)"},
    {"cat": "Monetization", "event": "topup_checkout_clicked", "props": "pack", "powers": "Top-up intent"},
    {"cat": "Monetization", "event": "topup_checkout_succeeded", "props": "pack, amount_usd", "powers": "Top-up revenue"},
    {"cat": "Monetization", "event": "subscription_canceled", "props": "mrr_delta", "powers": "MRR churn (blocked until this ships)"},
    {"cat": "Monetization", "event": "subscription_downgraded", "props": "plan, plan_from", "powers": "Downgrade signal"},
    {"cat": "Cost", "event": "ai_generation_metered", "props": "cost_usd, model, project_id, run_id, byok", "powers": "Inference spend, cost/gen, margin (server-side)"},
    {"cat": "Feature", "event": "git_commit_succeeded", "props": "—", "powers": "Git adoption"},
    {"cat": "Feature", "event": "github_connect_succeeded", "props": "—", "powers": "GitHub adoption"},
    {"cat": "Feature", "event": "project_shared", "props": "—", "powers": "Community / share adoption"},
    {"cat": "Feature", "event": "export_downloaded", "props": "—", "powers": "Export adoption, churn-risk cohort"}
];

# Non-event rows — properties can't be liveness-probed by event name, so these
# keep a manual status (env tagging shipped to prod 2026-07 → 🟢).
glob PROP_ROWS: list = [
    {"cat": "Super-prop", "event": "environment", "props": "prod / dev / preview / local", "powers": "The env filter on EVERY query", "status": "🟢"},
    {"cat": "Person", "event": "plan", "props": "free / builder / pro", "powers": "Tier segment on every chart", "status": "🟢"}
];

def:pub DataDictionary() -> JsxElement {
    has query: str = "";
    has usage: dict = {};
    has live: dict = {};
    has live_err: bool = False;

    async can with entry {
        names = [];
        for ev in EVENTS {
            names = names + [str(ev["event"])];
        }
        res = await event_usage(names);
        if res {
            usage = res as dict;
        }
        lv = await event_liveness(names);
        lvd = lv as dict;
        if "error" in lvd {
            live_err = True;
        }
        if "counts" in lvd {
            live = lvd["counts"] as dict;
        }
    }

    def on_search(e: ChangeEvent) {
        query = e.target.value;
    }

    q = query.lower();
    rows = [];
    for ev in EVENTS {
        blob = (str(ev["event"]) + " " + str(ev["cat"]) + " " + str(ev["props"]) + " " + str(ev["powers"])).lower();
        if (not q) or (q in blob) {
            cnt = len(usage.get(str(ev["event"]), []) as list);
            mtxt = "—" if cnt == 0 else str(cnt);
            n14 = (live.get(str(ev["event"]), 0) or 0) as int;
            status = "…";
            if live_err {
                status = "?";
            } elif live {
                status = "🟢" if n14 > 0 else "🔴";
            }
            row = {"cat": ev["cat"], "event": ev["event"], "props": ev["props"], "powers": ev["powers"], "status": status, "n14": n14, "mtxt": mtxt};
            rows = rows + [row];
        }
    }
    for pv in PROP_ROWS {
        blob2 = (str(pv["event"]) + " " + str(pv["cat"]) + " " + str(pv["props"]) + " " + str(pv["powers"])).lower();
        if (not q) or (q in blob2) {
            rows = rows + [{"cat": pv["cat"], "event": pv["event"], "props": pv["props"], "powers": pv["powers"], "status": pv["status"], "n14": -1, "mtxt": "—"}];
        }
    }

    # Derived, not hand-counted. Status legend matches the derivation.
    caption = ("The " + str(len(EVENTS)) + " CORE events the dashboard depends on."
        + (" Status DERIVED live: 🟢 = seen in prod in the last 14 days · 🔴 = zero prod events (14d)." if not live_err else " Status probe unavailable right now (?).")
        + " '14d' = prod event count behind the status. Full contract: .docs/posthog/EVENT_CATALOG.md."
        + " · 'Metrics' = live count of registry metrics using each event.");

    return <Card className="w-full">
        <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium">Data dictionary</CardTitle>
            <CardDescription className="text-xs">{caption}</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-3">
            <Input value={query} onChange={on_search} placeholder="Search events, properties, what they power…" className="h-8 max-w-sm text-xs" />
            <div className="max-h-[28rem] overflow-auto rounded-md border border-border">
                <Table>
                    <TableHeader>
                        <TableRow>
                            <TableHead className="text-xs">Event</TableHead>
                            <TableHead className="text-xs">Category</TableHead>
                            <TableHead className="text-xs">Key properties</TableHead>
                            <TableHead className="text-xs">Powers</TableHead>
                            <TableHead className="text-center text-xs">Metrics</TableHead>
                            <TableHead className="text-center text-xs">14d</TableHead>
                            <TableHead className="text-center text-xs">Status</TableHead>
                        </TableRow>
                    </TableHeader>
                    <TableBody>
                        {if len(rows) == 0 {
                            <TableRow><TableCell className="text-xs text-muted-foreground">No matching events.</TableCell></TableRow>
                        }}
                        {for ev in rows {
                            <TableRow key={str(ev["event"])}>
                                <TableCell className="whitespace-nowrap font-mono text-xs">{str(ev["event"])}</TableCell>
                                <TableCell className="text-xs"><Badge variant="outline">{str(ev["cat"])}</Badge></TableCell>
                                <TableCell className="text-xs text-muted-foreground">{str(ev["props"])}</TableCell>
                                <TableCell className="text-xs text-muted-foreground">{str(ev["powers"])}</TableCell>
                                <TableCell className="text-center text-xs tabular-nums">{str(ev["mtxt"])}</TableCell>
                                <TableCell className="text-center text-xs tabular-nums">{"—" if (ev["n14"] as int) < 0 else str(ev["n14"])}</TableCell>
                                <TableCell className="text-center text-xs">{str(ev["status"])}</TableCell>
                            </TableRow>
                        }}
                    </TableBody>
                </Table>
            </div>
        </CardContent>
    </Card>;
}
