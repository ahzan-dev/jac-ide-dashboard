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

# ---- timezone bridge: users pick/see LOCAL time; storage + queries stay UTC --
def _pad2(n: int) -> str {
    s = str(n);
    if len(s) < 2 {
        return "0" + s;
    }
    return s;
}

# "YYYY-MM-DDTHH:MM" from a datetime-local input (LOCAL time) -> "YYYY-MM-DD HH:MM:SS" UTC.
def:pub local_to_utc(s: str) -> str {
    d = new(Date, s);
    iso = d.toISOString();
    return iso[0:10] + " " + iso[11:19];
}

# "YYYY-MM-DD HH:MM[:SS]" UTC (server form) -> "YYYY-MM-DD HH:MM" in the viewer's local tz.
def:pub utc_to_local(s: str) -> str {
    if len(s) < 16 {
        return s;
    }
    d = new(Date, s[0:16].replace(" ", "T") + ":00Z");
    return str(d.getFullYear()) + "-" + _pad2(d.getMonth() + 1) + "-" + _pad2(d.getDate())
        + " " + _pad2(d.getHours()) + ":" + _pad2(d.getMinutes());
}

# Same, shaped for a datetime-local input's value attribute.
def:pub utc_to_local_input(s: str) -> str {
    return utc_to_local(s).replace(" ", "T");
}

# Display timezone: user-selectable (persisted), defaulting to the device zone.
# NOTE: the tz selector affects DISPLAY formatting (labels, axes, windows);
# the datetime pickers always use the device zone (native input limitation).
glob TZ_KEY: str = "jachammer_tz";

def:pub tz_display() -> str {
    try {
        v = localStorage.getItem(TZ_KEY);
        if v {
            return v as str;
        }
    } except Exception {
        return "";
    }
    return "";
}

def:pub tz_set(v: str) {
    try {
        if v == "" {
            localStorage.removeItem(TZ_KEY);
        } else {
            localStorage.setItem(TZ_KEY, v);
        }
    } except Exception {
        return;
    }
}

# The viewer's effective display timezone name for honest labeling.
def:pub tz_name() -> str {
    o = tz_display();
    if o != "" {
        return o;
    }
    try {
        return str(new(Intl.DateTimeFormat).resolvedOptions().timeZone);
    } except Exception {
        return "local";
    }
}

def _dt_of(s: str) -> any {
    ss = s.strip();
    if len(ss) == 10 {
        ss = ss + " 00:00:00";
    }
    return new(Date, ss[0:16].replace(" ", "T") + ":00Z");
}

# "YYYY-MM-DD HH:MM[:SS]" UTC -> "Jul 26, 10:30 PM" in the display tz.
def:pub human_dt(s: str) -> str {
    if len(s.strip()) < 10 {
        return s;
    }
    d = _dt_of(s);
    opts = {"month": "short", "day": "numeric", "hour": "numeric", "minute": "2-digit"};
    t = tz_display();
    if t != "" {
        opts["timeZone"] = t;
    }
    try {
        return str(d.toLocaleString("en-US", opts));
    } except Exception {
        return utc_to_local(s);
    }
}

# time-of-day only: "10:30 PM"
def:pub human_time(s: str) -> str {
    d = _dt_of(s);
    opts = {"hour": "numeric", "minute": "2-digit"};
    t = tz_display();
    if t != "" {
        opts["timeZone"] = t;
    }
    try {
        return str(d.toLocaleString("en-US", opts));
    } except Exception {
        return s;
    }
}

def _looks_dt(s: str) -> bool {
    return (len(s) >= 10) and (s[4:5] == "-") and (s[7:8] == "-");
}

# Server window label "YYYY-MM-DD HH:MM:SS → YYYY-MM-DD HH:MM:SS (7.5h)" ->
# "Jul 26, 10:30 PM → Jul 27, 6:00 AM (7.5h)" in the display tz. Fixed labels
# ("last 30 days", cohort windows) pass through untouched.
def:pub human_window(w: str) -> str {
    if " → " not in w {
        return w;
    }
    parts = w.split(" → ");
    if len(parts) != 2 {
        return w;
    }
    left = str(parts[0]).strip();
    right = str(parts[1]).strip();
    tail = "";
    if " (" in right {
        i = right.find(" (");
        tail = " " + right[i + 1:];
        right = right[0:i];
    }
    if _looks_dt(left) and _looks_dt(right) {
        return human_dt(left) + " → " + human_dt(right) + tail;
    }
    return w;
}

