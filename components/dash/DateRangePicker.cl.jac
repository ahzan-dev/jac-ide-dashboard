import from ..ui.input { Input }

# Inline date-range picker: two native date inputs (each opens the browser's own calendar).
# No Popover/Calendar component — those freeze the renderer in this jac-shadcn build.
def:pub DateRangePicker(date_from: str, date_to: str, on_change: Callable[[str, str], None]) -> JsxElement {
    def on_from(e: ChangeEvent) {
        on_change(e.target.value, date_to);
    }
    def on_to(e: ChangeEvent) {
        on_change(date_from, e.target.value);
    }
    return <div className="flex items-center gap-1.5">
        <Input type="date" value={date_from} onChange={on_from} className="h-8 w-[136px] text-xs tabular-nums" />
        <span className="text-xs text-muted-foreground">→</span>
        <Input type="date" value={date_to} onChange={on_to} className="h-8 w-[136px] text-xs tabular-nums" />
    </div>;
}
