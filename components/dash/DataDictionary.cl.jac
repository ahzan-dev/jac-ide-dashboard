import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..ui.input { Input }
import from ..ui.table { Table, TableHeader, TableBody, TableRow, TableHead, TableCell }
import from ..ui.badge { Badge }

# The CORE event contract (from .docs/posthog/EVENT_CATALOG.md). status: green live · yellow pending · red missing.
glob EVENTS: list = [
    {"cat": "Acquisition", "event": "auth_signup_succeeded", "props": "method, source", "powers": "Signups, activation, retention cohort", "status": "🟢"},
    {"cat": "Acquisition", "event": "auth_succeeded", "props": "method, is_new_user", "powers": "Active signed-in users", "status": "🟢"},
    {"cat": "Acquisition", "event": "auth_sso_clicked", "props": "provider", "powers": "Channel / provider split", "status": "🟡"},
    {"cat": "Activation", "event": "app_loaded", "props": "—", "powers": "Active-user heartbeat, time-spent", "status": "🟢"},
    {"cat": "Activation", "event": "ide_opened", "props": "—", "powers": "WAU / returning / lifecycle", "status": "🟢"},
    {"cat": "Activation", "event": "project_created", "props": "source", "powers": "Projects, activation funnel", "status": "🟢"},
    {"cat": "AI engine", "event": "ai_message_sent", "props": "prompt_length, task_category, project_id", "powers": "Gen requested, funnel, task-mix", "status": "🟢"},
    {"cat": "AI engine", "event": "ai_message_completed", "props": "duration_ms, files_changed, tool_call_count, response_length", "powers": "North Star, TTFV, gen-success, latency", "status": "🟢"},
    {"cat": "AI engine", "event": "ai_message_failed", "props": "reason, at_phase, duration_ms", "powers": "Failure breakdown", "status": "🟢"},
    {"cat": "AI engine", "event": "ai_user_aborted", "props": "duration_ms", "powers": "Give-up signal", "status": "🟢"},
    {"cat": "AI engine", "event": "ai_message_reverted", "props": "—", "powers": "Quality proxy (until generation_kept)", "status": "🟢"},
    {"cat": "AI engine", "event": "ai_response_rated", "props": "rating, message_id, files_changed", "powers": "AI Quality: helpful-rate, quality-by-model", "status": "🔴"},
    {"cat": "AI engine", "event": "ai_issue_reported", "props": "category, message_id", "powers": "Feedback / roadmap signal", "status": "🔴"},
    {"cat": "AI engine", "event": "generation_kept", "props": "message_id, project_id", "powers": "Acceptance (the real 'kept' signal)", "status": "🔴"},
    {"cat": "Preview", "event": "preview_start_requested", "props": "was_prepared", "powers": "Reliability denominator", "status": "🟢"},
    {"cat": "Preview", "event": "preview_ready", "props": "duration_ms", "powers": "North Star, reliability numerator", "status": "🟢"},
    {"cat": "Preview", "event": "preview_start_failed", "props": "reason, phase", "powers": "Reliability failures", "status": "🟢"},
    {"cat": "Deploy", "event": "deploy_sandbox_clicked", "props": "—", "powers": "Deploy intent", "status": "🟢"},
    {"cat": "Deploy", "event": "deploy_sandbox_succeeded", "props": "status", "powers": "Deploy success (sandbox)", "status": "🟡"},
    {"cat": "Deploy", "event": "deploy_production_clicked", "props": "has_subdomain, has_domain, has_cert_email", "powers": "Deploy intent (production)", "status": "🟢"},
    {"cat": "Deploy", "event": "deploy_production_succeeded", "props": "status, has_custom_domain", "powers": "Deploy success (production)", "status": "🟡"},
    {"cat": "Monetization", "event": "upgrade_checkout_clicked", "props": "plan", "powers": "Upgrade intent (leading revenue)", "status": "🟢"},
    {"cat": "Monetization", "event": "topup_checkout_clicked", "props": "pack", "powers": "Top-up intent", "status": "🟢"},
    {"cat": "Cost", "event": "ai_generation_metered", "props": "cost_usd, model, project_id, run_id", "powers": "Inference spend, cost/gen, margin (server-side)", "status": "🟡"},
    {"cat": "Feature", "event": "git_commit_succeeded", "props": "—", "powers": "Git adoption", "status": "🟢"},
    {"cat": "Feature", "event": "github_connect_succeeded", "props": "—", "powers": "GitHub adoption", "status": "🟢"},
    {"cat": "Feature", "event": "project_shared", "props": "—", "powers": "Community / share adoption", "status": "🟢"},
    {"cat": "Feature", "event": "export_downloaded", "props": "—", "powers": "Export adoption, churn-risk cohort", "status": "🟢"},
    {"cat": "Super-prop", "event": "environment", "props": "prod / dev / preview / local", "powers": "The env filter on EVERY query", "status": "🟡"},
    {"cat": "Person", "event": "plan", "props": "free / builder / pro", "powers": "Tier segment on every chart", "status": "🟡"}
];

def:pub DataDictionary() -> JsxElement {
    has query: str = "";

    def on_search(e: ChangeEvent) {
        query = e.target.value;
    }

    q = query.lower();
    rows = [];
    for ev in EVENTS {
        blob = (str(ev["event"]) + " " + str(ev["cat"]) + " " + str(ev["props"]) + " " + str(ev["powers"])).lower();
        if (not q) or (q in blob) {
            rows = rows + [ev];
        }
    }

    return <Card className="w-full">
        <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium">Data dictionary</CardTitle>
            <CardDescription className="text-xs">The 26 CORE events the dashboard depends on. 🟢 live · 🟡 pending deploy/config · 🔴 not yet instrumented. Full contract: .docs/posthog/EVENT_CATALOG.md.</CardDescription>
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
                                <TableCell className="text-center text-xs">{str(ev["status"])}</TableCell>
                            </TableRow>
                        }}
                    </TableBody>
                </Table>
            </div>
        </CardContent>
    </Card>;
}
