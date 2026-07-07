sv import from ...metrics_sv { metrics_batch }
sv import from ...billing_sv { billing_summary }
import from ..dash.StatTile { StatTile }
import from ..dash.ChartTiles { AreaTile, BarsTile, StaticStat, Banner }

glob COST_KEYS: list = ["metered_rows", "total_spend", "cost_per_request", "cost_per_user", "model_mix", "ai_requests_weekly"];

def:pub CostPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has data: dict = {};
    has billing: dict = {};
    has loading: bool = True;
    has seen: int = -999;

    async def load(refresh: bool) {
        loading = True;
        keys = COST_KEYS;
        res = await metrics_batch(keys, env, date_from, date_to, refresh);
        data = res as dict;
        bill = await billing_summary();
        billing = bill as dict;
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
    margin_note = "Needs tier prices (Stripe) vs metered cost. Prices live in Stripe, not code.";
    if avail and (mrr is not None) and ((mrr as float) > 0.0) {
        m = mrr as float;
        if spend is not None {
            sp = spend as float;
            margin_txt = str(int(round((m - sp) / m * 100.0))) + "%";
            margin_note = "Live: MRR $" + str(mrr) + "/mo − metered spend $" + str(spend) + " (selected window).";
        } else {
            margin_txt = "—";
            margin_note = "MRR is live ($" + str(mrr) + "/mo, " + str(subs) + " active subs), but metered cost isn't captured on prod yet — a real margin can't be computed (treating missing cost as 0 would show a false 100%).";
        }
    } elif billing {
        margin_note = str(billing["reason"]);
    }

    return <div className="grid grid-cols-12 gap-4">
        <div className="col-span-12"><Banner text={"Revenue is live — Stripe MRR now feeds the Gross-margin tile. Cost side is still partial: ai_generation_metered has started emitting, but the rows aren't tagged environment='prod' (nor a prod $host), so the prod env-filter excludes them and the spend tiles read n/a. Prod-filtered metered rows (90d): " + metered_txt + ". Fix: stamp the backend metered event with environment (or add its host to the prod allowlist) — then Total spend / Cost-per tiles and a real margin light up."} /></div>

        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Total spend" data={data["total_spend"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Cost / request" data={data["cost_per_request"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Cost / spender" data={data["cost_per_user"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StaticStat title="Gross margin" value={margin_txt} note={margin_note} definition="(MRR − metered cost) ÷ MRR." /></div>

        <div className="col-span-12 lg:col-span-5"><BarsTile title="Model mix (proxy)" data={data["model_mix"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-4"><AreaTile title="AI volume (cost driver)" data={data["ai_requests_weekly"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-3"><StaticStat title="Tier limits" value="Free · Builder · Pro" note="AI budget $1.33 / $4 / $10 · projects 3/5/10 · deploys 0/1/3 · credits = usd×150. $ prices live in Stripe." definition="Spend caps from TIER_LIMITS (code); dollar prices are in Stripe." /></div>

        {#* Burn spec §4 — the cost of the bet. Revenue side is external (Stripe). *#}
        <div className="col-span-12 lg:col-span-4"><StaticStat title="Burn rate + runway" value="—" note="'The clock everything races.' Needs metered spend (PostHog, gated) + cash balance & MRR (Stripe). Add STRIPE_SECRET_KEY to activate." definition="Months of runway = cash ÷ (spend − revenue)." /></div>
        <div className="col-span-12 lg:col-span-4"><StaticStat title="Power-user cost" value="—" note="Top-decile spend from ai_generation_metered — activates with POSTHOG_PROJECT_TOKEN on the prod pod." definition="Σ cost_usd of the top 10% of spenders." /></div>
    </div>;
}
