import from ..ui.card { Card, CardHeader, CardTitle, CardContent }
import from ..dash.ChartTiles { Banner }
import from ..dash.DataDictionary { DataDictionary }

def InfoCard(title: str, lines: list) -> JsxElement {
    return <Card className="h-full w-full">
        <CardHeader className="pb-2"><CardTitle className="text-sm font-medium">{title}</CardTitle></CardHeader>
        <CardContent>
            <ul className="flex flex-col gap-1.5">
                {for ln in lines {
                    <li key={str(ln)} className="text-xs text-muted-foreground">• {str(ln)}</li>
                }}
            </ul>
        </CardContent>
    </Card>;
}

glob PRIVACY_LINES: list = [
    "Inputs & code masked (data-ph-mask, code, pre, .monaco-editor)",
    "Session replay masked on sensitive nodes",
    "Prompt text is never captured (so no prompt clustering)",
    "Identified users only for product metrics; opt-out honored"
];
glob DATA_LINES: list = [
    "Autocapture limited to [data-ph-track] (click/submit only)",
    "Event retention per PostHog project 425465",
    "Export via API + jacpack",
    "$host and environment are materialized (fast prod filtering)"
];
glob ACCESS_LINES: list = [
    "Admin email allowlist gates the whole app (internal only)",
    "No user roles / RBAC model exists — admin vs everyone",
    "phx_ READ key is SERVER-ONLY; the browser calls walkers, never PostHog"
];

def:pub SettingsPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    return <div className="grid grid-cols-12 gap-4">
        <div className="col-span-12"><Banner text={"The controls at the top apply everywhere: the environment selector (currently: " + env + "), the date range, and a Refresh button (forces fresh data instead of the up-to-10-minute-old cached version). By default, every page shows only real production traffic, with test and dev data filtered out."} /></div>

        <div className="col-span-12 md:col-span-4"><InfoCard title="Privacy & masking" lines={PRIVACY_LINES} /></div>
        <div className="col-span-12 md:col-span-4"><InfoCard title="Data controls" lines={DATA_LINES} /></div>
        <div className="col-span-12 md:col-span-4"><InfoCard title="Access" lines={ACCESS_LINES} /></div>

        <div className="col-span-12"><DataDictionary /></div>
    </div>;
}
