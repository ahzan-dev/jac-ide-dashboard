import from .ui.sidebar {
    SidebarProvider, Sidebar, SidebarContent, SidebarHeader, SidebarGroup,
    SidebarGroupLabel, SidebarGroupContent, SidebarMenu, SidebarMenuItem,
    SidebarMenuButton, SidebarInset, SidebarFooter, SidebarTrigger
}
import from .ui.select { Select, SelectTrigger, SelectValue, SelectContent, SelectGroup, SelectItem }
import from .ui.button { Button }
import from .ui.badge { Badge }
import from .ui.tooltip { TooltipProvider }
import from .pages.AskPage { AskPage }
import from .pages.PinnedPage { PinnedPage }
import from .pages.OverviewPage { OverviewPage }
import from .pages.UsersPage { UsersPage }
import from .pages.RequestsPage { RequestsPage }
import from .pages.AdvancedPage { AdvancedPage }
import from .pages.HealthPage { HealthPage }
import from .pages.FeaturesPage { FeaturesPage }
import from .pages.QualityPage { QualityPage }
import from .pages.FeedbackPage { FeedbackPage }
import from .pages.ImpactPage { ImpactPage }
import from .pages.CostPage { CostPage }
import from .pages.SettingsPage { SettingsPage }
import from .dash.DateRangePicker { DateRangePicker }
import from .dash.SavedViews { SavedViews }
import from .dash.util { iso_days_ago, iso_tomorrow }

# 11-page IA (label, page-key, readiness dot), grouped as in the prototype.
glob NAV: list = [
    {"group": "Dashboard", "items": [
        {"label": "Ask (AI builder)", "page": "ask", "dot": "✨"},
        {"label": "My Dashboard", "page": "pinned", "dot": "📌"},
        {"label": "Overview", "page": "overview", "dot": "🟢"}
    ]},
    {"group": "Product", "items": [
        {"label": "Users & Adoption", "page": "users", "dot": "🟢"},
        {"label": "Feature Usage", "page": "features", "dot": "🟡"},
        {"label": "Feedback & Roadmap", "page": "feedback", "dot": "🔴"}
    ]},
    {"group": "AI Intelligence", "items": [
        {"label": "AI Requests", "page": "requests", "dot": "🟢"},
        {"label": "AI Quality", "page": "quality", "dot": "🔴"},
        {"label": "Advanced Analytics", "page": "advanced", "dot": "🟢"}
    ]},
    {"group": "Business", "items": [
        {"label": "Developer Impact", "page": "impact", "dot": "🟡"},
        {"label": "Cost & Usage", "page": "cost", "dot": "🟡"}
    ]},
    {"group": "Operations", "items": [
        {"label": "System Health", "page": "health", "dot": "🟡"},
        {"label": "Settings & Data", "page": "settings", "dot": "🟡"}
    ]}
];

glob PAGE_TITLES: dict = {
    "ask": "Ask (AI builder)", "pinned": "My Dashboard",
    "overview": "Overview", "users": "Users & Adoption", "features": "Feature Usage",
    "feedback": "Feedback & Roadmap", "requests": "AI Requests", "quality": "AI Quality",
    "advanced": "Advanced Analytics", "impact": "Developer Impact", "cost": "Cost & Usage",
    "health": "System Health", "settings": "Settings & Data"
};

# Persist the active page across refresh (localStorage) so a reload returns you to
# the same page — e.g. the Ask builder with its last thread — instead of resetting to Overview.
glob _PAGE_KEY: str = "jachammer_active_page";

def _initial_page() -> str {
    try {
        raw = localStorage.getItem(_PAGE_KEY);
        if raw and PAGE_TITLES[raw] {
            return raw as str;
        }
    } except Exception as e {
        return "overview";
    }
    return "overview";
}
def _persist_page(pg: str) {
    try {
        localStorage.setItem(_PAGE_KEY, pg);
    } except Exception as e {
        return;
    }
}

def NavButton(label: str, dot: str, page: str, active: bool, on_select: Callable[[str], None]) -> JsxElement {
    def handle(e: MouseEvent) {
        on_select(page);
    }
    return <SidebarMenuButton isActive={active} onClick={handle}>
        <span className="text-xs">{dot}</span>
        <span>{label}</span>
    </SidebarMenuButton>;
}

