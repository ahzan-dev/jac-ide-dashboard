sv import from ...metrics_sv { metrics_batch }
import from ..dash.util { cache_key, cache_get, cache_put, cacheable }
import from ..dash.StatTile { StatTile }
import from ..dash.ChartTiles { BarsTile, TableTile, Banner }

glob FEEDBACK_KEYS: list = ["problem_areas", "issue_categories", "rating_ratio", "issue_log", "ai_edits"];

def:pub FeedbackPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has data: dict = {};
    has loading: bool = True;
    has seen: int = -999;

    async def load(refresh: bool) {
        k = cache_key("feedback", env, date_from, date_to);
        hit = cache_get(k);
        if (hit is not None) and (not refresh) {
            data = hit as dict;
            loading = False;
            return;
        }
        loading = True;
        keys = FEEDBACK_KEYS;
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
        <div className="col-span-12"><Banner text="In-app feedback is live: thumbs ratings and the report-an-issue button both fire in production (low volume so far). The Issues & friction log below is the fullest picture — it counts every failure family, not just what users bothered to report. Surveys, support tickets, and feature requests are still tracked elsewhere." /></div>

        <div className="col-span-12 lg:col-span-6"><BarsTile title="Top problem areas (estimated)" data={data["problem_areas"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-6"><BarsTile title="Reported issues by type" data={data["issue_categories"]} loading={loading} /></div>

        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Helpful rate" data={data["rating_ratio"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="AI outputs manually edited" data={data["ai_edits"]} loading={loading} /></div>

        <div className="col-span-12"><TableTile title="Issues & friction log (all failure families)" data={data["issue_log"]} loading={loading} /></div>
    </div>;
}
