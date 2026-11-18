--[[
Year in Pages: a yearly reading recap for KOReader.

Reads the Reading statistics database, writes the recap as an HTML book in
"<home folder>/Year in Pages/", and opens it.
]]

local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

-- Our own modules must be required while the plugin loader has this
-- folder on package.path, so they load here at the top.
local Render = require("yip_render")
local Stats = require("yip_stats")

local YearInPages = WidgetContainer:extend{
    name = "yearinpages",
    is_doc_only = false,
}

function YearInPages:init()
    self.ui.menu:registerToMainMenu(self)
end

function YearInPages:addToMainMenu(menu_items)
    menu_items.yearinpages = {
        text = _("Year in Pages (reading recap)"),
        sorting_hint = "tools",
        callback = function()
            self:showYearPicker()
        end,
    }
end

local function dbPath()
    return DataStorage:getSettingsDir() .. "/statistics.sqlite3"
end

-- Wraps ljsqlite3's column-major result sets as an array of rows.
local function makeQuery(conn)
    return function(sql)
        local res, nrow = conn:exec(sql)
        local rows = {}
        if not res then return rows end
        nrow = tonumber(nrow) or 0
        local ncol = #res
        for i = 1, nrow do
            local row = {}
            for j = 1, ncol do
                local v = res[j][i]
                if type(v) == "cdata" then v = tonumber(v) end
                row[j] = v
            end
            rows[i] = row
        end
        return rows
    end
end

function YearInPages:withDatabase(fn)
    if lfs.attributes(dbPath(), "mode") ~= "file" then
        UIManager:show(InfoMessage:new{
            text = _("No reading statistics found yet.\n\nTurn on the Reading statistics plugin (Tools tab), read a little, and come back."),
        })
        return
    end
    -- Save the pages of the book that is open right now, if any.
    if self.ui.statistics and self.ui.statistics.insertDB then
        pcall(self.ui.statistics.insertDB, self.ui.statistics)
    end
    local SQ3 = require("lua-ljsqlite3/init")
    local ok_open, conn = pcall(SQ3.open, dbPath(), "ro")
    if not ok_open or not conn then
        logger.warn("YearInPages: could not open statistics database", conn)
        UIManager:show(InfoMessage:new{ text = _("Could not open the reading statistics database.") })
        return
    end
    local ok, result = pcall(fn, makeQuery(conn))
    conn:close()
    if not ok then
        logger.warn("YearInPages: failed", result)
        UIManager:show(InfoMessage:new{ text = T(_("Could not build the recap:\n%1"), tostring(result)) })
        return
    end
    return result
end

function YearInPages:showYearPicker()
    local years = self:withDatabase(Stats.years)
    if not years then return end
    if #years == 0 then
        UIManager:show(InfoMessage:new{ text = _("No reading recorded yet. Read a little and come back.") })
        return
    end
    if #years == 1 then
        self:build(years[1])
        return
    end
    local dialog
    local buttons = {}
    for i = 1, math.min(#years, 8) do
        local year = years[i]
        table.insert(buttons, {{
            text = tostring(year),
            callback = function()
                UIManager:close(dialog)
                self:build(year)
            end,
        }})
    end
    dialog = ButtonDialog:new{
        title = _("Which year?"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(dialog)
end

local function outputDir()
    local home = G_reader_settings:readSetting("home_dir") or DataStorage:getDataDir()
    local dir = home .. "/Year in Pages"
    if lfs.attributes(dir, "mode") ~= "directory" then
        lfs.mkdir(dir)
    end
    return dir
end

function YearInPages:build(year)
    local html = self:withDatabase(function(query)
        return Render.html(Stats.collect(query, year))
    end)
    if not html then return end

    local path = string.format("%s/Year in Pages %d.html", outputDir(), year)
    local f, err = io.open(path, "w")
    if not f then
        UIManager:show(InfoMessage:new{ text = T(_("Could not save the recap:\n%1"), tostring(err)) })
        return
    end
    f:write(html)
    f:close()
    logger.info("YearInPages: wrote", path)
    self:open(path)
end

function YearInPages:open(path)
    if self.ui.document and self.ui.switchDocument then
        self.ui:switchDocument(path)
    else
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(path)
    end
end

return YearInPages
