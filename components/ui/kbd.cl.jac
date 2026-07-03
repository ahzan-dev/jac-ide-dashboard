import from ...lib.utils { cn }

def:pub Kbd(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <kbd
            data-slot="kbd"
            className={cn(
                "bg-muted text-muted-foreground in-data-[slot=tooltip-content]:bg-background/20 in-data-[slot=tooltip-content]:text-background dark:in-data-[slot=tooltip-content]:bg-background/10 h-5 w-fit min-w-5 gap-1 rounded-sm px-1 font-sans text-xs font-medium [&_svg:not([class*='size-'])]:size-3 pointer-events-none inline-flex items-center justify-center select-none",
                props["className"]
            )}
            {**attrs}
        >
            {props["children"]}
        </kbd>;
}

def:pub KbdGroup(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <kbd
            data-slot="kbd-group"
            className={cn("gap-1 inline-flex items-center", props["className"])}
            {**attrs}
        >
            {props["children"]}
        </kbd>;
}
