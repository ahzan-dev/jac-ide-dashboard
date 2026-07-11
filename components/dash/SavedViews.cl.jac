# Saved views: persist {page, env, date range} bookmarks in the user's server
# graph (metrics_sv view_* endpoints) and restore on click, so they follow the
# account across browsers. Plain buttons (no Popover/portal — those freeze this build).
sv import from ...metrics_sv { view_list, view_add, view_remove }

def ViewChip(v: any, on_restore: Callable[[any], None], on_remove: Callable[[str], None]) -> JsxElement {
    def cr(e: MouseEvent) { on_restore(v); }
    def rm(e: MouseEvent) { on_remove(str(v["id"])); }
    return <div className="flex items-center overflow-hidden rounded-md border border-border text-xs">
        <button onClick={cr} className="max-w-[16rem] truncate px-2 py-1 hover:bg-accent" title={str(v["name"])}>{str(v["name"])}</button>
        <button onClick={rm} className="border-l border-border px-1.5 py-1 text-muted-foreground hover:text-destructive" title="Remove">×</button>
    </div>;
}

def:pub SavedViews(page: str, env: str, date_from: str, date_to: str, on_restore: Callable[[str, str, str, str], None]) -> JsxElement {
    has views: list = [];

    async def load() {
        try {
            views = (await view_list()) as list;
        } except Exception as e {
            views = [];
        }
    }
    async can with entry {
        await load();
    }

    async def do_save() {
        label = env + " · " + date_from + " → " + date_to;
        v = {"name": label, "page": page, "env": env, "from": date_from, "to": date_to};
        try {
            views = (await view_add(v)) as list;
        } except Exception as e {
            return;
        }
    }
    async def do_remove(view_id: str) {
        try {
            views = (await view_remove(view_id)) as list;
        } except Exception as e {
            return;
        }
    }
    def save(e: MouseEvent) {
        do_save();
    }
    def remove(view_id: str) {
        do_remove(view_id);
    }
    def do_restore(v: any) {
        on_restore(str(v["page"]), str(v["env"]), str(v["from"]), str(v["to"]));
    }

    return <div className="flex flex-wrap items-center gap-2">
        <button onClick={save} className="rounded-md border border-dashed border-border px-2 py-1 text-xs text-muted-foreground hover:text-foreground">★ Save this view</button>
        {for v in views {
            <ViewChip key={str(v["id"])} v={v} on_restore={do_restore} on_remove={remove} />
        }}
    </div>;
}
