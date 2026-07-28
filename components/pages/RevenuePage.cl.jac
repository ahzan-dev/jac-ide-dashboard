# Revenue / Monetization — the money loop's sidebar home (plan §2.1).
# Everything here is backed by LIVE events verified in prod (2026-07-28 probe):
# upgrade_checkout_clicked (136/30d), upgrade_checkout_succeeded (92, ships since
# 2026-07-22), topup_checkout_clicked (40) + Stripe MRR via billing_summary.
# Deliberately ABSENT: MRR churn — subscription_canceled has zero prod events,
# so the tile would be a fake; it gets added when the event ships (banner says so).
sv import from ...metrics_sv { metrics_batch }
sv import from ...billing_sv { billing_summary }
import from ..dash.StatTile { StatTile }
import from ..dash.ChartTiles { TableTile, BarsTile, StaticStat, Banner }
import from ..dash.util { cache_key, cache_get, cache_put, cacheable, inflight_start, inflight_end }

glob REVENUE_KEYS: list = ["paid_upgrades", "upgrade_conversion", "upgrades_detail", "checkout_outcomes", "total_spend"];

def:pub RevenuePage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has data: dict = {};
    has billing: dict = {};
    has loading: bool = True;
    has seen: int = -999;

    async def load(refresh: bool) {
        k = cache_key("revenue", env, date_from, date_to);
        hit = cache_get(k);
        if (hit is not None) and (not refresh) {
            h = hit as dict;
            data = h["data"] as dict;
            billing = h["billing"] as dict;
            loading = False;
            return;
        }
        loading = True;
        keys = REVENUE_KEYS;
        if (not inflight_start(k)) and (not refresh) {
            return;
        }
        res = await metrics_batch(keys, env, date_from, date_to, refresh);
        inflight_end(k);
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

    # MRR + margin — same guarded computation as the Cost page (never fake a
    # 100% margin when one half is missing).
    avail = (billing["available"] as bool) if billing else False;
    mrr = billing["mrr"] if billing else None;
    subs = billing["active_subs"] if billing else 0;
    mrr_txt = "—";
    mrr_note = "Awaiting Stripe (STRIPE_SECRET_KEY).";
    if avail and (mrr is not None) {
        mrr_txt = "$" + str(mrr) + "/mo";
        mrr_note = str(subs) + " active subscriptions — live from Stripe, not events.";
    } elif billing {
        mrr_note = str(billing["reason"]);
    }
    ts = data["total_spend"] if data else None;
    spend = ts["value"] if ts else None;
    margin_txt = "—";
    margin_note = "Needs Stripe MRR and metered AI spend.";
    if avail and (mrr is not None) and ((mrr as float) > 0.0) {
        m = mrr as float;
        if spend is not None {
            sp = spend as float;
            margin_txt = str(int(round((m - sp) / m * 100.0))) + "%";
            margin_note = "Live: $" + str(mrr) + "/month subscriptions minus $" + str(spend) + " AI cost this period.";
        } else {
            margin_note = "MRR is live but AI spend for this window is unavailable — refusing to show a fake 100%.";
        }
    } elif billing {
        margin_note = str(billing["reason"]);
    }

    return <div className="grid grid-cols-12 gap-4">
        <div className="col-span-12"><Banner text="The money loop, end-to-end: checkout clicks → completed paid upgrades (live since 2026-07-22) → MRR from Stripe. Not shown yet: MRR churn — subscription_canceled has never fired in production, so that tile appears only once the event ships (no invented numbers)." /></div>

        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StaticStat title="MRR (Stripe)" value={mrr_txt} note={mrr_note} definition="Monthly recurring revenue from active subscriptions, read live from Stripe." /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Completed upgrades" data={data["paid_upgrades"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Upgrade conversion" data={data["upgrade_conversion"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StaticStat title="Profit margin (after AI costs)" value={margin_txt} note={margin_note} definition="How much of subscription revenue is left after AI usage costs." /></div>

        <div className="col-span-12 lg:col-span-5"><BarsTile title="Checkout activity" data={data["checkout_outcomes"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-7"><TableTile title="Completed upgrades (row level)" data={data["upgrades_detail"]} loading={loading} /></div>
    </div>;
}
