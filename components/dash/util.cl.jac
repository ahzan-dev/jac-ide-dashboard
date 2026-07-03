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
