sv import from ...metrics_sv { metrics_batch }
import from ..dash.util { cache_key, cache_get, cache_put, cacheable }
import from ..dash.StatTile { StatTile }
import from ..dash.ChartTiles { LineTile, AreaTile, BarsTile, Banner }

glob HEALTH_KEYS: list = ["median_response", "preview_reliability", "exception_total", "exception_weekly", "latency_weekly", "deploy_success", "deploy_intent"];

def:pub HealthPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has data: dict = {};
    has loading: bool = True;
    has seen: int = -999;

    async def load(refresh: bool) {
        k = cache_key("health", env, date_from, date_to);
        hit = cache_get(k);
        if (hit is not None) and (not refresh) {
            data = hit as dict;
            loading = False;
            return;
        }
        loading = True;
        keys = HEALTH_KEYS;
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

    return <div className="grid grid-cols-12 gap-4">
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Typical response time" data={data["median_response"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Preview reliability" data={data["preview_reliability"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Website errors" data={data["exception_total"]} loading={loading} /></div>

        <div className="col-span-12 lg:col-span-6"><AreaTile title="Website errors over time" data={data["exception_weekly"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-6"><LineTile title="Response time over time" data={data["latency_weekly"]} loading={loading} /></div>

        <div className="col-span-12 sm:col-span-6 lg:col-span-4"><StatTile title="Deploy success rate" data={data["deploy_success"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-8"><BarsTile title="Deploy attempts (test vs live)" data={data["deploy_intent"]} loading={loading} /></div>

        <div className="col-span-12"><Banner text="The numbers on this page (AI response time, preview reliability, browser errors) are live and real. Server infrastructure health (server capacity, true uptime) isn't tracked here yet — it lives in a separate internal monitoring system." /></div>
    </div>;
}
