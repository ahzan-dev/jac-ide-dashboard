sv import from ...metrics_sv { metrics_batch }
sv import from ...billing_sv { billing_summary }
import from ..dash.StatTile { StatTile }
import from ..dash.ChartTiles { AreaTile, BarsTile, StaticStat, Banner }
import from ..dash.util { cache_key, cache_get, cache_put, cacheable }

glob COST_KEYS: list = ["metered_rows", "total_spend", "cost_per_request", "cost_per_user", "model_mix", "ai_requests_weekly"];

def:pub CostPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has data: dict = {};
    has billing: dict = {};
    has loading: bool = True;
    has seen: int = -999;

    async def load(refresh: bool) {
        k = cache_key("cost", env, date_from, date_to);
        hit = cache_get(k);
        if (hit is not None) and (not refresh) {
            h = hit as dict;
            data = h["data"] as dict;
            billing = h["billing"] as dict;
            loading = False;
            return;
        }
        loading = True;
        keys = COST_KEYS;
        res = await metrics_batch(keys, env, date_from, date_to, refresh);
        data = res as dict;
        bill = await billing_summary();
        billing = bill as dict;
        if cacheable(data, keys) { cache_put(k, {"data": data, "billing": billing}); }
        loading = False;
    }
    async can with (env, date_from, date_to, refresh_n) entry {
        refresh = (refresh_n != seen) and (seen != -999);
        seen = refresh_n;
        await load(refresh);
    }

    mr = data["metered_rows"] if data else None;
    mrv = mr["value"] if mr else None;
    metered_txt = str(mrv) if mrv is not None else "…";

    # Margin = (MRR − metered spend) ÷ MRR. Compute a real % ONLY when BOTH halves
    # exist — missing metered spend must NOT be treated as 0 (that reads as a false 100%).
    avail = (billing["available"] as bool) if billing else False;
    mrr = billing["mrr"] if billing else None;
    subs = billing["active_subs"] if billing else 0;
    ts = data["total_spend"] if data else None;
    spend = ts["value"] if ts else None;
    margin_txt = "—";
    margin_note = "We need your subscription pricing and AI cost data to calculate this — not available yet.";
    if avail and (mrr is not None) and ((mrr as float) > 0.0) {
        m = mrr as float;
        if spend is not None {
            sp = spend as float;
            margin_txt = str(int(round((m - sp) / m * 100.0))) + "%";
            margin_note = "Live: $" + str(mrr) + "/month from subscriptions, minus $" + str(spend) + " in AI costs this period.";
        } else {
            margin_txt = "—";
            margin_note = "You're making $" + str(mrr) + "/month from " + str(subs) + " paying customers, but live AI cost data isn't available yet, so we can't show a true margin (assuming zero cost would look artificially perfect).";
        }
    } elif billing {
        margin_note = str(billing["reason"]);
    }

    return <div className="grid grid-cols-12 gap-4">
        <div className="col-span-12"><Banner text={"Revenue numbers are live and accurate. Cost numbers aren't reliable for the live product yet — cost-tracking has started collecting data but isn't correctly labeled as live traffic, so the spend tiles below show 'not available' for now (cost-tracked runs so far: " + metered_txt + "). This is a known fix in progress — once resolved, total AI cost, cost-per-request, and a real profit margin appear automatically."} /></div>

        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Total AI cost" data={data["total_spend"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Cost per AI request" data={data["cost_per_request"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Cost per active user" data={data["cost_per_user"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StaticStat title="Profit margin (after AI costs)" value={margin_txt} note={margin_note} definition="How much of your subscription revenue is left after paying for AI usage costs." /></div>

        <div className="col-span-12 lg:col-span-5"><BarsTile title="Which AI model people choose" data={data["model_mix"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-4"><AreaTile title="AI usage (cost driver)" data={data["ai_requests_weekly"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-3"><StaticStat title="Plan limits" value="Free · Builder · Pro" note="Each plan gets a monthly AI budget (Free $1.33, Builder $4, Pro $10), a project limit (3/5/10), and a deploy limit (0/1/3). Subscription prices are set in our billing system." definition="The usage caps built into each pricing plan; the prices customers pay are managed in our billing system." /></div>

        {#* Burn spec §4 — the cost of the bet. Revenue side is external (Stripe). *#}
        <div className="col-span-12 lg:col-span-4"><StaticStat title="Cash runway" value="—" note="Not available yet — needs AI cost data plus your cash balance and subscription revenue to calculate how many months of cash you have left." definition="How many months your cash would last at the current pace of spending minus revenue." /></div>
        <div className="col-span-12 lg:col-span-4"><StaticStat title="Cost of heaviest users" value="—" note="Not available yet — turns on once detailed AI cost-tracking is switched on for the live product." definition="Total AI cost run up by the highest-spending 10% of users." /></div>
    </div>;
}
