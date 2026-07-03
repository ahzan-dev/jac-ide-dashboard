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
        <div className="col-span-12"><Banner text="🔴 No dedicated feedback system yet. The only roadmap signals are behavioral (failures/friction) plus ai_issue_reported (PR #607, empty until users report). NPS / tickets / feature-requests live in external tools." /></div>

        <div className="col-span-12 lg:col-span-6"><BarsTile title="Top problem areas (proxy)" data={data["problem_areas"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-6"><BarsTile title="Reported issues by category" data={data["issue_categories"]} loading={loading} /></div>

        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Helpful rate (thumbs)" data={data["rating_ratio"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-9"><Banner text="What it needs, by source: in-product NPS/CSAT → PostHog Surveys · support tickets → Zendesk/Intercom · feature requests & roadmap → Canny/Linear (embed). None are instrumented today — a labelled gap beats a fabricated score." /></div>
    </div>;
}