# Axis tick: daily/weekly buckets -> "05-17"; sub-day buckets (datetime values)
# -> local clock time "10:30 PM" (a repeated "07-26 07-26 …" axis is useless).
# Named (inline lambda tickFormatters miscompile in jac2js).
def:pub short_date(v: any) -> str {
    s = str(v);
    if len(s) >= 16 and (":" in s) { return human_time(s); }
    if len(s) >= 10 { return s[5:10]; }
    return s;
}

# Axis tick that also leaves short values (e.g. hour numbers) as-is.
def:pub axis_tick(v: any) -> str {
    s = str(v);
    if len(s) >= 16 and (":" in s) { return human_time(s); }
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

# NOTE: pins + saved views now persist in the user's server graph (metrics_sv:
# pin_*/view_* endpoints), not localStorage, so they follow the account across
# browsers. See PinnedPage / AskPage / SavedViews.

# ---- named-window annotations on trend charts (P4) --------------------------
# AppShell loads the user's named windows once; trend tiles shade the span of
# any named window that overlaps their series ("the hackathon happened HERE").
# Populated by AppShell BEFORE pages first mount (AppShell gates page rendering
# on the windows fetch): globs aren't reactive and jac2js memoizes components,
# so annotations must exist before the first tile render — no later chance.
glob ANNOTS: list = [];

def:pub set_annotations(ws: list) {
    ANNOTS.clear();
    for w in ws {
        ANNOTS.append(w);
    }
}

# Overlap a named window with a series' x values (date or datetime strings,
# lexicographically comparable). Returns [{x1, x2, name}] for ReferenceArea.
def:pub annots_for(series: list) -> list {
    out: list = [];
    if len(series) < 2 {
        return out;
    }
    for w in ANNOTS {
        wd = w as dict;
        f = str(wd.get("from_dt", ""));
        t = str(wd.get("to_dt", ""));
        if (f == "") or (t == "") {
            continue;
        }
        x1 = "";
        x2 = "";
        for p in series {
            x = str((p as dict)["x"]);
            hit = False;
            if len(x) <= 10 {
                # date-granular bucket: overlap at the DATE level (an evening
                # window like 22:30→06:00 must still mark both days)
                hit = (x >= f[0:10]) and (x <= t[0:10]);
            } else {
                hit = (x[0:19] >= f) and (x[0:19] <= t);
            }
            if hit {
                if x1 == "" {
                    x1 = x;
                }
                x2 = x;
            }
        }
        if x1 != "" {
            out = out + [{"x1": x1, "x2": x2, "name": str(wd.get("name", ""))}];
        }
    }
    return out;
}

# ---- client-side page cache: instant page switches --------------------------
# Each page's last batch result is kept alive across mount/unmount so switching
# pages renders immediately instead of re-fetching every time. Keyed by
# page + env + date range: a different env/range is a new key (miss → fresh
# fetch), and the top-bar Refresh forces a bypass (refresh=True). `glob` module
# state survives component remounts and is shared across all pages; it is NOT
# reactive — each page's own `data`/`loading` has-vars still drive its render.
glob PAGE_CACHE: dict = {};

# In-flight dedup: the initial-load effect fires ~3× per mount (known jac2js
# behavior) — without this, every page load sends the full metrics_batch three
# times. First caller owns the fetch; duplicates return and let the owner's
# completion set state.
glob INFLIGHT: dict = {};

def:pub inflight_start(k: str) -> bool {
    if INFLIGHT.get(k, False) as bool {
        return False;
    }
    INFLIGHT[k] = True;
    return True;
}
def:pub inflight_end(k: str) {
    INFLIGHT[k] = False;
}

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
