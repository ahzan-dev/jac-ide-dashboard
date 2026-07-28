sv import from ...metrics_sv { metrics_batch, ask_feedback_list }
import from ..dash.util { cache_key, cache_get, cache_put, cacheable, inflight_start, inflight_end }
import from ..dash.StatTile { StatTile }
import from ..dash.ChartTiles { BarsTile, TableTile, Banner }

glob FEEDBACK_KEYS: list = ["rating_ratio", "issue_log"];

def:pub FeedbackPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has data: dict = {};
    has fb: dict = {};
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
        if (not inflight_start(k)) and (not refresh) {
            return;
        }
        res = await metrics_batch(keys, env, date_from, date_to, refresh);
        inflight_end(k);
        data = res as dict;
        if cacheable(data, keys) { cache_put(k, data); }
        loading = False;
    }
    async def load_fb() -> None {
        try {
            fb = (await ask_feedback_list()) as dict;
        } except Exception {
            fb = {};
        }
    }
    async can with (env, date_from, date_to, refresh_n) entry {
        refresh = (refresh_n != seen) and (seen != -999);
        seen = refresh_n;
        await load(refresh);
        await load_fb();
    }

    # Fabricate a tile-shaped result for the ask-feedback log (server-graph data,
    # not a PostHog metric — no meta.key, so no pin button).
    ups = (fb.get("ups", 0) or 0) as int;
    downs = (fb.get("downs", 0) or 0) as int;
    fb_title = "Ask answer feedback (" + str(ups) + " up / " + str(downs) + " down)";
    fb_data = {"columns": fb.get("columns", []), "rows": fb.get("rows", []), "value": None,
        "series": [], "error": "",
        "meta": {"definition": "Thumbs left on Ask (AI builder) answers by dashboard users.",
                 "window": "all time",
                 "caveat": "The prompt-optimization loop: a down-vote row carries the exact question, the planner's mode, and the generated SQL — review recurring misses and turn them into eval scenarios / planner-prompt fixes.",
                 "env": env, "unit": "", "good_when_up": True, "cached": False}};

    return <div className="grid grid-cols-12 gap-4">
        <div className="col-span-12"><Banner text="In-app feedback is live: thumbs ratings and the report-an-issue button both fire in production (low volume so far). The Issues & friction log below is the fullest picture — it counts every failure family, not just what users bothered to report. Surveys, support tickets, and feature requests are still tracked elsewhere." /></div>


        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Helpful rate" data={data["rating_ratio"]} loading={loading} /></div>

        <div className="col-span-12"><TableTile title="Issues & friction log (all failure families)" data={data["issue_log"]} loading={loading} /></div>

        {if len((fb.get("rows", []) or []) as list) > 0 {
            <div className="col-span-12"><TableTile title={fb_title} data={fb_data} loading={False} /></div>
        }}
    </div>;
}
