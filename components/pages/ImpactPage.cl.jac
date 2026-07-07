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
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StaticStat title="Estimated return on investment" value="—" note="Not available yet — calculating this needs revenue data we don't have connected." definition="The value delivered to the business compared to what it cost to deliver." /></div>

        <div className="col-span-12 lg:col-span-6"><LineTile title="Work kept over time" data={data["kept_weekly"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-6"><AreaTile title="Code produced over time" data={data["files_changed_weekly"]} loading={loading} /></div>

        <div className="col-span-12"><Banner text="Being upfront about what's real: only 'work kept' (based on whether users undid changes) and 'files changed by AI' are actually measured. Hours-saved and return-on-investment are estimates — we'll measure them properly once we track real acceptance and connect revenue data." /></div>
    </div>;
}
