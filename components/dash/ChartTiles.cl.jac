import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..ui.skeleton { Skeleton }
import from ..ui.tooltip { Tooltip, TooltipTrigger, TooltipContent }
import from ..ui.badge { Badge }
import from ..ui.progress { Progress }
import from ..ui.table { Table, TableHeader, TableBody, TableRow, TableHead, TableCell }
import from ..ui.chart { ChartContainer, ChartTooltip, ChartTooltipContent }
import from "recharts" {
    LineChart, Line, BarChart, Bar, AreaChart, Area, XAxis, YAxis, CartesianGrid,
    PieChart, Pie, Cell
}
import from .util { fmt_num, pct1, short_date, axis_tick, delta_badge }

# dataviz validated categorical palette (fixed order, never cycled)
glob VIZ: list = ["var(--viz-1)", "var(--viz-2)", "var(--viz-3)", "var(--viz-4)", "var(--viz-5)", "var(--viz-6)"];

# ---- meta helpers (data = a metric result object from the page batch) ------
def _def(data: any) -> str {
    m = data["meta"] if data else None;
    return str(m["definition"]) if m else "";
}
def _win(data: any) -> str {
    m = data["meta"] if data else None;
    return str(m["window"]) if m else "";
}
def _cav(data: any) -> str {
    m = data["meta"] if data else None;
    return str(m["caveat"]) if m else "";
}
def _err(data: any) -> str {
    e = data["error"] if data else "";
    return str(e) if e else "";
}

# ---- shared card frame -----------------------------------------------------
def Frame(title: str, data: any, children: any = None) -> JsxElement {
    return <Card className="flex h-full w-full flex-col">
        <CardHeader className="pb-2">
            <div className="flex items-center gap-1.5">
                <CardTitle className="text-sm font-medium">{title}</CardTitle>
                <Tooltip>
                    <TooltipTrigger className="grid size-4 place-items-center rounded-full border border-border text-[10px] leading-none text-muted-foreground">?</TooltipTrigger>
                    <TooltipContent className="max-w-xs">{_def(data)}</TooltipContent>
                </Tooltip>
            </div>
            {if _win(data) {
                <CardDescription className="text-xs">{_win(data)}</CardDescription>
            }}
        </CardHeader>
        <CardContent className="flex flex-1 flex-col gap-2">
            {children}
            {if _err(data) {
                <p className="text-xs text-destructive">n/a — {_err(data)}</p>
            }}
            {if _cav(data) {
                <p className="text-[11px] leading-tight text-muted-foreground">{_cav(data)}</p>
            }}
        </CardContent>
    </Card>;
}

# ============================ Line chart tile ==============================
def:pub LineTile(title: str, data: any, loading: bool) -> JsxElement {
    series = (data["series"] as list) if data else [];
    return <Frame title={title} data={data}>
        {if loading {
            <Skeleton className="h-40 w-full" />
        } else {
            <ChartContainer config={{"y": {"label": title, "color": "var(--chart-1)"}}} className="aspect-auto h-44 w-full">
                <LineChart data={series} margin={{"top": 8, "right": 8, "bottom": 0, "left": -6}}>
                    <CartesianGrid vertical={False} strokeDasharray="3 3" />
                    <XAxis dataKey="x" tickLine={False} axisLine={False} minTickGap={28} fontSize={10} tickFormatter={short_date} />
                    <YAxis tickLine={False} axisLine={False} width={40} fontSize={10} />
                    <ChartTooltip content={<ChartTooltipContent />} />
                    <Line dataKey="y" type="monotone" stroke="var(--color-y)" strokeWidth={2} dot={False} />
                </LineChart>
            </ChartContainer>
        }}
    </Frame>;
}

# ============================ Area chart tile (volume trend) ==============
def:pub AreaTile(title: str, data: any, loading: bool) -> JsxElement {
    series = (data["series"] as list) if data else [];
    return <Frame title={title} data={data}>
        {if loading {
            <Skeleton className="h-40 w-full" />
        } else {
            <ChartContainer config={{"y": {"label": title, "color": "var(--chart-1)"}}} className="aspect-auto h-44 w-full">
                <AreaChart data={series} margin={{"top": 8, "right": 8, "bottom": 0, "left": -6}}>
                    <CartesianGrid vertical={False} strokeDasharray="3 3" />
                    <XAxis dataKey="x" tickLine={False} axisLine={False} minTickGap={28} fontSize={10} tickFormatter={short_date} />
                    <YAxis tickLine={False} axisLine={False} width={40} fontSize={10} />
                    <ChartTooltip content={<ChartTooltipContent />} />
                    <Area dataKey="y" type="monotone" stroke="var(--color-y)" strokeWidth={2} fill="var(--color-y)" fillOpacity={0.18} dot={False} />
                </AreaChart>
            </ChartContainer>
        }}
    </Frame>;
}

