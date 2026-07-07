sv import from ...metrics_sv { ai_insights }
import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..ui.button { Button }

def:pub InsightsBox(data: dict, loading: bool) -> JsxElement {
    has text: str = "";
    has reason: str = "";
    has running: bool = False;
    has ran: bool = False;

    async def run() {
        running = True;
        reason = "";
        text = "";
        res = await ai_insights(data);
        if res {
            if res["available"] {
                text = str(res["text"]);
            } else {
                reason = str(res["reason"]);
            }
        }
        running = False;
        ran = True;
    }

    return <Card className="w-full">
        <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium">AI insights (generated)</CardTitle>
            <CardDescription className="text-xs">An LLM writes a short narrative over this page's metrics. Generated on demand — verify against the tiles before acting.</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-3">
            <div>
                <Button onClick={run} disabled={running or loading}>{"Generating…" if running else "Generate insights"}</Button>
            </div>
            {if ran and text {
                <p className="whitespace-pre-line text-sm text-foreground">{text}</p>
            }}
            {if ran and (not text) and reason {
                <p className="text-xs text-muted-foreground">{"Not available — " + reason}</p>
            }}
        </CardContent>
    </Card>;
}
