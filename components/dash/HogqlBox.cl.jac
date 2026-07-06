sv import from ...metrics_sv { run_adhoc }
import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..ui.textarea { Textarea }
import from ..ui.button { Button }
import from ..ui.table { Table, TableHeader, TableBody, TableRow, TableHead, TableCell }

def:pub HogqlBox() -> JsxElement {
    has sql: str = "SELECT event, count() AS n FROM events\nWHERE timestamp > now() - INTERVAL 7 DAY AND (properties.environment = 'prod' OR properties.$host IN ('jachammer.ai','www.jachammer.ai','jac-builder.jaseci.org'))\nGROUP BY event ORDER BY n DESC LIMIT 20";
    has cols: list = [];
    has rows: list = [];
    has err: str = "";
    has running: bool = False;
    has ran: bool = False;

    async def run() {
        running = True;
        err = "";
        res = await run_adhoc(sql);
        if res {
            e = res["error"];
            if e {
                err = str(e);
                cols = [];
                rows = [];
            } else {
                cols = res["columns"] as list;
                rows = res["rows"] as list;
            }
        }
        running = False;
        ran = True;
    }
    def on_change(e: ChangeEvent) {
        sql = e.target.value;
    }

    return <Card className="w-full">
        <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium">Free-form HogQL (read-only)</CardTitle>
            <CardDescription className="text-xs">Admin escape hatch — runs server-side against PostHog project 425465. SELECT / WITH only; the phx_ key never reaches the browser.</CardDescription>
            <CardDescription className="text-xs">Unlike the tiles, ad-hoc SQL is NOT auto-filtered by environment — keep the prod clause in your WHERE to match tile numbers.</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-3">
            <Textarea value={sql} onChange={on_change} className="min-h-28 font-mono text-xs" spellCheck={False} />
            <div className="flex items-center gap-2">
                <Button onClick={run} disabled={running}>{"Running…" if running else "Run query"}</Button>
                {if ran and (not err) {
                    <span className="text-xs text-muted-foreground">{str(len(rows)) + " rows"}</span>
                }}
            </div>
            {if err {
                <p className="text-xs text-destructive">{err}</p>
            }}
            {if ran and (not err) and len(rows) > 0 {
                <div className="max-h-96 overflow-auto rounded-md border border-border">
                    <Table>
                        <TableHeader>
                            <TableRow>
                                {for (ci, c) in enumerate(cols) {
                                    <TableHead key={"h" + str(ci)} className="text-xs">{str(c)}</TableHead>
                                }}
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {for (ri, r) in enumerate(rows) {
                                <TableRow key={"r" + str(ri)}>
                                    {for (ci, cell) in enumerate(r) {
                                        <TableCell key={str(ci)} className="text-xs tabular-nums">{str(cell)}</TableCell>
                                    }}
                                </TableRow>
                            }}
                        </TableBody>
                    </Table>
                </div>
            }}
        </CardContent>
    </Card>;
}