# ============================ Meter tile (single ratio) ===================
# dataviz canonical form for "a single ratio against a limit": a same-ramp track
# (robust; recharts 3 radial-gauge scaling is unreliable).
def:pub GaugeTile(title: str, data: any, loading: bool) -> JsxElement {
    val = data["value"] if data else None;
    m = data["meta"] if data else None;
    good_up = (m["good_when_up"] as bool) if m else True;
    db = delta_badge(data["delta"] if data else None, good_up);
    v = 0.0;
    if val is not None {
        v = (val as float);
        if v < 0.0 { v = 0.0; }
        if v > 100.0 { v = 100.0; }
    }
    return <Frame title={title} data={data}>
        {if loading {
            <Skeleton className="h-24 w-full" />
        } else {
            <div className="flex flex-1 flex-col justify-center gap-3 py-1">
                <div className="flex items-baseline justify-between gap-2">
                    <div className="text-4xl font-semibold tabular-nums">{"n/a" if (val is None) else pct1(val)}</div>
                    {if db["txt"] {
                        <span className={"text-xs font-medium tabular-nums " + ("text-success" if db["cls"] == "good" else ("text-destructive" if db["cls"] == "bad" else "text-muted-foreground"))}>
                            {str(db["arrow"]) + " " + str(db["txt"])}
                        </span>
                    }}
                </div>
                <div className="h-2.5 w-full overflow-hidden rounded-full bg-muted">
                    <div className="h-full rounded-full" style={{"width": str(v) + "%", "backgroundColor": "var(--chart-1)"}}></div>
                </div>
            </div>
        }}
    </Frame>;
}

# ============================ Donut tile (composition) ====================
def:pub DonutTile(title: str, data: any, loading: bool) -> JsxElement {
    raw = (data["rows"] as list) if (data and (not loading)) else [];
    pdata = [];
    i = 0;
    for r in raw {
        pdata = pdata + [{"name": str(r[0]), "value": (r[1] as float), "fill": VIZ[i % 6]}];
        i = i + 1;
    }
    return <Frame title={title} data={data}>
        {if loading {
            <Skeleton className="h-40 w-full" />
        } else {
            <div className="flex flex-col items-center gap-3">
                {if len(pdata) == 0 {
                    <p className="text-xs text-muted-foreground">No data in this window.</p>
                }}
                <ChartContainer config={{}} className="aspect-square h-36">
                    <PieChart>
                        <ChartTooltip content={<ChartTooltipContent />} />
                        <Pie data={pdata} dataKey="value" nameKey="name" innerRadius={42} outerRadius={72} paddingAngle={2} strokeWidth={2}>
                            {for c in pdata {
                                <Cell key={str(c["name"])} fill={c["fill"]} />
                            }}
                        </Pie>
                    </PieChart>
                </ChartContainer>
                <div className="flex flex-wrap justify-center gap-x-3 gap-y-1">
                    {for c in pdata {
                        <div key={str(c["name"])} className="flex items-center gap-1.5 text-xs">
                            <span className="size-2 rounded-full" style={{"backgroundColor": c["fill"]}}></span>
                            <span className="text-muted-foreground">{str(c["name"]) + " · " + fmt_num(c["value"])}</span>
                        </div>
                    }}
                </div>
            </div>
        }}
    </Frame>;
}

# ============================ Stacked bar tile (multi-series) =============
def:pub StackBarTile(title: str, data: any, loading: bool) -> JsxElement {
    cols = (data["columns"] as list) if (data and (not loading)) else [];
    raw = (data["rows"] as list) if (data and (not loading)) else [];

    # series = every column after the first; precompute name+color and the recharts data
    bars = [];
    si = 0;
    for c in cols {
        if si > 0 {
            bars = bars + [{"name": str(c), "color": VIZ[(si - 1) % 6]}];
        }
        si = si + 1;
    }
    cdata = [];
    for r in raw {
        pt = {"x": str(r[0])};
        ci = 0;
        for c in cols {
            if ci > 0 {
                pt[str(c)] = r[ci];
            }
            ci = ci + 1;
        }
        cdata = cdata + [pt];
    }

    return <Frame title={title} data={data}>
        {if loading {
            <Skeleton className="h-44 w-full" />
        } else {
            <div className="flex flex-col gap-2">
                <ChartContainer config={{}} className="aspect-auto h-44 w-full">
                    <BarChart data={cdata} margin={{"top": 8, "right": 8, "bottom": 0, "left": -6}}>
                        <CartesianGrid vertical={False} strokeDasharray="3 3" />
                        <XAxis dataKey="x" tickLine={False} axisLine={False} minTickGap={20} fontSize={10} tickFormatter={short_date} />
                        <YAxis tickLine={False} axisLine={False} width={40} fontSize={10} />
                        <ChartTooltip content={<ChartTooltipContent />} />
                        {for b in bars {
                            <Bar key={b["name"]} dataKey={b["name"]} stackId="a" fill={b["color"]} />
                        }}
                    </BarChart>
                </ChartContainer>
                <div className="flex flex-wrap justify-center gap-x-3 gap-y-1">
                    {for b in bars {
                        <div key={b["name"]} className="flex items-center gap-1.5 text-xs">
                            <span className="size-2 rounded-full" style={{"backgroundColor": b["color"]}}></span>
                            <span className="text-muted-foreground">{b["name"]}</span>
                        </div>
                    }}
                </div>
            </div>
        }}
    </Frame>;
}

