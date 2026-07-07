sv import from ...metrics_sv { metrics_batch }
import from ..dash.StatTile { StatTile }
import from ..dash.ChartTiles { LineTile, BarsTile, Banner }

glob QUALITY_KEYS: list = [
    "failure_rate", "median_response", "revert_rate", "gen_success",
    "rating_ratio", "gen_success_weekly", "revert_weekly", "ai_fail_reasons"
];

def:pub QualityPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has data: dict = {};
    has loading: bool = True;
    has seen: int = -999;

    async def load(refresh: bool) {
        loading = True;
        keys = QUALITY_KEYS;
        res = await metrics_batch(keys, env, date_from, date_to, refresh);
        data = res as dict;
        loading = False;
    }
    async can with (env, date_from, date_to, refresh_n) entry {
        refresh = (refresh_n != seen) and (seen != -999);
        seen = refresh_n;
        await load(refresh);
    }

    return <div className="grid grid-cols-12 gap-4">
        <div className="col-span-12"><Banner text="Our biggest gap: we don't yet have a direct way for users to tell us if the AI's answer was good. Until that launches, everything below is inferred from behavior — failures, undos, and response time — not what users actually say." /></div>

        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="AI failure rate" data={data["failure_rate"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Typical response time" data={data["median_response"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Undo rate" data={data["revert_rate"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="AI success rate" data={data["gen_success"]} loading={loading} /></div>

        <div className="col-span-12 lg:col-span-4"><LineTile title="AI success rate over time" data={data["gen_success_weekly"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-4"><LineTile title="Undo rate over time" data={data["revert_weekly"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-4"><BarsTile title="Top failure reasons" data={data["ai_fail_reasons"]} loading={loading} /></div>

        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Helpful rate" data={data["rating_ratio"]} loading={loading} /></div>
    </div>;
}
