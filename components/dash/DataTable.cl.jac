# DataTable — the one table body used by every table tile: case-insensitive
# search, click-to-sort headers (numeric-aware, asc/desc toggle), and prev/next
# pagination with a rows-per-page picker. Controls appear only when the table is
# big enough to need them (search/pagination hidden under 11 rows).
#
# jac2js discipline (all bitten before — see CLAUDE.md):
#   * every variable assigned BEFORE any branch that reassigns it (TDZ),
#   * JSX slots trivial — filtering/sorting/formatting precomputed in the body,
#   * named callback components (HeadBtn / PageBtn), never inline lambdas,
#   * no inline `{if cond {"str"}}` labels — strings precomputed.
import from ..ui.table { Table, TableHeader, TableBody, TableRow, TableHead, TableCell }
import from ..ui.input { Input }
import from ..ui.button { Button }
import from ..ui.select { Select, SelectTrigger, SelectValue, SelectContent, SelectGroup, SelectItem }
import from .util { fmt_num, pct1 }
import from .UserPeek { UserPeek }

# Columns whose cells drill through to the User 360 panel.
glob USER_COLS: list[str] = ["user", "owner", "email"];

# Numeric-looking = optional leading '-', digits, at most one '.'. Anything else
# (emails, models, plans, ids, dates) renders as-is — fmt_num on text is NaN.
def:pub numlike(v: any) -> bool {
    s = str(v);
    if s == "" {
        return False;
    }
    digits = "0123456789";
    has_digit = False;
    dots = 0;
    i = 0;
    for ch in s {
        if ch in digits {
            has_digit = True;
        } elif ch == "-" and i == 0 {
            has_digit = has_digit;
        } elif ch == "." and dots == 0 {
            dots = 1;
        } else {
            return False;
        }
        i = i + 1;
    }
    return has_digit;
}

def hdr_label(col: str) -> str {
    return col.replace("_pct", " %").replace("_", " ");
}

def cell_text(v: any, col: str) -> str {
    if v is None {
        return fmt_num(v);
    }
    if not numlike(v) {
        return str(v);
    }
    if col.endswith("pct") or ("%" in col) {
        return pct1(v);
    }
    return fmt_num(v);
}

# Hand-rolled merge sort — list.sort(key=..) has no jac2js precedent in this
# codebase, so we don't gamble on it. Pairs are [key, row]; stable.
def _cmp_le(a: any, b: any, desc: bool, is_num: bool) -> bool {
    if is_num {
        af = a as float;
        bf = b as float;
        return (af >= bf) if desc else (af <= bf);
    }
    sa = str(a);
    sb = str(b);
    return (sa >= sb) if desc else (sa <= sb);
}

def _msort(pairs: list, desc: bool, is_num: bool) -> list {
    n = len(pairs);
    if n <= 1 {
        return pairs;
    }
    mid = n // 2;
    left = _msort(pairs[0:mid], desc, is_num);
    right = _msort(pairs[mid:n], desc, is_num);
    out: list = [];
    i = 0;
    j = 0;
    while (i < len(left)) and (j < len(right)) {
        lp = left[i] as list;
        rp = right[j] as list;
        if _cmp_le(lp[0], rp[0], desc, is_num) {
            out = out + [lp];
            i = i + 1;
        } else {
            out = out + [rp];
            j = j + 1;
        }
    }
    while i < len(left) {
        out = out + [left[i]];
        i = i + 1;
    }
    while j < len(right) {
        out = out + [right[j]];
        j = j + 1;
    }
    return out;
}

# Numeric-aware sort: numeric values ordered together, text values together
# (numbers first on desc, before text — stable within each group).
def sorted_rows(rows: list, ci: int, desc: bool) -> list {
    nums: list = [];
    texts: list = [];
    for r in rows {
        rl = r as list;
        v = rl[ci] if ci < len(rl) else None;
        if (v is not None) and numlike(v) {
            nums = nums + [[v as float, rl]];
        } else {
            key = str(v).lower() if v is not None else "";
            texts = texts + [[key, rl]];
        }
    }
    nums = _msort(nums, desc, True);
    texts = _msort(texts, desc, False);
    out: list = [];
    for p in nums {
        out = out + [(p as list)[1]];
    }
    for p in texts {
        out = out + [(p as list)[1]];
    }
    return out;
}

# One table cell — branching (clickable user vs plain text) lives in a
# component BODY, never in a for-slot.
def CellVal(cc: dict, on_user: Callable[[str], None]) -> JsxElement {
    def h(e: MouseEvent) {
        on_user(str(cc["v"]));
    }
    if cc["click"] as bool {
        return <button type="button" onClick={h} className="cursor-pointer text-left underline decoration-dotted underline-offset-2 hover:text-primary">{str(cc["v"])}</button>;
    }
    return <span>{str(cc["v"])}</span>;
}

# Sortable column header (named component — callbacks never inline).
def HeadBtn(label: str, idx: int, marker: str, on_sort: Callable[[int], None]) -> JsxElement {
    def h(e: MouseEvent) {
        on_sort(idx);
    }
    return <button type="button" onClick={h} className="inline-flex cursor-pointer select-none items-center gap-1 hover:text-foreground">
        <span>{label}</span>
        <span className="text-[9px] text-muted-foreground">{marker}</span>
    </button>;
}

