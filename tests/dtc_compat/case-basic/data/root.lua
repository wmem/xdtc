include("sub.lua")
include("patch.lua")
remove("modules.obsolete")

local detailTitleBeforeUpdate = get("modules.detail.title")
local secondLookupName = get("lookup.items.2.name") -- Lua arrays are 1-based.

update("modules.detail.title", "detail-updated-by-root")
update("meta", {
    extra = "added-by-update",
    detailTitleBeforeUpdate = detailTitleBeforeUpdate,
    secondLookupName = secondLookupName
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
        disabledItem = {
            enable = false,
            match = "detail.tpl",
            title = "should-not-render"
        },
        noEnableItem = {
            match = "detail.tpl",
            title = "should-not-render-too"
        }
    }
}
