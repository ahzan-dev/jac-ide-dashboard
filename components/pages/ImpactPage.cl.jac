sv import from ...metrics_sv { metrics_batch }
import from ..dash.util { cache_key, cache_get, cache_put, cacheable }
import from ..dash.StatTile { StatTile }
import from ..dash.ChartTiles { LineTile, AreaTile, StaticStat, Banner }

glob IMPACT_KEYS: list = ["kept_rate", "code_produced", "kept_weekly", "files_changed_weekly", "ai_edits", "session_depth"];

def:pub ImpactPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has data: dict = {};
    has loading: bool = True;
    has seen: int = -999;

    async def load(refresh: bool) {
        k = cache_key("impact", env, date_from, date_to);
        hit = cache_get(k);
        if (hit is not None) and (not refresh) {
            data = hit as dict;
            loading = False;
            return;
        }
        loading = True;
        keys = IMPACT_KEYS;
        res = await metrics_batch(keys, env, date_from, date_to, refresh);
        data = res as dict;
        if cacheable(data, keys) { cache_put(k, data); }
        loading = False;
    }
    async can with (env, date_from, date_to, refresh_n) entry {
        refresh = (refresh_n != seen) and (seen != -999);
        seen = refresh_n;
        await load(refresh);
    }

    # Derived estimate — files_changed × ~1.5–3 min saved each. Explicitly an estimate.
    cp = data["code_produced"] if data else None;
    files = cp["value"] if cp else None;
    hours_txt = "—";
    if files is not None {
        try {
            lo = int(round((files as float) * 1.5 / 60.0));
            hi = int(round((files as float) * 3.0 / 60.0));
            hours_txt = str(lo) + "–" + str(hi) + "h";
        } except Exception {
            hours_txt = "—";
        }
    }

    return <div className="grid grid-cols-12 gap-4">
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Work kept (not undone)" data={data["kept_rate"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Code produced" data={data["code_produced"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StaticStat title="Estimated hours saved" value={hours_txt} note="An estimate, not a precise measurement — we assume each file the AI changed saves roughly 1.5 to 3 minutes of manual work." definition="A rough estimate of engineering hours saved, based on how many files the AI changed." /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Typical session length" data={data["session_depth"]} loading={loading} /></div>

        <div className="col-span-12 lg:col-span-6"><LineTile title="Work kept over time" data={data["kept_weekly"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-6"><AreaTile title="Code produced over time" data={data["files_changed_weekly"]} loading={loading} /></div>

        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="AI outputs manually edited" data={data["ai_edits"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-9"><Banner text="What's measured vs estimated: work-kept, files-changed, session length (focused time), and manual edits of AI output are real measurements. Hours-saved remains an estimate (1.5–3 min per AI-changed file). ROI still needs revenue attribution and stays unshown rather than invented." /></div>
    </div>;
}
