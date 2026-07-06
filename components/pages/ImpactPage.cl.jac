sv import from ...metrics_sv { metrics_batch }
import from ..dash.StatTile { StatTile }
import from ..dash.ChartTiles { LineTile, AreaTile, StaticStat, Banner }

glob IMPACT_KEYS: list = ["kept_rate", "code_produced", "kept_weekly", "files_changed_weekly"];

def:pub ImpactPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has data: dict = {};
    has loading: bool = True;
    has seen: int = -999;

    async def load(refresh: bool) {
        loading = True;
        keys = IMPACT_KEYS;
        res = await metrics_batch(keys, env, date_from, date_to, refresh);
        data = res as dict;
        loading = False;
    }
    async can with (env, date_from, date_to, refresh_n) entry {
        refresh = (refresh_n != seen) and (seen != -999);
        seen = refresh_n;
        await load(refresh);
    }

    # Derived estimate — files_changed × ~2 min saved each. Explicitly an estimate.
    cp = data["code_produced"] if data else None;
    files = cp["value"] if cp else None;
    hours_txt = "—";
    if files is not None {
        try {
            hours_txt = str(int(round((files as float) * 2.0 / 60.0))) + "h";
        } except Exception {
            hours_txt = "—";
        }
    }

    return <div className="grid grid-cols-12 gap-4">
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Kept (not reverted)" data={data["kept_rate"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Code produced" data={data["code_produced"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StaticStat title="Est. hours saved" value={hours_txt} note="Estimate only: ~2 min saved per changed file. Not a measured value." definition="Rough productivity proxy from files_changed × a constant." /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StaticStat title="Est. ROI" value="—" note="Needs revenue (Stripe) to compute return; not in PostHog." definition="Value delivered ÷ cost." /></div>

        <div className="col-span-12 lg:col-span-6"><LineTile title="Acceptance proxy trend" data={data["kept_weekly"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-6"><AreaTile title="Code produced trend" data={data["files_changed_weekly"]} loading={loading} /></div>

        <div className="col-span-12"><Banner text="Honest scope — only acceptance proxy (revert-based) and code-produced (files_changed) are measured. Hours-saved / ROI are estimates until a per-file accept event (generation_kept) + Stripe revenue exist." /></div>
    </div>;
}
