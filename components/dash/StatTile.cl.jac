import from ..ui.card { Card, CardHeader, CardTitle, CardContent }
import from ..ui.skeleton { Skeleton }
import from ..ui.tooltip { Tooltip, TooltipTrigger, TooltipContent }
import from ..ui.chart { ChartContainer }
import from "recharts" { AreaChart, Area }
import from .util { fmt_val, slope_of, delta_badge }

# Presentational KPI tile: receives its metric result (`data`) from the page's batch fetch.
def:pub StatTile(title: str, data: any, loading: bool) -> JsxElement {
    m = data["meta"] if data else None;
    definition = str(m["definition"]) if m else "";
    unit = str(m["unit"]) if m else "";
    caveat = str(m["caveat"]) if m else "";
    good_up = (m["good_when_up"] as bool) if m else True;
    value = data["value"] if data else None;
    series = (data["series"] as list) if data else [];
    delta = data["delta"] if data else None;
    err = data["error"] if data else "";
    # Prefer compare-to-previous delta; fall back to the weekly slope when there's no prev window.
    sl = {"arrow": "", "cls": "flat", "txt": ""};
    if delta is not None {
        sl = delta_badge(delta, good_up);
    } elif len(series) > 2 {
        sl = slope_of(series, good_up);
    }

    return <Card className="w-full">
        <CardHeader className="pb-2">
            <div className="flex items-start justify-between gap-2">
                <div className="flex items-center gap-1.5">
                    <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
                    <Tooltip>
                        <TooltipTrigger className="grid size-4 place-items-center rounded-full border border-border text-[10px] leading-none text-muted-foreground">?</TooltipTrigger>
                        <TooltipContent className="max-w-xs">{definition}</TooltipContent>
                    </Tooltip>
                </div>
                {if (not loading) and sl["txt"] {
                    <span className={"text-xs font-medium tabular-nums " + ("text-success" if sl["cls"] == "good" else ("text-destructive" if sl["cls"] == "bad" else "text-muted-foreground"))}>
                        {str(sl["arrow"]) + " " + str(sl["txt"])}
                    </span>
                }}
            </div>
        </CardHeader>
        <CardContent className="flex flex-col gap-2">
            {if loading {
                <Skeleton className="h-9 w-24" />
            } else {
                <div className="text-3xl font-semibold tabular-nums">{fmt_val(value, unit)}</div>
            }}
            {if (not loading) and len(series) > 1 {
                <ChartContainer config={{"y": {"label": title, "color": "var(--chart-1)"}}} className="aspect-auto h-12 w-full">
                    <AreaChart data={series} margin={{"top": 2, "right": 0, "bottom": 0, "left": 0}}>
                        <Area dataKey="y" type="monotone" stroke="var(--color-y)" fill="var(--color-y)" fillOpacity={0.15} strokeWidth={1.5} dot={False} />
                    </AreaChart>
                </ChartContainer>
            }}
            {if err {
                <p className="text-xs text-destructive">n/a — {str(err)}</p>
            }}
            {if caveat {
                <p className="text-[11px] leading-tight text-muted-foreground">{caveat}</p>
            }}
        </CardContent>
    </Card>;
}
