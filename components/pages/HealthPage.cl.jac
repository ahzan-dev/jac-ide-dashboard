sv import from ...metrics_sv { metrics_batch }
import from ..dash.StatTile { StatTile }
import from ..dash.ChartTiles { LineTile, AreaTile, BarsTile, Banner }

glob HEALTH_KEYS: list = ["median_response", "preview_reliability", "exception_total", "exception_weekly", "latency_weekly", "deploy_success", "deploy_intent"];

def:pub HealthPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has data: dict = {};
    has loading: bool = True;
    has seen: int = -999;

    async def load(refresh: bool) {
        loading = True;
        keys = HEALTH_KEYS;
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
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="AI latency (median)" data={data["median_response"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Preview reliability" data={data["preview_reliability"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="JS errors" data={data["exception_total"]} loading={loading} /></div>

        <div className="col-span-12 lg:col-span-6"><AreaTile title="JS error trend" data={data["exception_weekly"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-6"><LineTile title="AI latency trend" data={data["latency_weekly"]} loading={loading} /></div>

        <div className="col-span-12 sm:col-span-6 lg:col-span-4"><StatTile title="Deploy success rate" data={data["deploy_success"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-8"><BarsTile title="Deploy intent (sandbox vs prod)" data={data["deploy_intent"]} loading={loading} /></div>

        <div className="col-span-12"><Banner text="App-level health is live (AI latency, preview reliability, JS errors). Infra (CPU/mem/pods, real uptime) is not a PostHog metric — reachable via jac-scale Prometheus (get_pod_resource_metrics / get_prometheus_series) pointed at the jac-builder namespace." /></div>
    </div>;
}
