include("sub.lua")
include("patch.lua")
include("sub.lua") -- duplicate include is intentionally ignored

remove("modules.obsolete")
local detail_title_before_update = get("modules.detail.title")
local second_lookup_name = get("lookup.items.2.name") -- Lua arrays are 1-based

update("modules.detail.title", "detail-updated-by-root")
update("meta", {
    extra = "added-by-update",
    detail_title_before_update = detail_title_before_update,
    second_lookup_name = second_lookup_name
})
replace("docs.item.note", "created-before-merge")

return {
    meta = {
        version = "1.0.0"
    },
    modules = {
        enable = true,
        match = "main.tpl",
        title = "main-from-root"
    },
    docs = {
        item = {
            enable = true,
            match = "detail.tpl",
            title = "detail-from-root"
        },
        disabled_item = {
            enable = false,
            match = "detail.tpl",
            title = "should-not-render"
        }
    }
}
