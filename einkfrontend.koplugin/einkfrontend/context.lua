-- Original implementation. SPDX-License-Identifier: AGPL-3.0-or-later
-- Shared visibility/activation contract. A common renderer does not imply that
-- every action belongs on every page. Check again when opening and navigating.
local Context = {}
function Context.alive(app)
    return app and app.plugin and app.plugin.active and app.adapter:alive()
end
function Context.allowed(app, key, widget)
    if not Context.alive(app) then return false end
    local model = app.screen and app.screen.model
    local route = app.stack[#app.stack]
    if key=='settings_popup' or key=='library_popup' or key=='page_search' then
        if not model or model.route~=route then return false end
        if widget and widget._eink_route~=route then return false end
        if key=='settings_popup' then return model.settings==true and route.id=='settings' end
        if key=='page_search' then
            return model.settings==true and ({collection_manager=true,collection_members=true,book_collections=true})[route.id]==true
        end
        return model.library==true
    end
    if key=='reader_panel' or key=='reader_topbar' or key=='book_statistics' or key=='navigation' then
        return app.plugin.ui.document~=nil
    end
    return key=='controls' or key=='home_editor'
end
return Context
