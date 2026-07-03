# Saved views: persist {page, env, date_from, date_to} to localStorage and restore on click.
# Plain buttons + localStorage (no Popover/portal — those freeze in this build).

glob _VK: str = "jachammer_views";

def _load_views() -> list {
    try {
        raw = localStorage.getItem(_VK);
        if raw {
            return JSON.parse(raw) as list;
        }
    } except Exception as e {
        return [];
    }
    return [];
}
def _save_views(views: list) {
    try {
        localStorage.setItem(_VK, JSON.stringify(views));
    } except Exception as e {
        return;
    }
}

def ViewChip(v: any, idx: int, on_restore: Callable[[any], None], on_remove: Callable[[int], None]) -> JsxElement {
    def cr(e: MouseEvent) { on_restore(v); }
    def rm(e: MouseEvent) { on_remove(idx); }
    return <div className="flex items-center overflow-hidden rounded-md border border-border text-xs">
        <button onClick={cr} className="max-w-[16rem] truncate px-2 py-1 hover:bg-accent" title={str(v["name"])}>{str(v["name"])}</button>
        <button onClick={rm} className="border-l border-border px-1.5 py-1 text-muted-foreground hover:text-destructive" title="Remove">×</button>
    </div>;
}

def:pub SavedViews(page: str, env: str, date_from: str, date_to: str, on_restore: Callable[[str, str, str, str], None]) -> JsxElement {
    has views: list = [];

    can with entry {
        views = _load_views();
    }

    def save(e: MouseEvent) {
        label = env + " · " + date_from + " → " + date_to;
        v = {"name": label, "page": page, "env": env, "from": date_from, "to": date_to};
        nv = views + [v];
        _save_views(nv);
        views = nv;
    }
    def do_restore(v: any) {
        on_restore(str(v["page"]), str(v["env"]), str(v["from"]), str(v["to"]));
    }
    def do_remove(idx: int) {
        nv = [];
        j = 0;
        for vv in views {
            if j != idx {
                nv = nv + [vv];
            }
            j = j + 1;
        }
        _save_views(nv);
        views = nv;
    }

    items = [];
    i = 0;
    for v in views {
        items = items + [{"v": v, "i": i}];
        i = i + 1;
    }

    return <div className="flex flex-wrap items-center gap-2">
        <button onClick={save} className="rounded-md border border-dashed border-border px-2 py-1 text-xs text-muted-foreground hover:text-foreground">★ Save this view</button>
        {for it in items {
            <ViewChip key={str(it["i"])} v={it["v"]} idx={it["i"]} on_restore={do_restore} on_remove={do_remove} />
        }}
    </div>;
}
