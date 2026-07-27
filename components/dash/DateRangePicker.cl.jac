import from ..ui.input { Input }
import from .util { local_to_utc, utc_to_local_input }

# Inline range picker, minute precision (P4): two native datetime-local inputs
# (browser-native calendars — no Popover/Calendar, those freeze this build).
# Displays the viewer's LOCAL time; emits UTC upward, so named windows and
# sub-day ranges round-trip without blanking the inputs (the old type=date
# quirk). Accepts incoming state as bare dates (UTC midnight) or UTC datetimes.
def _to_input(v: str) -> str {
    s = v.strip();
    if len(s) == 10 {
        s = s + " 00:00:00";
    }
    return utc_to_local_input(s);
}

def:pub DateRangePicker(date_from: str, date_to: str, on_change: Callable[[str, str], None]) -> JsxElement {
    def on_from(e: ChangeEvent) {
        v = str(e.target.value);
        if v != "" {
            on_change(local_to_utc(v), date_to);
        }
    }
    def on_to(e: ChangeEvent) {
        v = str(e.target.value);
        if v != "" {
            on_change(date_from, local_to_utc(v));
        }
    }
    from_val = _to_input(date_from);
    to_val = _to_input(date_to);
    return <div className="flex items-center gap-1.5">
        <Input type="datetime-local" value={from_val} onChange={on_from} className="h-8 w-[176px] text-xs tabular-nums" />
        <span className="text-xs text-muted-foreground">→</span>
        <Input type="datetime-local" value={to_val} onChange={on_to} className="h-8 w-[176px] text-xs tabular-nums" />
    </div>;
}