# ============================ Vertical bar chart tile =====================
def:pub VBarTile(title: str, data: any, loading: bool) -> JsxElement {
    series = (data["series"] as list) if data else [];
    return <Frame title={title} data={data}>
        {if loading {
            <Skeleton className="h-40 w-full" />
        } else {
            <ChartContainer config={{"y": {"label": title, "color": "var(--chart-1)"}}} className="aspect-auto h-44 w-full">
                <BarChart data={series} margin={{"top": 8, "right": 8, "bottom": 0, "left": -6}}>
                    <CartesianGrid vertical={False} strokeDasharray="3 3" />
                    <XAxis dataKey="x" tickLine={False} axisLine={False} minTickGap={12} fontSize={10} tickFormatter={axis_tick} />
                    <YAxis tickLine={False} axisLine={False} width={40} fontSize={10} />
                    <ChartTooltip content={<ChartTooltipContent />} />
                    <Bar dataKey="y" fill="var(--color-y)" radius={[3, 3, 0, 0]} />
                </BarChart>
            </ChartContainer>
        }}
    </Frame>;
}

# ============================ Generic data table tile =====================
def _hdr(col: str) -> str {
    c = col.replace("_pct", " %").replace("_", " ");
    return c;
}
def _cell(v: any, col: str) -> str {
    if col.endswith("pct") or ("%" in col) {
        return pct1(v);
    }
    return fmt_num(v);
}

def:pub TableTile(title: str, data: any, loading: bool) -> JsxElement {
    cols = (data["columns"] as list) if (data and (not loading)) else [];
    raw = (data["rows"] as list) if (data and (not loading)) else [];

    # Precompute header + formatted cells in the body (plain Jac) — keep JSX slots trivial
    # to avoid jac2js miscompiling enumerate + cross-indexing inside slots.
    headers = [];
    for c in cols {
        headers = headers + [_hdr(str(c))];
    }
    frows = [];
    for r in raw {
        cells = [];
        i = 0;
        for cell in r {
            val = str(cell) if i == 0 else _cell(cell, str(cols[i]));
            align = "font-medium" if i == 0 else "text-right tabular-nums";
            cells = cells + [{"k": str(i), "v": val, "a": align}];
            i = i + 1;
        }
        frows = frows + [{"k": str(r[0]), "cells": cells}];
    }

    return <Frame title={title} data={data}>
        {if loading {
            <Skeleton className="h-40 w-full" />
        } else {
            <div className="overflow-x-auto">
                <Table>
                    <TableHeader>
                        <TableRow>
                            {for h in headers {
                                <TableHead key={h} className="text-xs">{h}</TableHead>
                            }}
                        </TableRow>
                    </TableHeader>
                    <TableBody>
                        {if len(frows) == 0 {
                            <TableRow><TableCell className="text-xs text-muted-foreground">No data in this window.</TableCell></TableRow>
                        }}
                        {for fr in frows {
                            <TableRow key={fr["k"]}>
                                {for cc in fr["cells"] {
                                    <TableCell key={cc["k"]} className={"text-xs " + cc["a"]}>{cc["v"]}</TableCell>
                                }}
                            </TableRow>
                        }}
                    </TableBody>
                </Table>
            </div>
        }}
    </Frame>;
}

# ============================ Honesty banner ==============================
def:pub Banner(text: str) -> JsxElement {
    return <Card className="w-full">
        <CardContent className="py-3">
            <p className="text-xs text-muted-foreground">{text}</p>
        </CardContent>
    </Card>;
}

