local detail = get("modules.detail")
detail.patched_by_side_effect = "yes"

update_root({
    meta = {
        patched_by_side_effect = true
    }
})
