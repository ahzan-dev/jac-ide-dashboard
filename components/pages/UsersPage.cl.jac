sv import from ...metrics_sv { metrics_batch }
import from ..dash.util { cache_key, cache_get, cache_put, cacheable }
import from ..dash.StatTile { StatTile }
import from ..dash.ChartTiles { AreaTile, DonutTile, FunnelTile, RetentionTile }

glob USERS_KEYS: list = [
    "signups_total", "active_builders", "new_signups", "activation",
    "active_weekly", "returning_weekly", "signup_method",
    "funnel", "retention", "churn_risk"
];

def:pub UsersPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has data: dict = {};
    has loading: bool = True;
    has seen: int = -999;

    async def load(refresh: bool) {
        k = cache_key("users", env, date_from, date_to);
        hit = cache_get(k);
        if (hit is not None) and (not refresh) {
            data = hit as dict;
            loading = False;
            return;
        }
        loading = True;
        keys = USERS_KEYS;
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
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Signups (last 6 months)" data={data["signups_total"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Active builders" data={data["active_builders"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="New signups" data={data["new_signups"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="New users who got a result" data={data["activation"]} loading={loading} /></div>

        <div className="col-span-12 lg:col-span-5"><AreaTile title="User growth (all visitors)" data={data["active_weekly"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-4"><AreaTile title="Returning users" data={data["returning_weekly"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><DonutTile title="How people sign up" data={data["signup_method"]} loading={loading} /></div>

        <div className="col-span-12 lg:col-span-4"><FunnelTile title="New-user journey" data={data["funnel"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-5"><RetentionTile title="Retention over time" data={data["retention"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-3"><StatTile title="Accounts at risk (60 days)" data={data["churn_risk"]} loading={loading} /></div>
    </div>;
}
