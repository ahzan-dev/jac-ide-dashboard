sv import from ...metrics_sv { metrics_batch }
import from ..dash.StatTile { StatTile }
import from ..dash.ChartTiles { LineTile, BarsTile, VBarTile }

glob REQUESTS_KEYS: list = [
    "ai_requests", "requests_per_active", "prompt_len", "median_response",
    "requests_daily", "peak_hours", "gen_success_weekly", "ai_fail_reasons"
];

def:pub RequestsPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has data: dict = {};
    has loading: bool = True;
    has seen: int = -999;

    async def load(refresh: bool) {
        loading = True;
        keys = REQUESTS_KEYS;
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
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Total requests" data={data["ai_requests"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Requests / active user" data={data["requests_per_active"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Median prompt" data={data["prompt_len"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Median response" data={data["median_response"]} loading={loading} /></div>

        <div className="col-span-12 lg:col-span-5"><VBarTile title="Requests per day" data={data["requests_daily"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-4"><VBarTile title="Peak usage hours (UTC)" data={data["peak_hours"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><LineTile title="Generation success" data={data["gen_success_weekly"]} loading={loading} /></div>

        <div className="col-span-12 lg:col-span-6"><BarsTile title="Top failure reasons" data={data["ai_fail_reasons"]} loading={loading} /></div>
    </div>;
}
