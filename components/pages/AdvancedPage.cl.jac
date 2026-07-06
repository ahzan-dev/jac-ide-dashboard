sv import from ...metrics_sv { metrics_batch }
import from ..dash.StatTile { StatTile }
import from ..dash.ChartTiles { AreaTile, BarsTile, FunnelTile, StackBarTile, StaticStat, Banner }
import from ..dash.HogqlBox { HogqlBox }

glob ADVANCED_KEYS: list = ["churn_risk", "ai_baseline", "ai_fail_reasons", "funnel", "lifecycle", "daily_ai"];

def:pub AdvancedPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has data: dict = {};
    has loading: bool = True;
    has seen: int = -999;

    async def load(refresh: bool) {
        loading = True;
        keys = ADVANCED_KEYS;
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
        <div className="col-span-12"><Banner text="Rule-based analytics — heuristics (thresholds, ±σ baselines, named cohorts), not ML. Prompt clustering is blocked (prompt text is masked, never captured)." /></div>

        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Accounts at risk" data={data["churn_risk"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StatTile title="Daily AI baseline" data={data["ai_baseline"]} loading={loading} /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StaticStat title="Prompt clustering" value="—" note="Blocked: prompt text is masked and never captured. Needs new instrumentation + privacy review." definition="Grouping prompts by intent/topic." /></div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3"><StaticStat title="AI insights" value="—" note="byLLM one-shot summary (planned) — will be labelled 'generated'." definition="LLM-authored narrative over the metrics." /></div>

        <div className="col-span-12 lg:col-span-8"><StackBarTile title="User lifecycle" data={data["lifecycle"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-4"><FunnelTile title="Activation funnel" data={data["funnel"]} loading={loading} /></div>

        <div className="col-span-12 lg:col-span-6"><BarsTile title="Top failure reasons" data={data["ai_fail_reasons"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-6"><AreaTile title="AI volume (daily)" data={data["daily_ai"]} loading={loading} /></div>

        <div className="col-span-12"><HogqlBox /></div>
    </div>;
}
