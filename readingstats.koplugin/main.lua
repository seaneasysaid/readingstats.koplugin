-- readingstats.koplugin/main.lua
-- KOReader 插件：把「日历阅读统计」与「阅读分析」整合进顶部菜单（菜单模式调用）。
-- 由 userpatch（单文件补丁）改造而来，不再依赖 gestures/patches 目录，直接作为 koplugin 加载。

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _               = require("gettext")
local logger          = require("logger")
local CalendarStats   = require("calendar_stats")
local HeatmapView     = require("heatmap_view")
local ReadingInsights = require("reading_insights")
local ReadingStatsView = require("reading_stats_view")

local MENU_KEY = "reading_stats"

-- 兜底执行：KOReader 里菜单回调/动态子菜单一旦抛错，会直接把整个阅读器打回系统
-- （touchmenu 的 onMenuSelect 没有 pcall）。这里兜住，失败时记日志并弹提示，
-- 不影响其他功能。注意：绝不能用 `_` 当循环变量，否则会遮蔽上面的 gettext。
local function safeCall(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        logger.err("READINGSTATS: " .. label .. " failed: " .. tostring(err))
        pcall(function()
            local Notification = require("ui/widget/notification")
            Notification:notify(_("阅读足迹") .. "：" .. label .. " " .. _("执行失败"))
        end)
        return false, err
    end
    return true
end

-- 在本机（重度魔改版 KOReader）上，自定义菜单项要"能渲染"必须同时做两件事：
--   1) 把键加进 ui/elements/*_menu_order 的分组列表；
--   2) 把项注进 menu_items。
-- 这正是本机 2-quick-settings / 2--ui-font / 2-title-navbar 等补丁的做法。
-- 只写 sorting_hint 在本机解析不到顶级按钮，会注入了却不显示。
local function ensureInMenuOrder()
    for _i, mod_name in ipairs({
        "ui/elements/filemanager_menu_order",
        "ui/elements/reader_menu_order",
    }) do
        pcall(function()
            local order = require(mod_name)
            local tools = order and order.tools
            if type(tools) ~= "table" then return end
            for _j, k in ipairs(tools) do
                if k == MENU_KEY then return end -- 已插入，避免重复
            end
            -- 优先紧跟内置 statistics 之后，找不到就放分组最前面
            local pos = 1
            for i, k in ipairs(tools) do
                if k == "statistics" then pos = i + 1 break end
            end
            table.insert(tools, pos, MENU_KEY)
            logger.warn("READINGSTATS[diag]: inserted '" .. MENU_KEY .. "' into order of " .. mod_name .. " at pos " .. pos)
        end)
    end
end

local ReadingStats = WidgetContainer:extend{
    name = "readingstats",
}

-- KOReader 实例化插件时调用（self.ui 已被框架注入）
function ReadingStats:init()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
        logger.warn("READINGSTATS[diag]: init() ok, registered to main menu")
    else
        logger.warn("READINGSTATS[diag]: ui.menu NOT available at init time!")
    end
end

function ReadingStats:addToMainMenu(menu_items)
    -- 调用前先把统计落库，保证弹窗里看到的是最新数据
    local function withStatsFlush(show_fn)
        return function()
            local ui = self.ui
            if ui and ui.statistics and ui.statistics.insertDB then
                pcall(function() ui.statistics:insertDB() end)
            end
            show_fn()
        end
    end

    -- 子模块的设置菜单原本是"顶级项"（自带 sorting_hint="tools"）。
    -- 现在被嵌进「设置」里，顶级分组提示已无意义且可能引起误解，清掉它；
    -- 同时做浅拷贝，避免改动子模块自己的表。
    local cal_settings = nil
    if type(CalendarStats.settings_menu) == "table" then
        cal_settings = {}
        for k, v in pairs(CalendarStats.settings_menu) do cal_settings[k] = v end
        cal_settings.sorting_hint = nil
    else
        logger.err("READINGSTATS: calendar_stats.settings_menu 缺失或类型异常")
    end

    -- 阅读分析每页行数（7 / 8）设置项
    local rows_setting = {
        text_func = function()
            local s = G_reader_settings:readSetting("mini_ri_sett", {}) or {}
            return string.format(_("阅读分析每页行数（%d）"), s.items_per_page or 7)
        end,
        -- 动态子菜单：外面套 pcall，避免构造失败时把阅读器整个带崩
        sub_item_table_func = function()
            local ok, res = pcall(function()
                local sub = {}
                for _i, n in ipairs({ 7, 8 }) do
                    local rows = n
                    sub[#sub + 1] = {
                        text = tostring(rows) .. " " .. _("行"),
                        checked_func = function()
                            local s = G_reader_settings:readSetting("mini_ri_sett", {}) or {}
                            return (s.items_per_page or 7) == rows
                        end,
                        callback = function()
                            local s = G_reader_settings:readSetting("mini_ri_sett", {}) or {}
                            s.items_per_page = rows
                            G_reader_settings:saveSetting("mini_ri_sett", s)
                        end,
                    }
                end
                return sub
            end)
            if ok and type(res) == "table" then return res end
            logger.err("READINGSTATS: build rows_setting failed: " .. tostring(res))
            return {}
        end,
    }

    -- 入口名「阅读足迹」，与内置 statistics 插件的「阅读统计」区分
    -- 注意：这里不再使用 sorting_hint（本机解析不到顶级按钮），改为配合 order 定位
    menu_items[MENU_KEY] = {
        text = _("阅读足迹"),
        sub_item_table = {
            {
                text = _("阅读报告"),
                callback = withStatsFlush(function()
                    safeCall("阅读报告", function() ReadingStatsView.show(self.ui, "month", nil) end)
                end),
            },
            {
                text = _("日历阅读统计"),
                callback = withStatsFlush(function()
                    safeCall("日历阅读统计", function() CalendarStats.show() end)
                end),
            },
            {
                text = _("阅读热力图"),
                callback = withStatsFlush(function()
                    safeCall("阅读热力图", function() HeatmapView.show() end)
                end),
            },
            {
                text = _("阅读分析"),
                callback = withStatsFlush(function()
                    safeCall("阅读分析", function() ReadingInsights.show(self.ui) end)
                end),
            },
            {
                text = _("设置"),
                sub_item_table = {
                    CalendarStats.settings_menu,  -- 日历统计项选择 + 字号
                    HeatmapView.settings_menu,    -- 热力图跨度 26 / 52 周
                    rows_setting,
                },
            },
        },
    }

    -- 把键插进菜单 order，保证本机能渲染出来
    ensureInMenuOrder()

    logger.warn("READINGSTATS[diag]: addToMainMenu() ok; sub_item_table=",
        tostring(menu_items[MENU_KEY].sub_item_table ~= nil))
end

return ReadingStats
