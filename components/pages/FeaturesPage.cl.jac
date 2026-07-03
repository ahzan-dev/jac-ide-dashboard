sv import from ...metrics_sv { metrics_batch }
import from ..dash.ChartTiles { BarsTile, TableTile, Banner }

glob FEATURES_KEYS: list = ["top_features", "feature_table"];

def:pub FeaturesPage(env: str, date_from: str, date_to: str, refresh_n: int) -> JsxElement {
    has data: dict = {};
    has loading: bool = True;
    has seen: int = -999;

    async def load(refresh: bool) {
        loading = True;
        keys = FEATURES_KEYS;
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
        <div className="col-span-12"><Banner text="Real feature set only — no fictional per-feature/per-language breakdowns (JacCoder is one agent). Several surfaces are tier-gated (Free = 0 deploys, no folder-upload/community), so low numbers ≠ low interest." /></div>
        <div className="col-span-12 lg:col-span-5"><BarsTile title="Feature adoption" data={data["top_features"]} loading={loading} /></div>
        <div className="col-span-12 lg:col-span-7"><TableTile title="Feature table" data={data["feature_table"]} loading={loading} /></div>
    </div>;
}
