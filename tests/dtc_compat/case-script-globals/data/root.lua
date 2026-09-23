include("child.lua")
updateRoot({
    meta = {
        fromInstallTest = true
    }
})
return {
    rootOnly = true
}
