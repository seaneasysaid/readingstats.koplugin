local Blitbuffer      = require("ffi/blitbuffer")
local Button          = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local DataStorage     = require("datastorage")
local db_location     = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
local Device          = require("device")
local Dispatcher      = require("dispatcher")
local FileManager     = require("apps/filemanager/filemanager")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LineWidget      = require("ui/widget/linewidget")
local OverlapGroup    = require("ui/widget/overlapgroup")
local ReaderFooter    = require("apps/reader/modules/readerfooter")
local ReaderUI        = require("apps/reader/readerui")
local Screen          = Device.screen
local Size            = require("ui/size")
local SQ3             = require("lua-ljsqlite3/init")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local Widget          = require("ui/widget/widget")
local logger          = require("logger")
local _ = require("gettext")
local N_ = _.ngettext

local FONT_BOLD = "NotoSans-Bold.ttf"
local FONT_REG  = "NotoSans-Regular.ttf"

local ColorBox = Widget:extend{ _w = 1, _h = 1, _bg = nil, _r = 0, _border = nil, _bw = 0 }

function ColorBox:init()
    self._w  = math.max(1, math.floor(tonumber(self._w) or 1))
    self._h  = math.max(1, math.floor(tonumber(self._h) or 1))
    self._r  = math.max(0, tonumber(self._r) or 0)
    self._bw = math.max(0, tonumber(self._bw) or 0)
    self.dimen = Geom:new{ w = self._w, h = self._h }
end

function ColorBox:paintTo(bb, x, y)
    if self._border and self._bw > 0 then
        local bw = math.max(1, math.floor(self._bw + 0.5))
        bb:paintRoundedRect(x, y, self._w, self._h, self._border, self._r)
        local iw = self._w - bw * 2
        local ih = self._h - bw * 2
        if iw > 0 and ih > 0 then
            local ir = self._r - bw
            if ir < 0 then ir = 0 end
            bb:paintRoundedRect(x + bw, y + bw, iw, ih, self._bg, ir)
        end
    else
        bb:paintRoundedRect(x, y, self._w, self._h, self._bg, self._r)
    end
end

local function colorBox(w, h, bg, r, border, bw)
    return ColorBox:new{ _w = w, _h = h, _bg = bg, _r = r or 0, _border = border, _bw = bw or 0 }
end

local function makeGray(v)
    local c
    if Blitbuffer.Color8 then
        local ok
        ok, c = pcall(Blitbuffer.Color8, v)
        if ok and c then return c end
    end
    if Blitbuffer.ColorRGB32 then
        local ok
        ok, c = pcall(Blitbuffer.ColorRGB32, v, v, v, 0xFF)
        if ok and c then return c end
    end
    return nil
end

local LIGHT_FILL  = makeGray(0xC8)
                 or Blitbuffer.COLOR_LIGHT_GRAY
                 or Blitbuffer.COLOR_GRAY_4
                 or Blitbuffer.COLOR_GRAY_3
local MEDIUM_FILL = makeGray(0x80)
                 or Blitbuffer.COLOR_GRAY_3
                 or Blitbuffer.COLOR_GRAY_4
local DARK_FILL   = makeGray(0x40)
                 or Blitbuffer.COLOR_GRAY_2
                 or Blitbuffer.COLOR_GRAY_1
                 or Blitbuffer.COLOR_GRAY_3
local DEEP_FILL   = makeGray(0x20)
                 or Blitbuffer.COLOR_GRAY_1
                 or Blitbuffer.COLOR_GRAY_2
                 or Blitbuffer.COLOR_BLACK

local SECS_DAY = 86400
local WHITE  = Blitbuffer.COLOR_WHITE
local BLACK  = Blitbuffer.COLOR_BLACK
local GRAY_4 = Blitbuffer.COLOR_GRAY_4 or Blitbuffer.COLOR_GRAY_3

local STAT_ORDER = {
    "today_time", "today_pages",
    "week_time", "week_pages",
    "month_time", "month_pages",
    "total_time", "total_pages",
    "streak",
}

local MAX_ITEMS_PER_ROW = 5

local FONT_SIZE_MIN = 1
local FONT_SIZE_MAX = 30
local FONT_SIZE_DEF = 18

local defaults = {
    serif = 1,
    items = { "today_time", "today_pages", "total_time", "week_pages", "week_time" },
    max_items = MAX_ITEMS_PER_ROW,
    font_size = FONT_SIZE_DEF,
}

