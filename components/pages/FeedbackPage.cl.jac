sv import from ...metrics_sv { metrics_batch }
import from ..dash.StatTile { StatTile }
import from ..dash.ChartTiles { BarsTile, Banner }

glob FEEDBACK_KEYS: list = ["problem_areas", "issue_categories", "rating_ratio"];

def:pub FeedbackPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has data: dict = {};
    has loading: bool = True;
    has seen: int = -999;

    async def load(refresh: bool) {
        loading = True;
        keys = FEEDBACK_KEYS;
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
        <div className="col-span-12"><Banner text="We don't yet have a dedicated way for users to give feedback. What's below is inferred from behavior (failures and friction) plus a user-reported-issues feature that hasn't launched yet — it stays empty until it does. Customer satisfaction surveys, support tickets, and feature requests are tracked elsewhere, not here." /></div>

        <div className="col-span-12 lg:col-span-6"><BarsTile title="Top problem areas (estimated)" data={data["problem_areas"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-6"><BarsTile title="Reported issues by type" data={data["issue_categories"]} loading={loading} /></div>

        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Helpful rate" data={data["rating_ratio"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-9"><Banner text="To build a real feedback picture we'd need: in-app satisfaction surveys, a support-ticket system, and a place to collect feature requests. None of these are connected yet. We'd rather show an honest 'we don't have this yet' than a made-up score." /></div>
    </div>;
}