# ============================ Static info tile (no metric) =================
def:pub StaticStat(title: str, value: str, note: str, definition: str) -> JsxElement {
    return <Card className="flex h-full w-full flex-col">
        <CardHeader className="pb-2">
            <div className="flex items-center gap-1.5">
                <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
                {if definition {
                    <Tooltip>
                        <TooltipTrigger className="grid size-4 place-items-center rounded-full border border-border text-[10px] leading-none text-muted-foreground">?</TooltipTrigger>
                        <TooltipContent className="max-w-xs">{definition}</TooltipContent>
                    </Tooltip>
                }}
            </div>
        </CardHeader>
        <CardContent className="flex flex-col gap-2">
            <div className="text-3xl font-semibold tabular-nums text-muted-foreground">{value}</div>
            {if note {
                <p className="text-[11px] leading-tight text-muted-foreground">{note}</p>
            }}
        </CardContent>
    </Card>;
}

# ============================ Horizontal bars tile =========================
def:pub BarsTile(title: str, data: any, loading: bool) -> JsxElement {
    rows = (data["rows"] as list) if data else [];
    maxv = 1.0;
    for r in rows {
        rv = r[1] as float;
        if rv > maxv { maxv = rv; }
    }
    return <Frame title={title} data={data}>
        {if loading {
            <Skeleton className="h-40 w-full" />
        } else {
            <div className="flex flex-col gap-2 pt-1">
                {if len(rows) == 0 {
                    <p className="text-xs text-muted-foreground">No data in this window.</p>
                }}
                {for r in rows {
                    <div key={str(r[0])} className="flex flex-col gap-1">
                        <div className="flex items-center justify-between gap-2 text-xs">
                            <span className="min-w-0 flex-1 truncate text-muted-foreground" title={str(r[0])}>{str(r[0])}</span>
                            <span className="shrink-0 tabular-nums">{fmt_num(r[1])}</span>
                        </div>
                        <Progress value={(r[1] as float) / maxv * 100.0} className="h-2" />
                    </div>
                }}
            </div>
        }}
    </Frame>;
}

# ============================ Funnel tile ==================================
def:pub FunnelTile(title: str, data: any, loading: bool) -> JsxElement {
    rows = (data["rows"] as list) if data else [];
    first = (rows[0][1] as float) if rows else 0.0;
    return <Frame title={title} data={data}>
        {if loading {
            <Skeleton className="h-40 w-full" />
        } else {
            <div className="flex flex-col gap-2 pt-1">
                {for r in rows {
                    <div key={str(r[0])} className="flex flex-col gap-1">
                        <div className="flex items-center justify-between text-xs">
                            <span className="text-muted-foreground">{str(r[0])}</span>
                            <span className="tabular-nums">{fmt_num(r[1])}</span>
                        </div>
                        <Progress value={((r[1] as float) / first * 100.0) if first else 0.0} className="h-2.5" />
                    </div>
                }}
            </div>
        }}
    </Frame>;
}

# ============================ Retention heatmap tile =======================
def:pub RetentionTile(title: str, data: any, loading: bool) -> JsxElement {
    rows = (data["rows"] as list) if data else [];
    weeks = [0, 1, 2, 3, 4, 5];
    return <Frame title={title} data={data}>
        {if loading {
            <Skeleton className="h-40 w-full" />
        } else {
            <div className="overflow-x-auto">
                <Table>
                    <TableHeader>
                        <TableRow>
                            <TableHead className="text-xs">Cohort</TableHead>
                            <TableHead className="text-xs">N</TableHead>
                            {for w in weeks {
                                <TableHead key={"h" + str(w)} className={"text-center text-xs " + ("text-destructive" if w == 4 else "")}>{"W" + str(w)}</TableHead>
                            }}
                        </TableRow>
                    </TableHeader>
                    <TableBody>
                        {if len(rows) == 0 {
                            <TableRow><TableCell className="text-xs text-muted-foreground">No cohorts in this environment.</TableCell></TableRow>
                        }}
                        {for r in rows {
                            <TableRow key={str(r[0])}>
                                <TableCell className="whitespace-nowrap text-xs">{str(r[0])[:10]}</TableCell>
                                <TableCell className="text-xs tabular-nums">
                                    {fmt_num(r[1])}
                                    {if (r[1] as float) < 15.0 {
                                        <Badge variant="outline" className="ml-1 px-1 py-0 text-[9px]">⚠</Badge>
                                    }}
                                </TableCell>
                                {for w in weeks {
                                    <TableCell key={str(r[0]) + "w" + str(w)} className="text-center text-xs tabular-nums" style={{"backgroundColor": "rgba(57,135,229," + str(0.06 + (r[2 + w] as float) / 140.0) + ")"}}>
                                        {pct1(r[2 + w])}
                                    </TableCell>
                                }}
                            </TableRow>
                        }}
                    </TableBody>
                </Table>
            </div>
        }}
    </Frame>;
}