def:pub DataTable(columns: list, rows: list, env: str) -> JsxElement {
    has q: str = "";
    has sort_col: int = -1;
    has sort_desc: bool = True;
    has page: int = 0;
    has page_size: int = 10;
    has sel_user: str = "";

    def pick_user(u: str) {
        sel_user = u;
    }
    def close_peek() {
        sel_user = "";
    }

    def on_q(e: Event) {
        q = e.target.value as str;
        page = 0;
    }
    def on_sort(idx: int) {
        if sort_col == idx {
            sort_desc = not sort_desc;
        } else {
            sort_col = idx;
            sort_desc = True;
        }
        page = 0;
    }
    def on_page_size(v: str) {
        page_size = v as int;
        page = 0;
    }
    def prev_page(e: MouseEvent) {
        if page > 0 {
            page = page - 1;
        }
    }
    def next_page(e: MouseEvent) {
        page = page + 1;
    }

    # ---- pipeline: filter -> sort -> paginate (all precomputed, slots trivial) ----
    total_raw = len(rows);
    ql = q.strip().lower();
    filtered: list = [];
    if ql == "" {
        filtered = rows;
    } else {
        for r in rows {
            hit = False;
            for cell in (r as list) {
                if cell is not None and (ql in str(cell).lower()) {
                    hit = True;
                }
            }
            if hit {
                filtered = filtered + [r];
            }
        }
    }
    ordered = filtered;
    if (sort_col >= 0) and (sort_col < len(columns)) {
        ordered = sorted_rows(filtered, sort_col, sort_desc);
    }

    total = len(ordered);
    pages = 1;
    if total > page_size {
        pages = (total + page_size - 1) // page_size;
    }
    cur = page;
    if cur >= pages {
        cur = pages - 1;
    }
    if cur < 0 {
        cur = 0;
    }
    start = cur * page_size;
    end = start + page_size;
    if end > total {
        end = total;
    }
    visible = ordered[start:end];

    # formatted headers with sort markers
    headers: list = [];
    i = 0;
    for c in columns {
        marker = "↕";
        if sort_col == i {
            marker = "↓" if sort_desc else "↑";
        }
        headers = headers + [{"i": i, "label": hdr_label(str(c)), "marker": marker}];
        i = i + 1;
    }

    # formatted visible rows
    frows: list = [];
    ri = start;
    for r in visible {
        cells: list = [];
        ci = 0;
        for cell in (r as list) {
            val = str(cell) if ci == 0 else cell_text(cell, str(columns[ci]));
            align = "text-right tabular-nums";
            if ci == 0 {
                align = "font-medium";
            } elif (cell is not None) and (not numlike(cell)) {
                align = "";
            }
            clickable = (str(columns[ci]) in USER_COLS) and (cell is not None) and (val != "");
            cells = cells + [{"k": str(ci), "v": val, "a": align, "click": clickable}];
            ci = ci + 1;
        }
        frows = frows + [{"k": "r" + str(ri), "cells": cells}];
        ri = ri + 1;
    }

    show_controls = total_raw > 10;
    range_txt = "";
    if total > 0 {
        range_txt = str(start + 1) + "–" + str(end) + " of " + str(total);
        if total != total_raw {
            range_txt = range_txt + " (filtered from " + str(total_raw) + ")";
        }
    } else {
        range_txt = "0 of " + str(total_raw) + " (filtered)";
    }
    page_txt = "page " + str(cur + 1) + " / " + str(pages);
    prev_disabled = cur <= 0;
    next_disabled = cur >= pages - 1;
    ps_value = str(page_size);

    return <div className="flex flex-col gap-2">
        {if show_controls {
            <div className="flex flex-wrap items-center justify-between gap-2">
                <Input className="h-7 w-48 text-xs" value={q} onChange={on_q} placeholder="Search…" />
                <span className="text-[11px] text-muted-foreground">{range_txt}</span>
            </div>
        }}
        <div className="overflow-x-auto">
            <Table>
                <TableHeader>
                    <TableRow>
                        {for h in headers {
                            <TableHead key={"h" + str(h["i"])} className="text-xs">
                                <HeadBtn label={str(h["label"])} idx={h["i"] as int} marker={str(h["marker"])} on_sort={on_sort} />
                            </TableHead>
                        }}
                    </TableRow>
                </TableHeader>
                <TableBody>
                    {if len(frows) == 0 {
                        <TableRow><TableCell className="text-xs text-muted-foreground">No data in this window.</TableCell></TableRow>
                    }}
                    {for fr in frows {
                        <TableRow key={str(fr["k"])}>
                            {for cc in fr["cells"] {
                                <TableCell key={str(cc["k"])} className={"text-xs " + str(cc["a"])}>
                                    <CellVal cc={cc} on_user={pick_user} />
                                </TableCell>
                            }}
                        </TableRow>
                    }}
                </TableBody>
            </Table>
        </div>
        {if sel_user != "" {
            <UserPeek user={sel_user} env={env} on_close={close_peek} />
        }}
        {if show_controls and (pages > 1 or total > 10) {
            <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="flex items-center gap-2">
                    <span className="text-[11px] text-muted-foreground">Rows:</span>
                    <Select value={ps_value} onValueChange={on_page_size}>
                        <SelectTrigger className="h-7 w-16 text-xs"><SelectValue /></SelectTrigger>
                        <SelectContent>
                            <SelectGroup>
                                <SelectItem value="10">10</SelectItem>
                                <SelectItem value="25">25</SelectItem>
                                <SelectItem value="50">50</SelectItem>
                                <SelectItem value="100">100</SelectItem>
                            </SelectGroup>
                        </SelectContent>
                    </Select>
                </div>
                <div className="flex items-center gap-2">
                    <span className="text-[11px] text-muted-foreground">{page_txt}</span>
                    <Button variant="outline" size="sm" className="h-7 px-2 text-xs" onClick={prev_page} disabled={prev_disabled}>← Prev</Button>
                    <Button variant="outline" size="sm" className="h-7 px-2 text-xs" onClick={next_page} disabled={next_disabled}>Next →</Button>
                </div>
            </div>
        }}
    </div>;
}
