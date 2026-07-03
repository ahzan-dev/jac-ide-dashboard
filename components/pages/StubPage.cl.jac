import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..ui.badge { Badge }

def:pub StubPage(title: str, readiness: str, note: str) -> JsxElement {
    return <div className="grid grid-cols-12 gap-4">
        <div className="col-span-12 lg:col-span-8">
            <Card>
                <CardHeader>
                    <div className="flex items-center gap-2">
                        <CardTitle>{title}</CardTitle>
                        <Badge variant="outline">{readiness}</Badge>
                    </div>
                    <CardDescription>Planned for a later build phase — shown as an honest stub, not a fabricated number.</CardDescription>
                </CardHeader>
                <CardContent>
                    <p className="text-sm text-muted-foreground">{note}</p>
                </CardContent>
            </Card>
        </div>
    </div>;
}
