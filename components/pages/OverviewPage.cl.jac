sv import from ...metrics_sv { metrics_batch }
import from ..dash.StatTile { StatTile }
import from ..dash.ChartTiles { LineTile, AreaTile, BarsTile, FunnelTile, RetentionTile, GaugeTile }

glob OVERVIEW_KEYS: list = [
    "active_builders", "ai_requests", "median_response", "code_produced",
    "active_weekly", "top_features", "problem_areas",
    "gen_success", "kept_rate", "gen_success_weekly", "preview_reliability_weekly",
    "funnel", "retention"
];

def:pub OverviewPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has data: dict = {};
    has loading: bool = True;
    has seen: int = -999;

    async def load(refresh: bool) {
        loading = True;
        keys = OVERVIEW_KEYS;
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
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Active builders" data={data["active_builders"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="AI requests" data={data["ai_requests"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Median response" data={data["median_response"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Code produced" data={data["code_produced"]} loading={loading} /></div>

        <div className="col-span-12 lg:col-span-5"><AreaTile title="User growth (reach)" data={data["active_weekly"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-4"><BarsTile title="Top features by usage" data={data["top_features"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><BarsTile title="Top problem areas" data={data["problem_areas"]} loading={loading} /></div>

        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><GaugeTile title="Gen success" data={data["gen_success"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><GaugeTile title="Kept (not reverted)" data={data["kept_rate"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><LineTile title="AI quality trend" data={data["gen_success_weekly"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><LineTile title="Preview reliability" data={data["preview_reliability_weekly"]} loading={loading} /></div>

        <div className="col-span-12 lg:col-span-5"><FunnelTile title="Activation funnel" data={data["funnel"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-7"><RetentionTile title="Retention cohort" data={data["retention"]} loading={loading} /></div>
    </div>;
}