local RS_SETT = G_reader_settings:readSetting("mini_rs_sett", defaults)
if type(RS_SETT) ~= "table" then RS_SETT = {} end
for k, v in pairs(defaults) do if RS_SETT[k] == nil then RS_SETT[k] = v end end
if type(RS_SETT.items) ~= "table" then RS_SETT.items = {} end
do
    local filtered = {}
    for _, v in ipairs(RS_SETT.items) do
        if v ~= "total_books" then filtered[#filtered + 1] = v end
    end
    RS_SETT.items = filtered
end
if #RS_SETT.items == 0 then
    RS_SETT.items = { "today_time", "today_pages", "total_time", "week_pages", "week_time" }
end
do
    local fs = tonumber(RS_SETT.font_size) or FONT_SIZE_DEF
    fs = math.floor(fs + 0.5)
    if fs < FONT_SIZE_MIN then fs = FONT_SIZE_MIN end
    if fs > FONT_SIZE_MAX then fs = FONT_SIZE_MAX end
    RS_SETT.font_size = fs
end

local function writeSettToDisk() G_reader_settings:saveSetting("mini_rs_sett", RS_SETT) end

local function isItemSelected(id)
    for _, v in ipairs(RS_SETT.items) do if v == id then return true end end
    return false
end

local function toggleItem(id)
    local cur = RS_SETT.items
    local new_items, found = {}, false
    for _, v in ipairs(cur) do
        if v == id then found = true else new_items[#new_items + 1] = v end
    end
    if not found then
        if #cur >= MAX_ITEMS_PER_ROW then return end
        new_items[#new_items + 1] = id
    end
    RS_SETT.items = new_items
    writeSettToDisk()
end

local function midnight(ts)
    local t = os.date("*t", ts or os.time())
    t.hour, t.min, t.sec = 0, 0, 0
    return os.time(t)
end

local _dim_fallback = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
local function daysInMonth(y, m)
    local ok, t = pcall(os.time, { year = y, month = m + 1, day = 0 })
    if ok and t then
        local d = tonumber(os.date("%d", t))
        if d and d >= 28 and d <= 31 then return d end
    end
    return _dim_fallback[m] or 30
end

local function dbOpen()
    local ok, conn = pcall(SQ3.open, db_location)
    if ok and conn then return conn end
    return nil
end

local function dbQuery(conn, sql)
    if not conn or not sql then return nil end
    local ok, res = pcall(function() return conn:exec(sql) end)
    if not ok or type(res) ~= "table" then
        local sql2 = sql:gsub("page_stat", "page_stat_data")
        if sql2 ~= sql then
            ok, res = pcall(function() return conn:exec(sql2) end)
        end
    end
    if not ok or type(res) ~= "table" then return nil end
    return res
end

-- ============================================================
-- 时间范围查询（修复：避免 date()/strftime() 函数导致索引失效）
-- ============================================================

local function todayRange()
    local s = midnight(os.time())
    return s, s + SECS_DAY
end

local function whereToday()
    local s, e = todayRange()
    return string.format("start_time >= %d AND start_time < %d", s, e)
end

local function weekRange()
    -- 以周一为一周开始
    local now   = os.time()
    local wday  = tonumber(os.date("%w", now))        -- 0=周日, 1=周一 ... 6=周六
    local offset = (wday == 0) and 6 or (wday - 1)
    local monday = midnight(now - offset * SECS_DAY)
    return monday, monday + 7 * SECS_DAY
end

local function whereThisWeek()
    local s, e = weekRange()
    return string.format("start_time >= %d AND start_time < %d", s, e)
end

local function monthRange(y, m)
    local start_ts = os.time{ year = y, month = m, day = 1, hour = 0, min = 0, sec = 0 }
    local ny, nm = y, m + 1
    if nm > 12 then nm = 1; ny = ny + 1 end
    local end_ts = os.time{ year = ny, month = nm, day = 1, hour = 0, min = 0, sec = 0 }
    return start_ts, end_ts
end

local function whereMonth(y, m)
    local s, e = monthRange(y, m)
    return string.format("start_time >= %d AND start_time < %d", s, e)
end

local function whereAll()
    return "1=1"
end

-- ============================================================
-- 统计查询（统一使用外部传入的 conn，去掉多余的 JOIN book）
-- ============================================================

local function queryStats(conn, where_clause)
    if not conn then return 0, 0 end
    local sql = string.format([[
        SELECT coalesce(sum(pages_read), 0),
               coalesce(sum(duration_seconds), 0)
        FROM (
            SELECT COUNT(DISTINCT page_stat.page) AS pages_read,
                   SUM(page_stat.duration)        AS duration_seconds
            FROM page_stat
            WHERE %s
            GROUP BY page_stat.id_book
        )
    ]], where_clause)
    local res = dbQuery(conn, sql)
    if not res or type(res[1]) ~= "table" or #res[1] == 0 then return 0, 0 end
    local pages = tonumber(res[1][1]) or 0
    local secs  = tonumber(res[2] and res[2][1]) or 0
    return secs, pages
end

local function queryStreak(conn)
    if not conn then return 0 end

    -- 限制范围：只查最近 10 年，避免全表 DISTINCT
    local cutoff = midnight(os.time()) - 3650 * SECS_DAY
    local sql = string.format([[
        SELECT DISTINCT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS ds
        FROM page_stat
        WHERE start_time >= %d
        ORDER BY ds DESC;
    ]], cutoff)

    local res = dbQuery(conn, sql)
    if not res or type(res[1]) ~= "table" or #res[1] == 0 then return 0 end

    local days = {}
    for i = 1, #res[1] do days[tostring(res[1][i])] = true end

    local cursor = midnight(os.time())
    if not days[os.date("%Y-%m-%d", cursor)] then cursor = cursor - SECS_DAY end
    local streak = 0
    while days[os.date("%Y-%m-%d", cursor)] do
        streak = streak + 1
        cursor = cursor - SECS_DAY
    end
    return streak
end

local function queryMonthlyDailyStats(conn, y, m)
    if not conn then return {} end
    local s, e = monthRange(y, m)
    local sql = string.format([[
        SELECT strftime('%%d', start_time, 'unixepoch', 'localtime') AS day,
               sum(duration) AS dur
        FROM page_stat
        WHERE start_time >= %d AND start_time < %d
        GROUP BY day;
    ]], s, e)
    local res = dbQuery(conn, sql)

    local daily = {}
    if res and type(res[1]) == "table" then
        for i = 1, #res[1] do
            local day  = tonumber(res[1][i])
            local secs = tonumber(res[2] and res[2][i]) or 0
            if day then daily[day] = secs end
        end
    end
    return daily
end

-- ============================================================
-- 统计聚合（一次连接，全部查完再关闭；含月每日数据）
-- ============================================================

local function fetchAllStats()
    local s   = {}
    local now = os.date("*t")

    local conn = dbOpen()
    if not conn then
        s.today_secs,  s.today_pages  = 0, 0
        s.week_secs,   s.week_pages   = 0, 0
        s.month_secs,  s.month_pages  = 0, 0
        s.total_secs,  s.total_pages  = 0, 0
        s.streak      = 0
        s.month_daily = {}
        return s
    end

    s.today_secs,  s.today_pages  = queryStats(conn, whereToday())
    s.week_secs,   s.week_pages   = queryStats(conn, whereThisWeek())
    s.month_secs,  s.month_pages  = queryStats(conn, whereMonth(now.year, now.month))
    s.total_secs,  s.total_pages  = queryStats(conn, whereAll())
    s.streak                      = queryStreak(conn)
    s.month_daily                 = queryMonthlyDailyStats(conn, now.year, now.month)

    pcall(function() conn:close() end)
    return s
end

-- 统计缓存：打开/关闭/翻月窗口时避免反复全表查询
local _stats_cache    = nil
local _stats_cache_ts = 0
local STATS_CACHE_TTL = 20   -- 秒

local function getStatsCached()
    local now = os.time()
    if _stats_cache and (now - _stats_cache_ts) < STATS_CACHE_TTL then
        return _stats_cache
    end
    _stats_cache    = fetchAllStats()
    _stats_cache_ts = now
    return _stats_cache
end

-- 非当前月份的缓存（跨窗口实例保留）
local _month_cache = {}

local function fmtTime(secs)
    secs = math.floor(secs or 0)
    if secs <= 0 then return "0m" end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h >= 1 then return string.format("%dh%dm", h, m) end
    return string.format("%dm", m)
end

local function fmtCellTime(secs)
    secs = math.floor(secs or 0)
    if secs <= 0 then return "" end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h >= 1 then
        return string.format("%dh%02dm", h, m)
    else
        return string.format("%dm", m)
    end
end

local function secsToTotalMinutes(secs)
    secs = tonumber(secs) or 0
    if secs <= 0 then return 0 end
    return math.floor(secs / 60)
end

local function cellFill(secs)
    local m = secsToTotalMinutes(secs)
    if m <= 0  then return WHITE       end
    if m <= 30 then return LIGHT_FILL  end
    if m <= 60 then return MEDIUM_FILL end
    if m <= 90 then return DARK_FILL   end
    return DEEP_FILL
end

local function cellTextColor(secs)
    local m = secsToTotalMinutes(secs)
    if m > 60 then return WHITE end
    return BLACK
end

local STAT_DEFS = {
    today_time  = { label = _("今日时长"), get = function(s) return fmtTime(s.today_secs) end,    sub = _("今日阅读时长") },
    today_pages = { label = _("今日页数"), get = function(s) return tostring(s.today_pages) end,  sub = _("今日阅读页数") },
    week_time   = { label = _("本周时长"), get = function(s) return fmtTime(s.week_secs) end,     sub = _("本周阅读时长") },
    week_pages  = { label = _("本周页数"), get = function(s) return tostring(s.week_pages) end,   sub = _("本周阅读页数") },
    month_time  = { label = _("本月时长"), get = function(s) return fmtTime(s.month_secs) end,    sub = _("本月阅读时长") },
    month_pages = { label = _("本月页数"), get = function(s) return tostring(s.month_pages) end,  sub = _("本月阅读页数") },
    total_time  = { label = _("累计时长"), get = function(s) return fmtTime(s.total_secs) end,    sub = _("累计阅读时长") },
    total_pages = { label = _("累计页数"), get = function(s) return tostring(s.total_pages) end,  sub = _("累计阅读页数") },
    streak      = {
        label = _("连续天数"),
        get   = function(s) return s.streak > 0 and tostring(s.streak) or "—" end,
        sub_fn = function(s)
            if s.streak == 0 then return _("暂无连续") end
            return N_("天连续", "天连续", s.streak)
        end,
    },
}

local calendar_stats_menu = {
    text = _("日历统计项"),
    sorting_hint = "tools",
    sub_item_table_func = function()
        local sub = {
            {
                text = _("显示的统计项"),
                help_text = _("勾选要显示在弹窗里的统计项。\n一行最多显示 5 个。"),
                sub_item_table_func = function()
                    local sub2 = {}
                    for _, id in ipairs(STAT_ORDER) do
                        local _id = id
                        sub2[#sub2 + 1] = {
                            text_func = function()
                                local base = STAT_DEFS[_id].label
                                if isItemSelected(_id) then return base end
                                local rem = MAX_ITEMS_PER_ROW - #RS_SETT.items
                                if rem <= 2 then return base .. string.format("  (%d left)", rem) end
                                return base
                            end,
                            checked_func   = function() return isItemSelected(_id) end,
                            keep_menu_open = true,
                            callback       = function() toggleItem(_id) end,
                        }
                    end
                    return sub2
                end,
            },
            {
                text_func = function()
                    return string.format(_("统计项字号（%d）"), RS_SETT.font_size or FONT_SIZE_DEF)
                end,
                help_text = _("调整弹窗中统计项文字的大小。\n范围 1 ~ 30。"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local spin = SpinWidget:new{
                        title_text = _("统计项字号"),
                        info_text  = _("范围 1 ~ 30"),
                        value      = RS_SETT.font_size or FONT_SIZE_DEF,
                        value_min  = FONT_SIZE_MIN,
                        value_max  = FONT_SIZE_MAX,
                        value_step = 1,
                        value_hold_step = 5,
                        default_value = FONT_SIZE_DEF,
                        callback = function(spin_widget)
                            local v = math.floor(tonumber(spin_widget.value) or FONT_SIZE_DEF)
                            if v < FONT_SIZE_MIN then v = FONT_SIZE_MIN end
                            if v > FONT_SIZE_MAX then v = FONT_SIZE_MAX end
                            RS_SETT.font_size = v
                            writeSettToDisk()
                            if touchmenu_instance and touchmenu_instance.updateItems then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    }
                    UIManager:show(spin)
                end,
            },
        }
        return sub
    end,
}



local CAL_BUDGET_ROWS = 6

local CalendarStatsWindow = InputContainer:extend { modal = true, name = "calendar_stats_window" }

function CalendarStatsWindow:init()
    self.ges_events = self.ges_events or {}
    self.key_events = self.key_events or {}

    local t = os.date("*t")
    if not self._view_year  then self._view_year  = t.year end
    if not self._view_month then self._view_month = t.month end

    if Device:hasKeys() then
        local any_group = Device.input and Device.input.group and Device.input.group.Any
        if any_group then
            self.key_events.AnyKeyPressed = { { any_group } }
        end
    end
    if Device:isTouchDevice() then
        local function rng() return Screen:getSize() end
        self.ges_events.Swipe = {
            GestureRange:new { ges = "swipe", range = rng }
        }
        self.ges_events.Tap = {
            GestureRange:new { ges = "tap", range = rng }
        }
        self.ges_events.MultiSwipe = {
            GestureRange:new { ges = "multiswipe", range = rng }
        }
    end

    self:_build()
end

-- 翻月：只传 view 年月；统计缓存和月份缓存都是模块级，无需透传
function CalendarStatsWindow:_switchTo(y, m)
    UIManager:close(self)
    local w = CalendarStatsWindow:new {
        _view_year   = y,
        _view_month  = m,
    }
    UIManager:show(w, "ui")
end

function CalendarStatsWindow:_prevMonth()
    local m = self._view_month - 1
    local y = self._view_year
    if m < 1 then m = 12; y = y - 1 end
    self:_switchTo(y, m)
end

function CalendarStatsWindow:_nextMonth()
    local m = self._view_month + 1
    local y = self._view_year
    if m > 12 then m = 1; y = y + 1 end
    self:_switchTo(y, m)
end

function CalendarStatsWindow:_build()
    local self_ref = self

    local face_cal_time = Font:getFace(FONT_REG,  14)
    local face_cal_date = Font:getFace(FONT_REG,  11)
    local face_cal_dow  = Font:getFace(FONT_REG,  12)
    local face_cal_hdr  = Font:getFace(FONT_REG,  18)
    local face_cal_title = Font:getFace(FONT_REG, 20)
    local face_cal_leg  = Font:getFace(FONT_REG,  14)

    -- 统计项使用模块级缓存（TTL 内复用，避免反复全表扫描）
    local stats = self._stats or getStatsCached()
    self._stats = stats

    local view_year, view_month = self._view_year, self._view_month

    local now_t      = os.date("*t")
    local is_current = (view_year == now_t.year and view_month == now_t.month)
    local mkey       = string.format("%04d-%02d", view_year, view_month)

    local calendar_month_secs, calendar_month_pages, monthly_daily
    if is_current then
        -- 当前月直接复用 fetchAllStats 里已经查好的数据
        calendar_month_secs  = stats.month_secs
        calendar_month_pages = stats.month_pages
        monthly_daily        = stats.month_daily or {}
    else
        local cached = _month_cache[mkey]
        if cached then
            calendar_month_secs  = cached.secs
            calendar_month_pages = cached.pages
            monthly_daily        = cached.daily
        else
            local conn = dbOpen()
            if conn then
                calendar_month_secs, calendar_month_pages =
                    queryStats(conn, whereMonth(view_year, view_month))
                monthly_daily = queryMonthlyDailyStats(conn, view_year, view_month)
                pcall(function() conn:close() end)
            else
                calendar_month_secs, calendar_month_pages = 0, 0
                monthly_daily = {}
            end
            _month_cache[mkey] = {
                secs  = calendar_month_secs,
                pages = calendar_month_pages,
                daily = monthly_daily,
            }
        end
    end

    local items = {}
    for _, id in ipairs(RS_SETT.items) do
        if STAT_DEFS[id] then items[#items + 1] = id end
        if #items >= MAX_ITEMS_PER_ROW then break end
    end
    local n = #items

    local SCR_W, SCR_H = Screen:getWidth(), Screen:getHeight()
    local FRAME_PAD    = Screen:scaleBySize(12)
    local TITLE_GAP    = Screen:scaleBySize(12)
    local VAL_LBL_GAP  = Screen:scaleBySize(6)
    local CAL_GAP      = Screen:scaleBySize(8)

    local CORNER_R     = Screen:scaleBySize(12)
    local CELL_R       = Screen:scaleBySize(5)

    local STATS_PAD_V  = Screen:scaleBySize(10)

    local function scaleLine(v)
        local s = Screen:scaleBySize(v)
        if s < 1 then s = 1 end
        return s
    end

    local FRAME_BORDER = scaleLine(0.6)
    local CELL_BW      = scaleLine(0.4)

    local LINE_W     = scaleLine(0.8)
    local SEP_GAP    = Screen:scaleBySize(15)
    local SEP_TOTAL  = 2 * SEP_GAP + LINE_W

    local function measureText(text, face)
        if not text or text == "" then text = " " end
        local ok, w = pcall(TextWidget.new, TextWidget, { text = text, face = face })
        if not ok or not w then return 0, 0 end
        local ok2, sz = pcall(function() return w:getSize() end)
        pcall(function() w:free() end)
        if not ok2 or not sz then return 0, 0 end
        return tonumber(sz.w) or 0, tonumber(sz.h) or 0
    end

    local function getItemValue(id)
        if id == "month_time" then return fmtTime(calendar_month_secs) end
        if id == "month_pages" then return tostring(calendar_month_pages) end
        local def = STAT_DEFS[id]
        return def and def.get(stats) or ""
    end

    local CAL_TARGET_CELL = Screen:scaleBySize(64)
    local cal_min_w       = CAL_TARGET_CELL * 7 + CAL_GAP * 6

    local items_per_row = math.max(1, math.min(n, MAX_ITEMS_PER_ROW))
    local item_w
    if n == 0 then
        item_w = cal_min_w
    else
        item_w = math.floor((cal_min_w - SEP_TOTAL * (items_per_row - 1)) / items_per_row)
        if item_w < Screen:scaleBySize(40) then item_w = Screen:scaleBySize(40) end
    end

    local BASE_VAL_SIZE = tonumber(RS_SETT.font_size) or FONT_SIZE_DEF
    BASE_VAL_SIZE = math.floor(BASE_VAL_SIZE + 0.5)
    if BASE_VAL_SIZE < FONT_SIZE_MIN then BASE_VAL_SIZE = FONT_SIZE_MIN end
    if BASE_VAL_SIZE > FONT_SIZE_MAX then BASE_VAL_SIZE = FONT_SIZE_MAX end
    local BASE_LBL_SIZE = math.max(1, math.floor(BASE_VAL_SIZE * 15 / 18 + 0.5))

    local face_val_base = Font:getFace(FONT_REG, BASE_VAL_SIZE)
    local face_lbl_base = Font:getFace(FONT_REG, BASE_LBL_SIZE)

    local max_content_w = 0
    for _, id in ipairs(items) do
        local def = STAT_DEFS[id]
        if def then
            local vs = getItemValue(id)
            local ls = def.label or ""
            local vw = select(1, measureText(vs, face_val_base))
            local lw = select(1, measureText(ls, face_lbl_base))
            local w = math.max(vw, lw)
            if w > max_content_w then max_content_w = w end
        end
    end

    local padding_w = Screen:scaleBySize(2)
    local usable_w = math.max(1, item_w - padding_w)
    local scale = 1
    if max_content_w > 0 then
        scale = usable_w / max_content_w
    end
    if scale > 1.0 then scale = 1.0 end
    if scale < 0.25 then scale = 0.25 end

    local val_size = math.max(1, math.floor(BASE_VAL_SIZE * scale + 0.5))
    local lbl_size = math.max(1, math.floor(BASE_LBL_SIZE * scale + 0.5))
    local face_val = Font:getFace(FONT_REG, val_size)
    local face_lbl = Font:getFace(FONT_REG, lbl_size)

    local content_h = (select(2, measureText("Ag", face_val)) or 0)
                    + VAL_LBL_GAP
                    + (select(2, measureText("Ag", face_lbl)) or 0)
    local item_h = content_h

    local stats_rows_w = item_w * items_per_row
                       + SEP_TOTAL * math.max(0, items_per_row - 1)

    local row_w_natural = stats_rows_w

    local title_pad_w   = Screen:scaleBySize(240)
    local screen_cap    = math.floor(math.min(SCR_W, SCR_H) * 0.98)
    local max_inner_w   = math.max(Screen:scaleBySize(240),
                                   screen_cap - FRAME_PAD * 2)

    local inner_w = math.max(row_w_natural, cal_min_w, title_pad_w)
    if inner_w > max_inner_w then inner_w = max_inner_w end
    if inner_w < cal_min_w    then inner_w = math.min(cal_min_w, max_inner_w) end

    local function buildColumnSeparator(height)
        local line_h = math.max(1, math.floor(height / 2))
        return HorizontalGroup:new {
            align = "center",
            HorizontalSpan:new { width = SEP_GAP },
            LineWidget:new {
                dimen = Geom:new { w = LINE_W, h = line_h },
                background = Blitbuffer.COLOR_GRAY,
            },
            HorizontalSpan:new { width = SEP_GAP },
        }
    end

    local function buildStatItem(id)
        local def = STAT_DEFS[id]
        if not def then
            return CenterContainer:new {
                dimen = Geom:new { w = item_w, h = item_h },
                TextWidget:new { text = " ", face = face_val },
            }
        end

        local val_str = getItemValue(id)
        local lbl_str = def.label or ""

        local val_w = TextBoxWidget:new {
            text = val_str, face = face_val, fgcolor = BLACK,
            width = item_w, alignment = "center",
        }
        local lbl_w = TextBoxWidget:new {
            text = lbl_str, face = face_lbl, fgcolor = BLACK,
            width = item_w, alignment = "center",
        }
        local content = VerticalGroup:new {
            align = "center", val_w,
            VerticalSpan:new { width = VAL_LBL_GAP }, lbl_w,
        }
        return CenterContainer:new {
            dimen = Geom:new { w = item_w, h = item_h },
            content,
        }
    end

    local rows_group = VerticalGroup:new { align = "center" }
    if n == 0 then
        rows_group[#rows_group + 1] = CenterContainer:new {
            dimen = Geom:new { w = inner_w, h = item_h },
            TextBoxWidget:new {
                text = _("未选择任何统计项"), face = face_val,
                fgcolor = BLACK, width = inner_w,
                alignment = "center",
            },
        }
    else
        local row = HorizontalGroup:new { align = "center" }
        for i, id in ipairs(items) do
            if i > 1 then
                row[#row + 1] = buildColumnSeparator(item_h)
            end
            row[#row + 1] = buildStatItem(id)
        end
        rows_group[#rows_group + 1] = row
    end

    local dim_days  = daysInMonth(view_year, view_month)
    local first_ts  = os.time { year = view_year, month = view_month, day = 1, hour = 0 }
    local wday1     = tonumber(os.date("%w", first_ts)) or 0
    local first_col = (wday1 == 0) and 7 or wday1

    local cell_side_w = math.floor((inner_w - CAL_GAP * 6) / 7)
    cell_side_w = math.max(cell_side_w, Screen:scaleBySize(28))

    local CAL_HDR_H    = Screen:scaleBySize(30)
    local CAL_DOW_H    = Screen:scaleBySize(18)
    local CAL_INNER_GP = Screen:scaleBySize(5)
    local CAL_BOTTOM_H = Screen:scaleBySize(22)

    local cards_h = item_h + STATS_PAD_V

    local avail_h = SCR_H - FRAME_PAD * 2
                  - TITLE_GAP
                  - cards_h - Screen:scaleBySize(14)
                  - CAL_HDR_H - CAL_INNER_GP
                  - CAL_DOW_H - Screen:scaleBySize(3)
                  - CAL_BOTTOM_H - CAL_INNER_GP
    avail_h = math.max(avail_h, Screen:scaleBySize(120))

    local cell_side_h = math.floor(
        (avail_h - (CAL_BUDGET_ROWS - 1) * CAL_GAP) / CAL_BUDGET_ROWS)
    cell_side_h = math.max(cell_side_h, Screen:scaleBySize(26))

    local cell_side = math.min(cell_side_w, CAL_TARGET_CELL)
    if cell_side > cell_side_h then
        local keep_min = math.floor(CAL_TARGET_CELL * 0.85)
        cell_side = math.max(cell_side_h, math.min(cell_side, keep_min))
    end

    local CELL_PAD_L = Screen:scaleBySize(5)

    local function buildDayCell(day, secs)
        local s = tonumber(secs) or 0

        local bg = cellFill(s)
        local fg = cellTextColor(s)

        if logger.dbg then
            local m = secsToTotalMinutes(s)
            local tier = "white"
            if m <= 0 then tier = "empty"
            elseif m <= 30 then tier = "light"
            elseif m <= 60 then tier = "medium"
            elseif m <= 90 then tier = "dark"
            else tier = "deep" end
            logger.dbg(string.format(
                "[calendar_stats] day=%s secs=%d total_min=%d tier=%s",
                tostring(day), math.floor(s), m, tier))
        end

        local time_str = fmtCellTime(s)

        local date_widget = TextWidget:new {
            text = tostring(day), face = face_cal_date, fgcolor = fg,
        }
        local time_widget = TextWidget:new {
            text = (time_str ~= "" and time_str or " "),
            face = face_cal_time, fgcolor = fg,
        }

        local date_w, date_h = 0, 0
        do
            local ok, sz = pcall(function() return date_widget:getSize() end)
            if ok and sz then
                date_w = tonumber(sz.w) or 0
                date_h = tonumber(sz.h) or 0
            end
        end
        local time_w, time_h = 0, 0
        do
            local ok, sz = pcall(function() return time_widget:getSize() end)
            if ok and sz then
                time_w = tonumber(sz.w) or 0
                time_h = tonumber(sz.h) or 0
            end
        end

        local right_fill = math.max(0, cell_side - CELL_PAD_L - date_w)
        local date_row = HorizontalGroup:new {
            align = "center",
            HorizontalSpan:new { width = CELL_PAD_L },
            date_widget,
            HorizontalSpan:new { width = right_fill },
        }

        local time_row = CenterContainer:new {
            dimen = Geom:new { w = cell_side, h = math.max(1, time_h) },
            time_widget,
        }

        local inner_gap = Screen:scaleBySize(1)
        local inner = VerticalGroup:new {
            align = "center",
            date_row,
            VerticalSpan:new { width = inner_gap },
            time_row,
        }

        local inner_cc = CenterContainer:new {
            dimen = Geom:new { w = cell_side, h = cell_side },
            inner,
        }

        local bg_box = colorBox(cell_side, cell_side, bg, CELL_R, BLACK, CELL_BW)

        return OverlapGroup:new {
            dimen = Geom:new { w = cell_side, h = cell_side },
            allow_mirroring = false,
            bg_box,
            inner_cc,
        }
    end

    local function blankCell()
        return colorBox(cell_side, cell_side, WHITE, CELL_R, BLACK, CELL_BW)
    end

    local NAV_BTN_PAD = Screen:scaleBySize(6)
    local prev_btn = Button:new {
        text = "◀",
        bordersize = 0,
        text_font_face = "cfont",
        text_font_size = 12,
        text_font_bold = true,
        padding = NAV_BTN_PAD,
        callback = function() self_ref:_prevMonth() end,
    }
    local next_btn = Button:new {
        text = "▶",
        bordersize = 0,
        text_font_face = "cfont",
        text_font_size = 12,
        text_font_bold = true,
        padding = NAV_BTN_PAD,
        callback = function() self_ref:_nextMonth() end,
    }

    local function buildCalendar()
        local cal_title_str = string.format(_("%d年%d月份阅读统计"), view_year, view_month)
        local cal_title_w   = measureText(cal_title_str, face_cal_title)
        local cal_title = TextWidget:new {
            text = cal_title_str, face = face_cal_title, fgcolor = BLACK,
        }

        local nav_label_str = string.format(_("%d月/12月"), view_month)
        local nav_label_w   = measureText(nav_label_str, face_cal_hdr)
        local nav_label = TextWidget:new {
            text = nav_label_str, face = face_cal_hdr, fgcolor = BLACK,
        }

        local prev_w = (prev_btn:getSize() and prev_btn:getSize().w) or Screen:scaleBySize(24)
        local next_w = (next_btn:getSize() and next_btn:getSize().w) or Screen:scaleBySize(24)
        local NAV_INNER_GAP = Screen:scaleBySize(2)

        local hdr_gap = inner_w - cal_title_w - prev_w - next_w
                        - nav_label_w - NAV_INNER_GAP * 2
        if hdr_gap < 0 then hdr_gap = 0 end

        local title_row = HorizontalGroup:new { align = "center" }
        title_row[#title_row + 1] = cal_title
        title_row[#title_row + 1] = HorizontalSpan:new { width = hdr_gap }
        title_row[#title_row + 1] = prev_btn
        title_row[#title_row + 1] = HorizontalSpan:new { width = NAV_INNER_GAP }
        title_row[#title_row + 1] = nav_label
        title_row[#title_row + 1] = HorizontalSpan:new { width = NAV_INNER_GAP }
        title_row[#title_row + 1] = next_btn

        local title_cc = CenterContainer:new {
            dimen = Geom:new { w = inner_w, h = CAL_HDR_H },
            title_row,
        }

        local dow_labels = { _("周一"), _("周二"), _("周三"), _("周四"), _("周五"), _("周六"), _("周日") }
        local dow_inner = HorizontalGroup:new { align = "center" }
        for i = 1, 7 do
            if i > 1 then dow_inner[#dow_inner + 1] = HorizontalSpan:new { width = CAL_GAP } end
            local lbl = TextWidget:new {
                text = dow_labels[i], face = face_cal_dow, fgcolor = BLACK,
            }
            dow_inner[#dow_inner + 1] = CenterContainer:new {
                dimen = Geom:new { w = cell_side, h = CAL_DOW_H }, lbl,
            }
        end
        local dow_row = CenterContainer:new {
            dimen = Geom:new { w = inner_w, h = CAL_DOW_H },
            dow_inner,
        }

        local grid_rows = {}
        do
            local cur_row = HorizontalGroup:new { align = "center" }
            local col = first_col

            for fill_col = 1, first_col - 1 do
                if fill_col > 1 then
                    cur_row[#cur_row + 1] = HorizontalSpan:new { width = CAL_GAP }
                end
                cur_row[#cur_row + 1] = blankCell()
            end

            for day = 1, dim_days do
                if col > 1 then cur_row[#cur_row + 1] = HorizontalSpan:new { width = CAL_GAP } end
                cur_row[#cur_row + 1] = buildDayCell(day, monthly_daily[day] or 0)
                col = col + 1
                if col > 7 then
                    grid_rows[#grid_rows + 1] = CenterContainer:new {
                        dimen = Geom:new { w = inner_w, h = cell_side },
                        cur_row,
                    }
                    cur_row = HorizontalGroup:new { align = "center" }
                    col = 1
                end
            end

            if col > 1 then
                while col <= 7 do
                    if col > 1 then cur_row[#cur_row + 1] = HorizontalSpan:new { width = CAL_GAP } end
                    cur_row[#cur_row + 1] = blankCell()
                    col = col + 1
                end
                grid_rows[#grid_rows + 1] = CenterContainer:new {
                    dimen = Geom:new { w = inner_w, h = cell_side },
                    cur_row,
                }
            end
        end

        local BOTTOM_LINE_H = CAL_BOTTOM_H

        local SWATCH_SIDE = Screen:scaleBySize(12)
        local SWATCH_GAP  = Screen:scaleBySize(4)
        local LEGEND_GAP  = Screen:scaleBySize(10)

        local legend_items = {
            { LIGHT_FILL,  _("浅30m")   },
            { MEDIUM_FILL, _("中1h")    },
            { DARK_FILL,   _("深1h30m") },
            { DEEP_FILL,   _("更深2h")  },
        }

        local legend_row = HorizontalGroup:new { align = "center" }
        local legend_w = 0
        for i, it in ipairs(legend_items) do
            if i > 1 then
                legend_row[#legend_row + 1] = HorizontalSpan:new { width = LEGEND_GAP }
                legend_w = legend_w + LEGEND_GAP
            end

            local swatch = colorBox(SWATCH_SIDE, SWATCH_SIDE, it[1],
                                    Screen:scaleBySize(2), BLACK, CELL_BW)
            local swatch_cc = CenterContainer:new {
                dimen = Geom:new { w = SWATCH_SIDE, h = BOTTOM_LINE_H },
                swatch,
            }
            legend_row[#legend_row + 1] = swatch_cc

            legend_row[#legend_row + 1] = HorizontalSpan:new { width = SWATCH_GAP }

            local tw = measureText(it[2], face_cal_leg)
            if tw < 1 then tw = 1 end
            local txt = TextWidget:new {
                text = it[2], face = face_cal_leg, fgcolor = BLACK,
            }
            local txt_cc = CenterContainer:new {
                dimen = Geom:new { w = tw, h = BOTTOM_LINE_H },
                txt,
            }
            legend_row[#legend_row + 1] = txt_cc

            legend_w = legend_w + SWATCH_SIDE + SWATCH_GAP + tw
        end

        local legend_cc = CenterContainer:new {
            dimen = Geom:new { w = legend_w, h = BOTTOM_LINE_H },
            legend_row,
        }

        local total_str  = string.format(_("本月时长：%s"), fmtTime(calendar_month_secs))
        local total_w_px = measureText(total_str, face_cal_leg)
        if total_w_px < 1 then total_w_px = 1 end
        local total_widget = TextWidget:new {
            text = total_str, face = face_cal_leg, fgcolor = BLACK,
        }
        local total_cc = CenterContainer:new {
            dimen = Geom:new { w = total_w_px, h = BOTTOM_LINE_H },
            total_widget,
        }

        local spacer_w = inner_w - legend_w - total_w_px
        if spacer_w < 0 then spacer_w = 0 end

        local bottom_row = HorizontalGroup:new { align = "center" }
        bottom_row[#bottom_row + 1] = legend_cc
        bottom_row[#bottom_row + 1] = HorizontalSpan:new { width = spacer_w }
        bottom_row[#bottom_row + 1] = total_cc

        local g = VerticalGroup:new { align = "center" }
        g[#g + 1] = title_cc
        g[#g + 1] = VerticalSpan:new { width = Screen:scaleBySize(4) }
        g[#g + 1] = dow_row
        g[#g + 1] = VerticalSpan:new { width = Screen:scaleBySize(2) }
        for ri, r in ipairs(grid_rows) do
            if ri > 1 then g[#g + 1] = VerticalSpan:new { width = CAL_GAP } end
            g[#g + 1] = r
        end
        g[#g + 1] = VerticalSpan:new { width = Screen:scaleBySize(6) }
        g[#g + 1] = CenterContainer:new {
            dimen = Geom:new { w = inner_w, h = BOTTOM_LINE_H },
            bottom_row,
        }
        return g
    end

    local calendar_widget = buildCalendar()

    local content = VerticalGroup:new {
        align = "center",
        calendar_widget,
        VerticalSpan:new { width = STATS_PAD_V },
        rows_group,
    }

    local main_frame = FrameContainer:new {
        radius     = CORNER_R,
        bordersize = FRAME_BORDER,
        padding    = FRAME_PAD,
        background = WHITE,
        content,
    }

    self[1] = CenterContainer:new {
        dimen = Screen:getSize(),
        VerticalGroup:new { main_frame },
    }
end

local function _frameDimen(self)
    local a = self[1]
    local b = a and a[1]
    local c = b and b[1]
    return c and c.dimen or nil
end

function CalendarStatsWindow:onTap() UIManager:close(self) end
function CalendarStatsWindow:onSwipe(_a, _g) self:onClose() end
function CalendarStatsWindow:onClose() UIManager:close(self); return true end
CalendarStatsWindow.onAnyKeyPressed = CalendarStatsWindow.onClose
CalendarStatsWindow.onMultiSwipe    = CalendarStatsWindow.onClose

function CalendarStatsWindow:onShow()
    local d = _frameDimen(self)
    if d then
        UIManager:setDirty(self, function() return "ui", d end)
    else
        UIManager:setDirty(self, "ui")
    end
    return true
end

function CalendarStatsWindow:onCloseWidget()
    local d = _frameDimen(self) or Screen:getSize()
    if d then
        UIManager:setDirty(nil, function() return "ui", d end)
    end
end

Dispatcher:registerAction(
    "calendar_stats_action",
    { category = "none", event = "CalendarStats", title = _("日历阅读统计"), general = true }
)

local function showCalendarStats()
    local w = CalendarStatsWindow:new {}
    UIManager:show(w, "ui")
end

function ReaderUI:onCalendarStats()
    if self.statistics and self.statistics.insertDB then
        pcall(function() self.statistics:insertDB() end)
    end
    showCalendarStats()
end

function FileManager:onCalendarStats()
    if self.statistics and self.statistics.insertDB then
        pcall(function() self.statistics:insertDB() end)
    end
    showCalendarStats()
end

local _M = {}
_M.show = showCalendarStats
_M.settings_menu = calendar_stats_menu
return _M