def:pub AppShell(on_logout: Callable[[], None]) -> JsxElement {
    has env: str = "prod";
    has date_from: str = iso_days_ago(30);
    has date_to: str = iso_tomorrow();
    has refresh_n: int = 0;
    has active_page: str = _initial_page();

    def go(pg: str) {
        active_page = pg;
        _persist_page(pg);
    }
    def on_env(v: str) {
        env = v;
    }
    def on_range(f: str, t: str) {
        date_from = f;
        date_to = t;
    }
    def on_restore(pg: str, e: str, f: str, t: str) {
        active_page = pg;
        _persist_page(pg);
        env = e;
        date_from = f;
        date_to = t;
    }
    def on_refresh(e: MouseEvent) {
        refresh_n = refresh_n + 1;
    }
    def handle_logout(e: MouseEvent) {
        on_logout();
    }

    page_title = str(PAGE_TITLES[active_page]);

    return <TooltipProvider>
        <SidebarProvider>
            <Sidebar>
                <SidebarHeader>
                    <div className="flex items-center gap-2 px-2 py-1.5">
                        <div className="size-2.5 rounded-full bg-primary"></div>
                        <span className="text-sm font-semibold">JacHammer Analytics</span>
                    </div>
                </SidebarHeader>
                <SidebarContent>
                    {for grp in NAV {
                        <SidebarGroup key={str(grp["group"])}>
                            <SidebarGroupLabel>{str(grp["group"])}</SidebarGroupLabel>
                            <SidebarGroupContent>
                                <SidebarMenu>
                                    {for it in grp["items"] {
                                        <SidebarMenuItem key={str(it["page"])}>
                                            <NavButton label={str(it["label"])} dot={str(it["dot"])} page={str(it["page"])} active={active_page == it["page"]} on_select={go} />
                                        </SidebarMenuItem>
                                    }}
                                </SidebarMenu>
                            </SidebarGroupContent>
                        </SidebarGroup>
                    }}
                </SidebarContent>
                <SidebarFooter>
                    <div className="flex items-center justify-between gap-2 px-2 py-1">
                        <span className="text-[11px] text-muted-foreground">PostHog · 425465</span>
                        <Button variant="ghost" size="sm" onClick={handle_logout}>Log out</Button>
                    </div>
                </SidebarFooter>
            </Sidebar>

            <SidebarInset>
                <header className="flex flex-col gap-3 border-b border-border px-6 py-4 sm:flex-row sm:items-center sm:justify-between">
                    <div className="flex items-center gap-2">
                        <SidebarTrigger />
                        <div className="flex flex-col">
                            <div className="flex items-center gap-2">
                                <h1 className="text-lg font-semibold">{page_title}</h1>
                                <Badge variant="outline">Internal · read-only</Badge>
                            </div>
                            <p className="text-xs text-muted-foreground">JacHammer Analytics Dashboard</p>
                        </div>
                    </div>
                    <div className="flex flex-wrap items-center gap-2">
                        <Select value={env} onValueChange={on_env}>
                            <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
                            <SelectContent>
                                <SelectGroup>
                                    <SelectItem value="prod">Production</SelectItem>
                                    <SelectItem value="dev">Dev</SelectItem>
                                    <SelectItem value="preview">Preview</SelectItem>
                                    <SelectItem value="all">All envs</SelectItem>
                                </SelectGroup>
                            </SelectContent>
                        </Select>
                        <DateRangePicker date_from={date_from} date_to={date_to} on_change={on_range} />
                        <Button variant="outline" onClick={on_refresh}>Refresh</Button>
                    </div>
                </header>

                <div className="border-b border-border bg-muted/30 px-6 py-2 text-[11px] text-muted-foreground">
                    KPIs & trends follow the selected range (auto daily / weekly / monthly buckets) · cohorts (retention, lifecycle) use their own windows · env = {env} · prod is $host-allowlisted (super-property not emitted by prod yet).
                </div>

                <div className="flex items-center gap-2 border-b border-border px-6 py-2">
                    <SavedViews page={active_page} env={env} date_from={date_from} date_to={date_to} on_restore={on_restore} />
                </div>

                <main className="p-6">
                    {if active_page == "ask" {
                        <AskPage env={env} date_from={date_from} date_to={date_to} refresh_n={refresh_n} />
                    } elif active_page == "pinned" {
                        <PinnedPage env={env} date_from={date_from} date_to={date_to} refresh_n={refresh_n} />
                    } elif active_page == "overview" {
                        <OverviewPage env={env} date_from={date_from} date_to={date_to} refresh_n={refresh_n} />
                    } elif active_page == "users" {
                        <UsersPage env={env} date_from={date_from} date_to={date_to} refresh_n={refresh_n} />
                    } elif active_page == "requests" {
                        <RequestsPage env={env} date_from={date_from} date_to={date_to} refresh_n={refresh_n} />
                    } elif active_page == "advanced" {
                        <AdvancedPage env={env} date_from={date_from} date_to={date_to} refresh_n={refresh_n} />
                    } elif active_page == "features" {
                        <FeaturesPage env={env} date_from={date_from} date_to={date_to} refresh_n={refresh_n} />
                    } elif active_page == "health" {
                        <HealthPage env={env} date_from={date_from} date_to={date_to} refresh_n={refresh_n} />
                    } elif active_page == "quality" {
                        <QualityPage env={env} date_from={date_from} date_to={date_to} refresh_n={refresh_n} />
                    } elif active_page == "feedback" {
                        <FeedbackPage env={env} date_from={date_from} date_to={date_to} refresh_n={refresh_n} />
                    } elif active_page == "impact" {
                        <ImpactPage env={env} date_from={date_from} date_to={date_to} refresh_n={refresh_n} />
                    } elif active_page == "cost" {
                        <CostPage env={env} date_from={date_from} date_to={date_to} refresh_n={refresh_n} />
                    } else {
                        <SettingsPage env={env} date_from={date_from} date_to={date_to} refresh_n={refresh_n} />
                    }}
                </main>
            </SidebarInset>
        </SidebarProvider>
    </TooltipProvider>;
}
