# Shared display helpers for dashboard tiles (client-side, pure functions).

# ---- date helpers for the range picker (browser Date interop) --------------
def:pub iso_days_ago(n: int) -> str {
    ms = new(Date).getTime() - (n * 86400000);
    return new(Date, ms).toISOString()[0:10];
}
def:pub iso_tomorrow() -> str {
    ms = new(Date).getTime() + 86400000;
    return new(Date, ms).toISOString()[0:10];
}
def:pub iso_of(d: any) -> str {
    return d.toISOString()[0:10];
}

# Axis tick: "2026-05-17" -> "05-17". Named (inline lambda tickFormatters miscompile in jac2js).
def:pub short_date(v: any) -> str {
    s = str(v);
    if len(s) >= 10 { return s[5:10]; }
    return s;
}

# Axis tick that shortens dates but leaves short values (e.g. hour numbers) as-is.
def:pub axis_tick(v: any) -> str {
    s = str(v);
    if len(s) >= 10 and ("-" in s) { return s[5:10]; }
    return s;
}

def:pub env_label(e: str) -> str {
    if e == "prod" { return "Production"; }
    if e == "dev" { return "Dev"; }
    if e == "preview" { return "Preview"; }
    return "All envs";
}

def:pub fmt_num(v: any) -> str {
    if v is None { return "—"; }
    try {
        f = v as float;
        if f == int(f) { return _group(int(f)); }
        return str(round(f * 10.0) / 10.0);
    } except Exception {
        return str(v);
    }
}

# Thousands separators without relying on jac2js format specs.
def _group(n: int) -> str {
    neg = n < 0;
    s = str(abs(n));
    out = "";
    i = len(s);
    while i > 3 {
        out = "," + s[i - 3:i] + out;
        i = i - 3;
    }
    out = s[0:i] + out;
    return ("-" + out) if neg else out;
}

def:pub fmt_val(v: any, unit: str) -> str {
    if v is None { return "n/a"; }
    s = fmt_num(v);
    if unit == "$" { return "$" + s; }
    if unit == "%" { return s + "%"; }
    if unit == "s" { return s + "s"; }
    if unit { return s + " " + unit; }
    return s;
}

def:pub pct1(v: any) -> str {
    if v is None { return "—"; }
    try {
        return str(int(round(v as float))) + "%";
    } except Exception {
        return str(v);
    }
}

# Badge from a compare-to-previous % delta (current window vs the previous equal-length window).
def:pub delta_badge(delta: any, good_when_up: bool) -> dict {
    if delta is None {
        return {"arrow": "", "cls": "flat", "txt": ""};
    }
    d = delta as float;
    up = d > 0.0;
    flat = d == 0.0;
    good = (up and good_when_up) or ((not up) and (not good_when_up) and (not flat));
    arrow = "→";
    if up { arrow = "▲"; }
    elif d < 0.0 { arrow = "▼"; }
    cls = "flat";
    if not flat {
        cls = "good" if good else "bad";
    }
    dd = int(round(d));
    sign = "+" if dd >= 0 else "";
    return {"arrow": arrow, "cls": cls, "txt": sign + str(dd) + "% vs prev"};
}

# ---- client-side page cache: instant page switches --------------------------
# Each page's last batch result is kept alive across mount/unmount so switching
# pages renders immediately instead of re-fetching every time. Keyed by
# page + env + date range: a different env/range is a new key (miss → fresh
# fetch), and the top-bar Refresh forces a bypass (refresh=True). `glob` module
# state survives component remounts and is shared across all pages; it is NOT
# reactive — each page's own `data`/`loading` has-vars still drive its render.
glob PAGE_CACHE: dict = {};

def:pub cache_key(page: str, env: str, date_from: str, date_to: str) -> str {
    return page + ":" + env + ":" + date_from + ":" + date_to;
}
def:pub cache_get(k: str) -> dict | None {
    hit = PAGE_CACHE.get(k, None);
    if hit is None { return None; }
    return hit as dict;
}
def:pub cache_put(k: str, v: dict) -> dict {
    PAGE_CACHE[k] = v;
    return v;
}
# Decide whether a page's batch result is worth caching. Rule: MAJORITY-HEALTHY —
# cache only if more tiles returned real data than carried a transient `error`
# (PostHog 503 / timeout). This keeps switching instant for fully- or mostly-
# healthy pages (the common case), still caches during a partial PostHog brownout
# (e.g. 11 good tiles + 1 timeout), but refuses to freeze an all-empty or mostly-
# broken snapshot — that page re-fetches on the next visit and self-heals instead
# of showing stale "n/a" for the whole session. Tiles that are legitimately empty
# (no data, no error — e.g. a stub) count for neither side.
def:pub cacheable(res: dict, keys: list) -> bool {
    good = 0;
    bad = 0;
    for k in keys {
        tile = res.get(k as str, None);
        if tile is not None {
            t = tile as dict;
            if t.get("error", "") { bad += 1; }
            elif _tile_has_data(t) { good += 1; }
        }
    }
    return good > bad;
}
# A tile carries data if it has a scalar value, a trend series, or table/funnel rows.
def _tile_has_data(t: dict) -> bool {
    if t.get("value", None) is not None { return True; }
    if len(t.get("series", []) as list) > 0 { return True; }
    if len(t.get("rows", []) as list) > 0 { return True; }
    return False;
}

# Slope of a weekly series: compare the last two COMPLETE points (drop the in-progress week).
# Returns {arrow, cls, txt}. cls is 'good'/'bad'/'flat' given the metric's good_when_up.
def:pub slope_of(series: list, good_when_up: bool) -> dict {
    n = len(series);
    if n < 3 {
        return {"arrow": "→", "cls": "flat", "txt": ""};
    }
    a = series[n - 3]["y"] as float;   # week before last complete
    b = series[n - 2]["y"] as float;   # last complete week (n-1 is in progress)
    if a == 0.0 {
        return {"arrow": "→", "cls": "flat", "txt": ""};
    }
    change = (b - a) / a * 100.0;
    up = b > a;
    flat = b == a;
    good = (up and good_when_up) or ((not up) and (not good_when_up) and (not flat));
    arrow = "→";
    if up { arrow = "▲"; }
    elif b < a { arrow = "▼"; }
    cls = "flat";
    if not flat {
        cls = "good" if good else "bad";
    }
    ch = int(round(change));
    sign = "+" if ch >= 0 else "";
    return {"arrow": arrow, "cls": cls, "txt": sign + str(ch) + "% wk"};
}
