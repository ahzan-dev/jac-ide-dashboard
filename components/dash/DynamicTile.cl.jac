# Registry-only chart dispatcher: the server's `chart` string -> an existing tile.
# The LLM never picks a raw component; it picks a metric, the server maps shape->chart,
# and this switch renders the same verified tiles the static pages use.
import from .StatTile { StatTile }
import from .ChartTiles {
    AreaTile, LineTile, VBarTile, BarsTile, DonutTile, TableTile,
    GaugeTile, FunnelTile, RetentionTile, StackBarTile
}

def:pub DynamicTile(chart: str, title: str, data: any, loading: bool) -> JsxElement {
    if chart == "compare" {
        # a single number vs a comparison period → StatTile (shows value + ±% delta badge)
        return <StatTile title={title} data={data} loading={loading} pinnable={False} />;
    }
    if chart == "gauge" {
        return <GaugeTile title={title} data={data} loading={loading} pinnable={False} />;
    }
    if chart == "area" {
        return <AreaTile title={title} data={data} loading={loading} pinnable={False} />;
    }
    if chart == "line" {
        return <LineTile title={title} data={data} loading={loading} pinnable={False} />;
    }
    if chart == "vbar" {
        return <VBarTile title={title} data={data} loading={loading} pinnable={False} />;
    }
    if chart == "bars" {
        return <BarsTile title={title} data={data} loading={loading} pinnable={False} />;
    }
    if chart == "donut" {
        return <DonutTile title={title} data={data} loading={loading} pinnable={False} />;
    }
    if chart == "table" {
        return <TableTile title={title} data={data} loading={loading} pinnable={False} />;
    }
    if chart == "funnel" {
        return <FunnelTile title={title} data={data} loading={loading} pinnable={False} />;
    }
    if chart == "retention" {
        return <RetentionTile title={title} data={data} loading={loading} pinnable={False} />;
    }
    if chart == "stackbar" {
        return <StackBarTile title={title} data={data} loading={loading} pinnable={False} />;
    }
    return <StatTile title={title} data={data} loading={loading} pinnable={False} />;
}
