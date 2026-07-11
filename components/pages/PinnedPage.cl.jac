# My Dashboard — the tiles the user pinned from the Ask page. Each pin is a RECIPE
# (metric key or generated SQL), re-run live on load for the current env/range, so
# the numbers are never a frozen snapshot. Pins live in the user's server graph
# (metrics_sv pin_* endpoints), so they follow the account across browsers.
sv import from ...metrics_sv { run_pinned, pin_list, pin_remove }
import from ..dash.DynamicTile { DynamicTile }
import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..ui.button { Button }
import from ..ui.skeleton { Skeleton }

def _span(chart: str) -> str {
    if chart == "stat" or chart == "gauge" {
        return "col-span-12 sm:col-span-6 lg:col-span-3";
    }
    if chart == "table" or chart == "retention" or chart == "stackbar" {
        return "col-span-12";
    }
    return "col-span-12 lg:col-span-6";
}

def UnpinBtn(idx: int, on_unpin: Callable[[int], None]) -> JsxElement {
    def h(e: MouseEvent) {
        on_unpin(idx);
    }
    return <Button size="sm" variant="ghost" className="h-6 px-2 text-xs text-muted-foreground hover:text-destructive" onClick={h}>✕ Unpin</Button>;
}

def:pub PinnedPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has pins: list[dict] = [];
    has tiles: list[dict] = [];
    has loading: bool = True;

    async def load() {
        ps = (await pin_list()) as list[dict];
        pins = ps;
        if len(ps) == 0 {
            tiles = [];
            loading = False;
            return;
        }
        loading = True;
        res = await run_pinned(ps, env, date_from, date_to);
        tiles = res as list[dict];
        loading = False;
    }
    async can with (env, date_from, date_to, refresh_n) entry {
        await load();
    }

    # Remove the pin from the server graph (fire-and-forget); UI updates optimistically.
    async def do_remove(pin_id: str) -> None {
        try {
            await pin_remove(pin_id);
        } except Exception as e {
            return;
        }
    }
    # Unpin by index: drop from the server graph + both parallel lists optimistically.
    def unpin(idx: int) -> None {
        p = pins[idx] as dict;
        do_remove(str(p["id"]));
        np = [];
        nt = [];
        j = 0;
        for pp in pins {
            if j != idx {
                np = np + [pp];
            }
            j = j + 1;
        }
        j = 0;
        for tt in tiles {
            if j != idx {
                nt = nt + [tt];
            }
            j = j + 1;
        }
        pins = np;
        tiles = nt;
    }

    return <div className="flex flex-col gap-4">
        {if loading {
            <div className="grid grid-cols-12 gap-4">
                <div className="col-span-12 sm:col-span-6 lg:col-span-3"><Skeleton className="h-32 w-full" /></div>
                <div className="col-span-12 sm:col-span-6 lg:col-span-3"><Skeleton className="h-32 w-full" /></div>
                <div className="col-span-12 lg:col-span-6"><Skeleton className="h-32 w-full" /></div>
            </div>
        }}
        {if (not loading) and (len(tiles) == 0) {
            <Card className="w-full">
                <CardHeader>
                    <CardTitle className="text-base">No pinned tiles yet</CardTitle>
                    <CardDescription className="text-xs">Go to <span className="font-medium">Ask (AI builder)</span>, build something, and click <span className="font-medium">📌 Pin</span> on a tile. It'll show up here with live data for the selected environment and date range.</CardDescription>
                </CardHeader>
            </Card>
        }}
        {if (not loading) and (len(tiles) > 0) {
            <div className="grid grid-cols-12 gap-4">
                {for (idx, t) in enumerate(tiles) {
                    <div key={"p" + str(idx)} className={_span(str(t["chart"]))}>
                        <div className="flex flex-col gap-1">
                            <div className="flex justify-end">
                                <UnpinBtn idx={idx} on_unpin={unpin} />
                            </div>
                            <DynamicTile chart={str(t["chart"])} title={str(t["title"])} data={t["data"]} loading={False} />
                        </div>
                    </div>
                }}
            </div>
        }}
    </div>;
}
