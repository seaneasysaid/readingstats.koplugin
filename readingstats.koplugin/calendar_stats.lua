local Blitbuffer      = require("ffi/blitbuffer")
local Button          = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
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
local ReaderUI        = require("apps/reader/readerui")
local Screen          = Device.screen
local StatsDb         = require("stats_db")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local Widget          = require("ui/widget/widget")
local logger          = require("logger")
local _ = require("gettext")

-- 字体一律走 fontmap 别名，不写死字体文件名：
--   cfont = 当前 UI 正文字体，tfont = 当前 UI 标题（粗体）字体
-- 用户的 UI 字体（设置项 ui_font_name / 2--ui-font.lua 补丁）替换的正是这些别名；
-- 写 "NotoSans-Bold.ttf" 这种实名会绕过替换，永远只是内置 NotoSans。
-- 没改过 UI 字体时，cfont/tfont 本身就映射到 NotoSans-Regular / NotoSans-Bold，外观不变。
local FONT_REG  = "cfont"
local FONT_BOLD = "tfont"

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

-- 统计项固定死，不再提供设置项（页数已下线：同一页在不同书/排版下不可比）：
--   今日时长 / 本周时长 / 本月时长 / 累计时长，一行四项
-- 「本月阅读 X 天」放在日历底部那一行的右侧（原来放「本月时长」的位置）
local STAT_ITEMS = { "today_time", "week_time", "month_time", "total_time" }

local FONT_SIZE_DEF = 18

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

-- 库访问统一走 stats_db.lua。下面两个薄包装只负责把日志前缀钉成 CALENDAR，
-- 函数名与调用点保持不变（本文件有 7 处调用），避免无谓的大范围改动。
local DB_TAG = "CALENDAR"

local function dbOpen()
    return StatsDb.open(DB_TAG)
end

local function dbQuery(conn, sql)
    return StatsDb.exec(conn, sql, DB_TAG)
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

-- 只求时长：原先为了页数套了一层「按书分组」的子查询，页数下线后去掉，
-- 直接对 page_stat 求和即可，少四次分组扫描
local function queryStats(conn, where_clause)
    if not conn then return 0 end
    local sql = string.format([[
        SELECT coalesce(sum(duration), 0)
        FROM page_stat
        WHERE %s
    ]], where_clause)
    local res = dbQuery(conn, sql)
    if not res or type(res[1]) ~= "table" or #res[1] == 0 then return 0 end
    return tonumber(res[1][1]) or 0
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

-- 某一天各本书的阅读明细（书名 / 作者 / 时长 / 页数）
-- 注意：page_stat 没有 pages_read 列，页数必须用 COUNT(DISTINCT page)
local function queryDayBooks(conn, y, m, d)
    if not conn then return {} end
    local s = os.time { year = y, month = m, day = d, hour = 0, min = 0, sec = 0 }
    local e = s + SECS_DAY
    local sql = string.format([[
        SELECT book.title, book.authors,
               SUM(page_stat.duration)        AS dur,
               COUNT(DISTINCT page_stat.page) AS pages
        FROM page_stat
        JOIN book ON page_stat.id_book = book.id
        WHERE start_time >= %d AND start_time < %d
        GROUP BY page_stat.id_book
        ORDER BY dur DESC;
    ]], s, e)
    local res = dbQuery(conn, sql)
    local out = {}
    if res and type(res[1]) == "table" then
        for i = 1, #res[1] do
            out[#out + 1] = {
                title   = res[1][i] or _("未知"),
                authors = (res[2] and res[2][i]) or "",
                dur     = tonumber(res[3] and res[3][i]) or 0,
                pages   = tonumber(res[4] and res[4][i]) or 0,
            }
        end
    end
    return out
end

-- ============================================================
-- 统计聚合（一次连接，全部查完再关闭；含月每日数据）
-- ============================================================

local function fetchAllStats()
    local s   = {}
    local now = os.date("*t")

    local conn = dbOpen()
    if not conn then
        s.today_secs = 0
        s.week_secs  = 0
        s.month_secs = 0
        s.total_secs = 0
        s.month_daily = {}
        return s
    end

    s.today_secs = queryStats(conn, whereToday())
    s.week_secs  = queryStats(conn, whereThisWeek())
    s.month_secs = queryStats(conn, whereMonth(now.year, now.month))
    s.total_secs = queryStats(conn, whereAll())
    s.month_daily = queryMonthlyDailyStats(conn, now.year, now.month)

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
-- 带 TTL：翻月可以一直往后翻到未来月份，若把「未来月份=空」永久缓存下来，
-- 等真到了那个月就会一直显示为空，直到重启 KOReader。
local _month_cache = {}
local MONTH_CACHE_TTL = 60   -- 秒

local function fmtTime(secs)
    secs = math.floor(secs or 0)
    if secs <= 0 then return _("0分钟") end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h >= 1 then return string.format(_("%d小时%d分钟"), h, m) end
    if m <= 0 then return _("<1分钟") end
    return string.format(_("%d分钟"), m)
end

-- 中文时长：<1分钟 / x分钟 / x小时y分钟
local function fmtCN(secs)
    secs = math.floor(tonumber(secs) or 0)
    if secs <= 0 then return _("0分钟") end
    if secs < 60 then return _("<1分钟") end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then return string.format(_("%d小时%d分钟"), h, m) end
    return string.format(_("%d分钟"), m)
end

-- 日格里的时长：中文优先。同一个时长给出「从完整到紧凑」的几种写法，
-- 由调用方按格子实际宽度挑一个放得下的（格子窄时自动退到 2时30分 / 2h30m）
local function cellTimeCandidates(secs)
    secs = math.floor(tonumber(secs) or 0)
    if secs <= 0 then return { "" } end
    if secs < 60 then return { _("<1分钟"), _("<1分") } end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h >= 1 then
        if m == 0 then
            return { string.format(_("%d小时"), h), string.format(_("%d时"), h),
                     string.format("%dh", h) }
        end
        return {
            string.format(_("%d小时%d分钟"), h, m),
            string.format(_("%d小时%d分"), h, m),
            string.format(_("%d时%d分"), h, m),
            string.format("%dh%dm", h, m),
        }
    end
    return {
        string.format(_("%d分钟"), m),
        string.format(_("%d分"), m),
        string.format("%dm", m),
    }
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

-- 每项只保留 label / get：原先的 sub / sub_fn 没有任何界面读取，属历史遗留
-- 页数（today_pages / week_pages / month_pages / total_pages）已下线，不再提供
-- 「连续天数」也已下线：STAT_ITEMS 里没有它，界面从不渲染，连同 queryStreak 一起删掉
local STAT_DEFS = {
    today_time  = { label = _("今日时长"), get = function(s) return fmtTime(s.today_secs) end },
    week_time   = { label = _("本周时长"), get = function(s) return fmtTime(s.week_secs) end },
    month_time  = { label = _("本月时长"), get = function(s) return fmtTime(s.month_secs) end },
    total_time  = { label = _("累计时长"), get = function(s) return fmtTime(s.total_secs) end },
}

local CAL_BUDGET_ROWS = 6

-- 递归清空所有分组控件的布局缓存（VerticalGroup/HorizontalGroup 的 _size/_offsets）。
-- paintTo 是拿 getSize() 时记下的 _offsets[i] 去画的，只要构建期存在任何一次
-- 「先 getSize、后 append 子项」，offsets 就会比子项少，重绘时直接
-- attempt to index a nil value（verticalgroup.lua:51 / horizontalgroup.lua:54）。
-- 建好整棵树后统一 reset 一遍最稳：首次绘制时按当前子项重新算，之后走缓存。
local function resetLayoutTree(w)
    if type(w) ~= "table" then return end
    for i = 1, #w do
        resetLayoutTree(w[i])
    end
    if type(w.resetLayout) == "function" then
        pcall(function() w:resetLayout() end)
    end
end

-- 绘制前的自愈：只要发现某个分组的 _offsets 比子项少（或整表缺失），就重置它。
-- 这样即使别处遗留了过期缓存，最多是这一个分组重算一次尺寸，不会把整个
-- KOReader 带崩（paintTo 里访问 self._offsets[i] 会直接 index nil）。
local function ensureOffsets(w)
    if type(w) ~= "table" then return end
    local n = #w
    if n > 0 then
        local offs = w._offsets
        local broken = (type(offs) ~= "table")
        if not broken then
            for i = 1, n do
                if offs[i] == nil then broken = true; break end
            end
        end
        if broken and type(w.resetLayout) == "function" then
            pcall(function() w:resetLayout() end)
        end
    end
    for i = 1, n do ensureOffsets(w[i]) end
end

local CalendarStatsWindow = InputContainer:extend { modal = true, name = "calendar_stats_window" }

function CalendarStatsWindow:init()
    self.ges_events = self.ges_events or {}
    self.key_events = self.key_events or {}

    local t = os.date("*t")
    if not self._view_year  then self._view_year  = t.year end
    if not self._view_month then self._view_month = t.month end
    -- 首次打开默认选中「今天」；翻月时由 _switchTo 显式设成 15 号。
    -- 若进来时看的不是当前月（正常流程不会），仍落到 15 号，避免选中一个不存在的日期。
    if not self._sel_day then
        if self._view_year == t.year and self._view_month == t.month then
            self._sel_day = t.day
        else
            self._sel_day = 15
        end
    end

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

-- 绘制前自愈 + 兜底：offsets 缺项先重建；万一还有别的坑，也只丢这一帧，
-- 不会让 KOReader 直接崩掉重启（真机上崩过一次，日志见 crash.log）
function CalendarStatsWindow:paintTo(bb, x, y)
    ensureOffsets(self)
    local ok, err = pcall(InputContainer.paintTo, self, bb, x, y)
    if not ok and not self._paint_err_logged then
        self._paint_err_logged = true
        if logger then
            -- 带上完整调用栈：只打一行 message 的话，定位不到是哪个控件出的问题
            local tb = debug.traceback("", 2)
            logger.err("READINGSTATS: calendar paintTo failed:", tostring(err),
                       "\n[stack]\n" .. tostring(tb))
        end
    end
end

-- 重建窗口：翻月、换选中日、书单滚动 统一走这里，状态显式透传
function CalendarStatsWindow:_rebuild(over)
    local opt = {
        _view_year  = self._view_year,
        _view_month = self._view_month,
        _sel_day    = self._sel_day,
        _book_off   = self._book_off or 0,
    }
    for k, v in pairs(over or {}) do opt[k] = v end
    UIManager:close(self)
    UIManager:show(CalendarStatsWindow:new(opt), "ui")
end

-- 翻月：回到 15 号、书单滚回顶部
function CalendarStatsWindow:_switchTo(y, m)
    self:_rebuild {
        _view_year  = y,
        _view_month = m,
        _sel_day    = 15,
        _book_off   = 0,
    }
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

-- 点某天：只切换选中日并重建窗口（统计与月份数据都走模块级缓存，开销极小）
function CalendarStatsWindow:_selectDay(day)
    if not day or day == self._sel_day then return end
    self:_rebuild { _sel_day = day, _book_off = 0 }
end

function CalendarStatsWindow:_build()
    local self_ref = self

    local face_cal_time = Font:getFace(FONT_REG,  14)
    local face_cal_date = Font:getFace(FONT_REG,  11)
    local face_cal_dow  = Font:getFace(FONT_REG,  12)
    -- 顶栏「<< 返回」和「日历阅读统计」用 22 号粗体（标题层级，对齐阅读报告的 section）
    local face_cal_title = Font:getFace(FONT_REG, 22)
    local face_cal_title_bold = Font:getFace(FONT_BOLD, 22)

    -- 统计项使用模块级缓存（TTL 内复用，避免反复全表扫描）
    local stats = self._stats or getStatsCached()
    self._stats = stats

    local view_year, view_month = self._view_year, self._view_month

    local now_t      = os.date("*t")
    local is_current = (view_year == now_t.year and view_month == now_t.month)
    local mkey       = string.format("%04d-%02d", view_year, view_month)

    local calendar_month_secs, monthly_daily
    if is_current then
        -- 当前月直接复用 fetchAllStats 里已经查好的数据
        calendar_month_secs = stats.month_secs
        monthly_daily       = stats.month_daily or {}
    else
        local cached = _month_cache[mkey]
        if cached and (os.time() - (cached.ts or 0)) < MONTH_CACHE_TTL then
            calendar_month_secs = cached.secs
            monthly_daily       = cached.daily
        else
            local conn = dbOpen()
            if conn then
                calendar_month_secs = queryStats(conn, whereMonth(view_year, view_month))
                monthly_daily = queryMonthlyDailyStats(conn, view_year, view_month)
                pcall(function() conn:close() end)
            else
                calendar_month_secs = 0
                monthly_daily = {}
            end
            _month_cache[mkey] = {
                secs  = calendar_month_secs,
                daily = monthly_daily,
                ts    = os.time(),
            }
        end
    end

    local items = {}
    for _, id in ipairs(STAT_ITEMS) do
        if STAT_DEFS[id] then items[#items + 1] = id end
    end
    local n = #items

    local SCR_W, SCR_H = Screen:getWidth(), Screen:getHeight()
    -- 与阅读报告一致：内容左右只留 8，顶栏分隔线通屏宽；FrameContainer 自身不设 padding
    local FRAME_PAD    = Screen:scaleBySize(8)
    local TITLE_GAP    = Screen:scaleBySize(10)
    -- 两张卡片（参考阅读报告的卡片样式）：白底 + 灰边 + 圆角 + 内边距
    local CARD_B       = math.max(1, Screen:scaleBySize(1))
    local CARD_PAD     = Screen:scaleBySize(12)
    local CARD_R       = Screen:scaleBySize(8)
    local CARD_GAP     = Screen:scaleBySize(10)
    local CARD_CHROME_V = (CARD_B + CARD_PAD) * 2
    local card_w       = math.max(Screen:scaleBySize(240), SCR_W - FRAME_PAD * 2)
    -- 卡片内部宽度（日历、统计项、详情都按这个宽度排）
    local inner_w      = math.max(Screen:scaleBySize(200), card_w - CARD_CHROME_V)
    local VAL_LBL_GAP  = Screen:scaleBySize(6)
    local CAL_GAP      = Screen:scaleBySize(8)

    local CELL_R       = Screen:scaleBySize(5)

    local function scaleLine(v)
        local s = Screen:scaleBySize(v)
        if s < 1 then s = 1 end
        return s
    end

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

    -- 按可用宽度截断文本（UTF-8 安全），超出补省略号；二分查找，避免逐字测量
    local function fitText(text, face, max_w)
        if not text or text == "" then return "" end
        if not max_w or max_w <= 0 then return "" end
        if (select(1, measureText(text, face)) or 0) <= max_w then return text end
        local chars = {}
        for ch in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            chars[#chars + 1] = ch
        end
        local lo, hi, best = 1, #chars - 1, 0
        while lo <= hi do
            local mid = math.floor((lo + hi) / 2)
            local cand = table.concat(chars, "", 1, mid) .. "…"
            if (select(1, measureText(cand, face)) or 0) <= max_w then
                best = mid; lo = mid + 1
            else
                hi = mid - 1
            end
        end
        if best <= 0 then return "…" end
        return table.concat(chars, "", 1, best) .. "…"
    end

    local function getItemValue(id)
        if id == "month_time" then return fmtTime(calendar_month_secs) end
        local def = STAT_DEFS[id]
        return def and def.get(stats) or ""
    end

    -- 固定项全部排成一行；每项宽度按项数均分，字号再按最长内容自适应下调，
    -- 保证「999小时59分钟」这种长值也单行不折行
    local MAX_PER_ROW = math.max(1, n)
    local STATS_ROW_GAP = Screen:scaleBySize(10)

    local items_per_row = math.max(1, math.min(n, MAX_PER_ROW))
    local n_rows = math.max(1, math.ceil(n / items_per_row))

    local item_w
    if n == 0 then
        item_w = inner_w
    else
        item_w = math.floor((inner_w - SEP_TOTAL * (items_per_row - 1)) / items_per_row)
        if item_w < Screen:scaleBySize(40) then item_w = Screen:scaleBySize(40) end
    end

    -- 统计项字号固定，不再提供设置项；仍按可用宽度自适应缩小，保证单行不折行
    local BASE_VAL_SIZE = FONT_SIZE_DEF
    local BASE_LBL_SIZE = math.max(1, math.floor(BASE_VAL_SIZE * 15 / 18 + 0.5))

    local face_val_base = Font:getFace(FONT_REG, BASE_VAL_SIZE)
    local face_lbl_base = Font:getFace(FONT_REG, BASE_LBL_SIZE)

    -- 值和标签分开量各自最宽的内容，避免窄标签把字号一起压小
    local max_val_w, max_lbl_w, longest_val = 0, 0, ""
    for _, id in ipairs(items) do
        local def = STAT_DEFS[id]
        if def then
            local vs = getItemValue(id)
            local ls = def.label or ""
            local vw = select(1, measureText(vs, face_val_base)) or 0
            local lw = select(1, measureText(ls, face_lbl_base)) or 0
            if vw > max_val_w then max_val_w = vw; longest_val = vs end
            if lw > max_lbl_w then max_lbl_w = lw end
        end
    end

    local padding_w = Screen:scaleBySize(4)
    local usable_w = math.max(1, item_w - padding_w)

    local scale = 1
    if max_val_w > 0 then scale = math.min(scale, usable_w / max_val_w) end
    if max_lbl_w > 0 then scale = math.min(scale, usable_w / max_lbl_w) end
    if scale < 0.25 then scale = 0.25 end

    local val_size = math.max(1, math.floor(BASE_VAL_SIZE * scale + 0.5))
    local lbl_size = math.max(1, math.floor(BASE_LBL_SIZE * scale + 0.5))

    -- 取整后可能仍差几像素：实测最长值，逐级降字号直到一定放得下单行
    do
        local guard = 0
        while val_size > 8 and guard < 40 do
            local f = Font:getFace(FONT_REG, val_size)
            if (select(1, measureText(longest_val, f)) or 0) <= usable_w then break end
            val_size = val_size - 1
            guard = guard + 1
        end
    end

    local face_val = Font:getFace(FONT_REG, val_size)
    local face_lbl = Font:getFace(FONT_REG, lbl_size)

    local content_h = (select(2, measureText("Ag", face_val)) or 0)
                    + VAL_LBL_GAP
                    + (select(2, measureText("Ag", face_lbl)) or 0)
    local item_h = content_h

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

        -- 用 TextWidget（不换行）而不是 TextBoxWidget：值必须单行显示
        local val_w = TextWidget:new {
            text = val_str, face = face_val, fgcolor = BLACK,
            max_width = item_w,
        }
        local lbl_w = TextWidget:new {
            text = lbl_str, face = face_lbl, fgcolor = BLACK,
            max_width = item_w,
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
        -- 按每行 items_per_row 项铺开，超过一行就往下排（行高相同，整行居中）
        for r = 1, n_rows do
            local first = (r - 1) * items_per_row + 1
            local last  = math.min(r * items_per_row, n)
            local row = HorizontalGroup:new { align = "center" }
            for i = first, last do
                if i > first then
                    row[#row + 1] = buildColumnSeparator(item_h)
                end
                row[#row + 1] = buildStatItem(items[i])
            end
            if r > 1 then
                rows_group[#rows_group + 1] = VerticalSpan:new { width = STATS_ROW_GAP }
            end
            rows_group[#rows_group + 1] = CenterContainer:new {
                dimen = Geom:new { w = inner_w, h = item_h }, row,
            }
        end
    end

    local dim_days  = daysInMonth(view_year, view_month)
    local first_ts  = os.time { year = view_year, month = view_month, day = 1, hour = 0 }
    local wday1     = tonumber(os.date("%w", first_ts)) or 0
    local first_col = (wday1 == 0) and 7 or wday1

    local cell_side_w = math.floor((inner_w - CAL_GAP * 6) / 7)
    cell_side_w = math.max(cell_side_w, Screen:scaleBySize(28))

    local CAL_HDR_H    = Screen:scaleBySize(30)
    local CAL_DOW_H    = Screen:scaleBySize(18)
    local CAL_BOTTOM_H = Screen:scaleBySize(22)

    local CAL_TITLE_SPAN_H  = Screen:scaleBySize(4)
    local CAL_DOW_SPAN_H    = Screen:scaleBySize(2)
    local CAL_BOTTOM_SPAN_H = Screen:scaleBySize(6)

    -- ===== 顶部标题栏（复刻阅读报告）：<< 返回（左）+ 居中「日历阅读统计」=====
    local HDR_MARGIN  = FRAME_PAD
    local HDR_GAP     = Screen:scaleBySize(10)
    local HDR_TOP_PAD = Screen:scaleBySize(12)

    local back_tw = TextWidget:new { text = "<< " .. _("返回"), face = face_cal_title_bold, fgcolor = BLACK }
    local back_sz = back_tw:getSize()
    local back_w  = (back_sz and back_sz.w) or Screen:scaleBySize(60)
    local hdr_row_h = (back_sz and back_sz.h) or Screen:scaleBySize(26)

    local hdr_side_w  = HDR_MARGIN + back_w + HDR_GAP
    local hdr_title_w = math.max(1, SCR_W - 2 * hdr_side_w)
    local hdr_title_tw = TextWidget:new {
        text = _("日历阅读统计"), face = face_cal_title_bold, fgcolor = BLACK,
        max_width = hdr_title_w,
    }

    -- 返回键容器：默认白底；点击时整块反色做反馈
    local back_cell = FrameContainer:new {
        bordersize = 0, background = WHITE, padding = 0, margin = 0,
        CenterContainer:new { dimen = Geom:new { w = back_w, h = hdr_row_h }, back_tw },
    }

    local hdr_row = HorizontalGroup:new {
        align = "center",
        HorizontalSpan:new { width = HDR_MARGIN },
        back_cell,
        HorizontalSpan:new { width = HDR_GAP },
        CenterContainer:new { dimen = Geom:new { w = hdr_title_w, h = hdr_row_h }, hdr_title_tw },
        HorizontalSpan:new { width = HDR_GAP },
        HorizontalSpan:new { width = back_w },
        HorizontalSpan:new { width = HDR_MARGIN },
    }

    -- 顶栏分隔线通屏宽（与阅读报告一致），行内容仍按 inner_w 居中
    local header_widget = VerticalGroup:new {
        align = "center",
        VerticalSpan:new { width = HDR_TOP_PAD },
        hdr_row,
        LineWidget:new { dimen = Geom:new { w = SCR_W, h = LINE_W },
                         background = Blitbuffer.COLOR_GRAY },
    }
    local header_h = (header_widget:getSize() and header_widget:getSize().h) or Screen:scaleBySize(50)

    -- 返回键命中区（含顶部留白，好点）：绝对屏幕坐标
    self._back_cell = back_cell
    self._back_tw   = back_tw
    self._back_rect = {
        x = 0, y = 0,
        w = FRAME_PAD + hdr_side_w,
        h = HDR_TOP_PAD + hdr_row_h,
    }

    -- 卡片一里「统计项」区块：分隔线 + 上下留白 + 统计项本身（可能有多行）
    local STATS_SEP_GAP = Screen:scaleBySize(10)
    local STATS_BOT_GAP = Screen:scaleBySize(8)
    local STATS_BLOCK_H = STATS_SEP_GAP + LINE_W + STATS_BOT_GAP
                        + item_h * n_rows + STATS_ROW_GAP * (n_rows - 1)

    -- 卡片二（阅读详情）内部最小高度：先预留，避免日历把屏幕吃满后溢出被裁
    local DETAIL_MIN_H = Screen:scaleBySize(110)

    -- 6 行格子可用高度（已扣掉顶栏、两张卡片的边距/内边距、统计项、详情面板、日历自带表头/星期/底栏）
    local avail_h = SCR_H - FRAME_PAD
                  - header_h - TITLE_GAP
                  - CARD_GAP
                  - CARD_CHROME_V * 2
                  - STATS_BLOCK_H
                  - DETAIL_MIN_H
                  - CAL_HDR_H - CAL_TITLE_SPAN_H
                  - CAL_DOW_H - CAL_DOW_SPAN_H
                  - CAL_BOTTOM_H - CAL_BOTTOM_SPAN_H
    avail_h = math.max(avail_h, Screen:scaleBySize(100))

    local cell_side_h = math.floor(
        (avail_h - (CAL_BUDGET_ROWS - 1) * CAL_GAP) / CAL_BUDGET_ROWS)
    cell_side_h = math.max(cell_side_h, Screen:scaleBySize(24))

    -- 格子宽高分开算：
    --   宽度撑满卡片内宽（中文时长比 "2h30m" 宽，需要更宽的格子）
    --   高度仍沿用原来的 64 目标值，不跟着放大，否则日历变高会把详情卡挤没
    local CAL_TARGET_CELL = Screen:scaleBySize(64)
    local cell_w = math.max(cell_side_w, Screen:scaleBySize(28))
    local cell_h = math.min(cell_side_h, CAL_TARGET_CELL)
    cell_h = math.max(cell_h, Screen:scaleBySize(24))

    local CELL_PAD_L = Screen:scaleBySize(5)

    -- 日格内时长的字号自适应：从 14 往下降，直到这串文字塞得进格子宽度
    local CELL_TIME_SIZES = { 14, 13, 12, 11, 10, 9 }
    local function fitCellTime(secs, max_w)
        local cands = cellTimeCandidates(secs)
        if #cands == 1 and cands[1] == "" then
            return "", face_cal_time
        end
        for _, cand in ipairs(cands) do
            for _, sz in ipairs(CELL_TIME_SIZES) do
                local f = Font:getFace(FONT_REG, sz)
                if (select(1, measureText(cand, f)) or 0) <= max_w then
                    return cand, f
                end
            end
        end
        -- 实在放不下：最紧凑写法 + 最小字号
        return cands[#cands], Font:getFace(FONT_REG, CELL_TIME_SIZES[#CELL_TIME_SIZES])
    end

    local function buildDayCell(day, secs, selected)
        local s = tonumber(secs) or 0

        local bg = cellFill(s)
        local fg = cellTextColor(s)

        -- 留 4px 安全余量：真机字面比测量值略宽，卡在临界值会溢出格子
        local time_str, face_cell_time = fitCellTime(s, math.max(1,
            cell_w - CELL_PAD_L * 2 - Screen:scaleBySize(4)))

        local date_widget = TextWidget:new {
            text = tostring(day), face = face_cal_date, fgcolor = fg,
        }
        local time_widget = TextWidget:new {
            text = (time_str ~= "" and time_str or " "),
            face = face_cell_time, fgcolor = fg,
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

        local right_fill = math.max(0, cell_w - CELL_PAD_L - date_w)
        local date_row = HorizontalGroup:new {
            align = "center",
            HorizontalSpan:new { width = CELL_PAD_L },
            date_widget,
            HorizontalSpan:new { width = right_fill },
        }

        local time_row = CenterContainer:new {
            dimen = Geom:new { w = cell_w, h = math.max(1, time_h) },
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
            dimen = Geom:new { w = cell_w, h = cell_h },
            inner,
        }

        -- 选中态只把描边加粗到 2（原来 3，偏重），仍然明显但不再抢眼
        local bg_box = colorBox(cell_w, cell_h, bg, CELL_R, BLACK,
                                selected and Screen:scaleBySize(2) or CELL_BW)

        return OverlapGroup:new {
            dimen = Geom:new { w = cell_w, h = cell_h },
            allow_mirroring = false,
            bg_box,
            inner_cc,
        }
    end

    local function blankCell()
        return colorBox(cell_w, cell_h, WHITE, CELL_R, BLACK, CELL_BW)
    end

    -- 翻月按钮：< / > 各套一个圆角方框；框高与「2026年X月」标题行一致
    -- 宽度给到 52（原先是 30 的方形），手指更容易点中
    local NAV_BOX_W = math.max(CAL_HDR_H, Screen:scaleBySize(52))
    local NAV_BOX_R = Screen:scaleBySize(6)
    local function makeNavBtn(glyph, cb)
        -- Button 自身 frame = label_container + 2*padding + 2*bordersize，padding 为 0，
        -- 所以 height 要给 CAL_HDR_H - 2*CARD_B 才能让外框高度正好等于标题行高
        return Button:new {
            text = glyph,
            bordersize = CARD_B,
            radius = NAV_BOX_R,
            text_font_face = FONT_REG,
            text_font_size = 22,
            text_font_bold = true,
            padding = 0,
            width = NAV_BOX_W,
            height = math.max(1, CAL_HDR_H - CARD_B * 2),
            callback = cb,
        }
    end
    local prev_btn = makeNavBtn("<", function() self_ref:_prevMonth() end)
    local next_btn = makeNavBtn(">", function() self_ref:_nextMonth() end)

    -- 网格宽度：翻月按钮框的左右边沿与网格左右边沿对齐（统计项不参与这个对齐）
    local grid_w = 7 * cell_w + 6 * CAL_GAP

    local function buildCalendar()
        -- 年月居中，< > 两个方框分别顶到网格左右两边
        local cal_title_str = string.format(_("%d年%d月"), view_year, view_month)
        local cal_title = TextWidget:new {
            text = cal_title_str, face = face_cal_title, fgcolor = BLACK,
        }

        local mid_w = math.max(1, grid_w - NAV_BOX_W * 2)

        local title_row = HorizontalGroup:new { align = "center" }
        title_row[#title_row + 1] = CenterContainer:new {
            dimen = Geom:new { w = NAV_BOX_W, h = CAL_HDR_H }, prev_btn,
        }
        title_row[#title_row + 1] = CenterContainer:new {
            dimen = Geom:new { w = mid_w, h = CAL_HDR_H }, cal_title,
        }
        title_row[#title_row + 1] = CenterContainer:new {
            dimen = Geom:new { w = NAV_BOX_W, h = CAL_HDR_H }, next_btn,
        }

        local title_cc = CenterContainer:new {
            dimen = Geom:new { w = grid_w, h = CAL_HDR_H },
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
                dimen = Geom:new { w = cell_w, h = CAL_DOW_H }, lbl,
            }
        end
        local dow_row = CenterContainer:new {
            dimen = Geom:new { w = grid_w, h = CAL_DOW_H },
            dow_inner,
        }

        local grid_rows = {}
        do
            -- 日格命中区用绝对屏幕坐标登记（全屏窗口下子控件坐标不可靠）
            -- 卡片一内容起点 = 顶栏 + 间距 + 卡片边框 + 卡片内边距
            local card1_x0 = FRAME_PAD + CARD_B + CARD_PAD
            local card1_y0 = header_h + TITLE_GAP + CARD_B + CARD_PAD
            local row_x0   = math.floor((inner_w - grid_w) / 2)
            local grid_y0  = card1_y0
                           + CAL_HDR_H + CAL_TITLE_SPAN_H
                           + CAL_DOW_H + CAL_DOW_SPAN_H
            local row_idx = 1

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
                self_ref._day_rects[day] = {
                    x = card1_x0 + row_x0 + (col - 1) * (cell_w + CAL_GAP),
                    y = grid_y0 + (row_idx - 1) * (cell_h + CAL_GAP),
                    w = cell_w,
                    h = cell_h,
                }
                cur_row[#cur_row + 1] = buildDayCell(day, monthly_daily[day] or 0,
                                                     day == self_ref._sel_day)
                col = col + 1
                if col > 7 then
                    grid_rows[#grid_rows + 1] = CenterContainer:new {
                        dimen = Geom:new { w = grid_w, h = cell_h },
                        cur_row,
                    }
                    cur_row = HorizontalGroup:new { align = "center" }
                    col = 1
                    row_idx = row_idx + 1
                end
            end

            if col > 1 then
                while col <= 7 do
                    if col > 1 then cur_row[#cur_row + 1] = HorizontalSpan:new { width = CAL_GAP } end
                    cur_row[#cur_row + 1] = blankCell()
                    col = col + 1
                end
                grid_rows[#grid_rows + 1] = CenterContainer:new {
                    dimen = Geom:new { w = grid_w, h = cell_h },
                    cur_row,
                }
            end
        end

        local BOTTOM_LINE_H = CAL_BOTTOM_H

        local SWATCH_SIDE = Screen:scaleBySize(12)
        local SWATCH_GAP  = Screen:scaleBySize(4)
        local LEGEND_GAP  = Screen:scaleBySize(10)

        -- 底部右侧「本月阅读 X 天」：按当前视图月份统计，翻月时也跟着变，
        -- 与上面的日历保持一致（直接数月度每日数据，不额外查库）
        local view_month_days = 0
        for _, secs in pairs(monthly_daily or {}) do
            if (tonumber(secs) or 0) > 0 then view_month_days = view_month_days + 1 end
        end

        local legend_items = {
            { LIGHT_FILL,  _("浅30分钟")     },
            { MEDIUM_FILL, _("中1小时")      },
            { DARK_FILL,   _("深1小时30分钟") },
            { DEEP_FILL,   _("更深2小时")    },
        }

        local total_str = string.format(_("本月阅读 %d天"), view_month_days)

        -- 图例四个中文档位 + 右侧「本月时长」要挤在同一行：
        -- 字号从 14 往下试，选第一个整体装得进 inner_w 的（小屏自动降到 12/11 号）
        local function legendTotalAt(sz)
            local f = Font:getFace(FONT_REG, sz)
            local lw = 0
            for i, it in ipairs(legend_items) do
                if i > 1 then lw = lw + LEGEND_GAP end
                lw = lw + SWATCH_SIDE + SWATCH_GAP
                     + (select(1, measureText(it[2], f)) or 0)
            end
            local tw = select(1, measureText(total_str, f)) or 0
            return lw, tw
        end

        local leg_size = 10
        local MIN_LEG_GAP = Screen:scaleBySize(14)
        for _, sz in ipairs { 14, 13, 12, 11, 10 } do
            leg_size = sz
            local lw, tw = legendTotalAt(sz)
            if lw + tw + MIN_LEG_GAP <= inner_w then break end
        end
        local face_leg = Font:getFace(FONT_REG, leg_size)

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

            local tw = measureText(it[2], face_leg)
            if tw < 1 then tw = 1 end
            local txt = TextWidget:new {
                text = it[2], face = face_leg, fgcolor = BLACK,
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

        local total_w_px = measureText(total_str, face_leg)
        if total_w_px < 1 then total_w_px = 1 end
        local total_widget = TextWidget:new {
            text = total_str, face = face_leg, fgcolor = BLACK,
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
        g[#g + 1] = VerticalSpan:new { width = CAL_TITLE_SPAN_H }
        g[#g + 1] = dow_row
        g[#g + 1] = VerticalSpan:new { width = CAL_DOW_SPAN_H }
        for ri, r in ipairs(grid_rows) do
            if ri > 1 then g[#g + 1] = VerticalSpan:new { width = CAL_GAP } end
            g[#g + 1] = r
        end
        g[#g + 1] = VerticalSpan:new { width = CAL_BOTTOM_SPAN_H }
        g[#g + 1] = CenterContainer:new {
            dimen = Geom:new { w = inner_w, h = BOTTOM_LINE_H },
            bottom_row,
        }
        return g
    end

    -- ===== 底部「当天阅读详情」面板 =====
    local function buildDetailPanel(panel_w, panel_h)
        local sel_day = self_ref._sel_day or 15

        local face_d_hdr = Font:getFace(FONT_BOLD, 18)
        local face_d_tot = Font:getFace(FONT_REG, 15)
        local face_d_sub = Font:getFace(FONT_REG, 12)

        local day_secs = tonumber(monthly_daily and monthly_daily[sel_day]) or 0

        -- 当天有记录才查明细，省一次查询
        local books = {}
        if day_secs > 0 then
            local conn = dbOpen()
            if conn then
                books = queryDayBooks(conn, view_year, view_month, sel_day) or {}
                pcall(function() conn:close() end)
            end
        end

        local TITLE_H = Screen:scaleBySize(30)
        local HEAD_GAP = Screen:scaleBySize(4)
        local head_h  = TITLE_H + HEAD_GAP

        local panel = VerticalGroup:new { align = "left" }

        -- 标题与总时长同一行、左对齐（参考阅读报告的顶部信息行）
        local title_str = string.format(_("%d月%d日 阅读详情"), view_month, sel_day)
        local total_str = string.format(_("共%s"), fmtCN(day_secs))
        local hgap_w    = Screen:scaleBySize(20)
        local title_w   = select(1, measureText(title_str, face_d_hdr)) or 0
        local total_w   = select(1, measureText(total_str, face_d_tot)) or 0
        local fill_w    = math.max(0, panel_w - title_w - hgap_w - total_w)

        local head_row = HorizontalGroup:new {
            align = "center",
            TextWidget:new { text = title_str, face = face_d_hdr, fgcolor = BLACK },
            HorizontalSpan:new { width = hgap_w },
            TextWidget:new { text = total_str, face = face_d_tot, fgcolor = BLACK },
            HorizontalSpan:new { width = fill_w },
        }

        panel[#panel + 1] = CenterContainer:new {
            dimen = Geom:new { w = panel_w, h = TITLE_H },
            head_row,
        }
        panel[#panel + 1] = VerticalSpan:new { width = HEAD_GAP }

        if #books == 0 then
            panel[#panel + 1] = CenterContainer:new {
                dimen = Geom:new { w = panel_w, h = Screen:scaleBySize(40) },
                TextWidget:new {
                    text = _("这一天还没有阅读记录"),
                    face = face_d_sub, fgcolor = Blitbuffer.COLOR_GRAY,
                },
            }
        else
            -- 排行行：名次 + 书名·作者 + 时长右对齐，文字下方再加一条长度条。
            -- 长度条取自「统计概览 · 读书排行」的 proportionBar：
            -- 浅灰轨道铺满整行宽，黑色实心条按「本书时长 / 当天最长」的比例截取。
            --
            -- ⚠️ 字号固定 18，不再按「至少排 4 本」逐级下调字号：
            --   6 行格子的月份卡片一更高，一屏自然少排一行，多出的书用滚动条看。
            --   宁可少一行，也不把书名压小 —— 墨水屏上小字等于看不清。
            local BAR_THIN    = math.max(2, Screen:scaleBySize(3))
            local BAR_GAP     = Screen:scaleBySize(2)   -- 文字行与长度条之间
            local ROW_GAP     = Screen:scaleBySize(3)   -- 长度条与下一行之间
            local ROW_PAD_T   = 1

            local face_d_row  = Font:getFace(FONT_REG, 18)
            local text_line_h = math.max(
                (select(2, measureText("Ag", face_d_row)) or 0),
                (select(2, measureText("Ag", face_d_sub)) or 0))
            local row_h = ROW_PAD_T + text_line_h + BAR_GAP + BAR_THIN + ROW_GAP

            -- 满格基准取当天最长的一本书（不是可见那几行，滚动时比例才稳定）
            local max_dur = 1
            for _, it in ipairs(books) do
                local d = tonumber(it.dur) or 0
                if d > max_dur then max_dur = d end
            end

            -- 书单是独立滚动区：高度只吃卡片二剩下的空间，怎么滑都不影响上面的日历
            local list_h = math.max(row_h, panel_h - head_h)
            local visible_rows = math.max(1, math.floor(list_h / row_h))
            local max_off = math.max(0, #books - visible_rows)
            local off = math.max(0, math.min(self_ref._book_off or 0, max_off))
            self_ref._book_off     = off
            self_ref._book_max_off = max_off
            self_ref._book_step    = math.max(1, visible_rows - 1)

            local first_idx = off + 1
            local last_idx  = math.min(#books, off + visible_rows)

            -- 名次用纯文本「1. 2. 3.」，不再画灰底圆圈。
            -- 宽度按最大名次（如 "12."）统一，保证每行书名左沿对齐。
            local RANK_W   = math.ceil(select(1, measureText(string.format("%d.", #books), face_d_row)) or 0)
            local RANK_GAP = Screen:scaleBySize(8)
            local TIME_GAP = Screen:scaleBySize(12)

            -- 有滚动条时列表让出右侧一条，避免书名/时长被压在滚动条下
            local BAR_W   = Screen:scaleBySize(3)
            local BAR_PAD = Screen:scaleBySize(6)
            local list_w  = panel_w - ((max_off > 0) and (BAR_W + BAR_PAD) or 0)

            local rows_group = VerticalGroup:new { align = "left" }

            for i = first_idx, last_idx do
                local b = books[i]

                local rank_str   = string.format("%d.", i)
                local rank_str_w = select(1, measureText(rank_str, face_d_row)) or 0

                local time_str = fmtCN(b.dur)
                local time_w = select(1, measureText(time_str, face_d_row)) or 0
                local name_w = math.max(1, list_w - RANK_W - RANK_GAP - TIME_GAP - time_w)

                local name = b.title or _("未知")
                if b.authors and b.authors ~= "" then
                    name = name .. " · " .. b.authors
                end
                name = fitText(name, face_d_row, name_w)
                local name_draw_w = select(1, measureText(name, face_d_row)) or 0

                local row = HorizontalGroup:new { align = "center" }
                row[#row + 1] = TextWidget:new {
                    text = rank_str, face = face_d_row, fgcolor = BLACK,
                }
                row[#row + 1] = HorizontalSpan:new {
                    width = math.max(0, RANK_W - rank_str_w) + RANK_GAP,
                }
                row[#row + 1] = TextWidget:new {
                    text = (name ~= "" and name or " "),
                    face = face_d_row, fgcolor = BLACK,
                    max_width = name_w,
                }
                row[#row + 1] = HorizontalSpan:new {
                    width = math.max(0, list_w - RANK_W - RANK_GAP
                                        - name_draw_w - time_w),
                }
                row[#row + 1] = TextWidget:new {
                    text = time_str, face = face_d_row, fgcolor = BLACK,
                }

                -- 长度条：轨道 + 按比例截取的实心条，两层同坐标叠放
                -- ⚠️ OverlapGroup 的子项必须直接是控件数组（OverlapGroup:new(layers)），
                -- 写成 OverlapGroup:new{ dimen=..., layers } 会把整张表当成一个子项 → 0×0 画不出来
                local ratio = math.max(0, math.min(1, (tonumber(b.dur) or 0) / max_dur))
                local fill_w = math.floor(ratio * list_w + 0.5)
                if fill_w < 1 and ratio > 0 then fill_w = 1 end
                if fill_w > list_w then fill_w = list_w end

                local bar_layers = {
                    dimen = Geom:new { w = list_w, h = BAR_THIN },
                    colorBox(list_w, BAR_THIN, Blitbuffer.COLOR_GRAY_E, 0, nil, 0),
                }
                if fill_w > 0 then
                    bar_layers[#bar_layers + 1] =
                        colorBox(fill_w, BAR_THIN, BLACK, 0, nil, 0)
                end

                rows_group[#rows_group + 1] = VerticalGroup:new {
                    align = "left",
                    VerticalSpan:new { width = ROW_PAD_T },
                    CenterContainer:new {
                        dimen = Geom:new { w = list_w, h = text_line_h }, row,
                    },
                    VerticalSpan:new { width = BAR_GAP },
                    OverlapGroup:new(bar_layers),
                    VerticalSpan:new { width = ROW_GAP },
                }
            end

            -- 末页行数不足一屏时补白，滚动条轨道高度才不会跳
            local body_h = (last_idx - first_idx + 1) * row_h
            local list_col = VerticalGroup:new { align = "left", rows_group }
            if body_h < list_h then
                list_col[#list_col + 1] = VerticalSpan:new { width = list_h - body_h }
            end

            if max_off > 0 then
                -- 右侧细滚动条：轨道透明，滑块按可见比例定长，位置按偏移量算
                local thumb_h = math.max(Screen:scaleBySize(28),
                    math.floor(list_h * visible_rows / #books))
                if thumb_h > list_h then thumb_h = list_h end
                local thumb_y = 0
                if max_off > 0 then
                    thumb_y = math.floor((list_h - thumb_h) * off / max_off)
                end

                local bar_col = VerticalGroup:new {
                    align = "center",
                    VerticalSpan:new { width = thumb_y },
                    -- 必须用自绘的 ColorBox，不能用 FrameContainer：
                    -- FrameContainer:getSize() 里直接取 self[1]:getSize()，
                    -- 空内容（只有 width/height/background）会 index nil，整棵树 paintTo 中断
                    colorBox(BAR_W, thumb_h, Blitbuffer.COLOR_GRAY_4,
                             math.floor(BAR_W / 2), nil, 0),
                    VerticalSpan:new { width = math.max(0, list_h - thumb_y - thumb_h) },
                }

                panel[#panel + 1] = HorizontalGroup:new {
                    align = "top",
                    list_col,
                    HorizontalSpan:new { width = BAR_PAD },
                    bar_col,
                }
            else
                panel[#panel + 1] = list_col
            end
        end

        -- 面板吃满分配高度，底部不留空（全屏观感）
        local ph = 0
        do
            local ok, sz = pcall(function() return panel:getSize() end)
            if ok and sz then ph = tonumber(sz.h) or 0 end
        end
        if ph < panel_h then
            panel[#panel + 1] = VerticalSpan:new { width = panel_h - ph }
            -- ⚠️ getSize() 会缓存 _size/_offsets；之后 append 子项必须 resetLayout，
            -- 否则 paintTo 里 self._offsets[i] 是 nil，直接崩（verticalgroup.lua:51）
            panel:resetLayout()
        end

        return panel
    end

    self_ref._day_rects = self_ref._day_rects or {}
    local calendar_widget = buildCalendar()

    -- ===== 卡片一：日历 + 统计项（一个整体，中间一条分隔线）=====
    local card1_body = VerticalGroup:new {
        align = "center",
        -- 零高度撑条：把卡片内容宽度钉到 inner_w（VerticalGroup 宽度只认最宽子项）
        HorizontalSpan:new { width = inner_w },
        calendar_widget,
        VerticalSpan:new { width = STATS_SEP_GAP },
        LineWidget:new {
            dimen = Geom:new { w = inner_w, h = LINE_W },
            background = Blitbuffer.COLOR_GRAY,
        },
        VerticalSpan:new { width = STATS_BOT_GAP },
        rows_group,
    }

    local card1 = FrameContainer:new {
        background = WHITE,
        color      = Blitbuffer.COLOR_GRAY,
        bordersize = CARD_B,
        radius     = CARD_R,
        padding    = CARD_PAD,
        margin     = 0,
        card1_body,
    }
    -- 尺寸算一次就定死，后面不再往这个组里 append（append 会让缓存的偏移表失效）
    local card1_h = (card1:getSize() and card1:getSize().h) or 0

    -- ===== 卡片二：当天阅读详情（吃满剩余高度）=====
    -- 高度跟着日历实际占位走：6 行格子的月份必然矮一点、少显示一行书，
    -- 但字号恒定 18，行数不强行对齐。
    local card2_y = header_h + TITLE_GAP + card1_h + CARD_GAP
    local card2_inner_h = SCR_H - FRAME_PAD - card2_y - CARD_CHROME_V
    if card2_inner_h < DETAIL_MIN_H then card2_inner_h = DETAIL_MIN_H end

    local detail_panel = buildDetailPanel(inner_w, card2_inner_h)

    local card2 = FrameContainer:new {
        background = WHITE,
        color      = Blitbuffer.COLOR_GRAY,
        bordersize = CARD_B,
        radius     = CARD_R,
        padding    = CARD_PAD,
        margin     = 0,
        VerticalGroup:new {
            align = "center",
            HorizontalSpan:new { width = inner_w },
            detail_panel,
        },
    }

    local content = VerticalGroup:new {
        align = "center",
        header_widget,
        VerticalSpan:new { width = TITLE_GAP },
        card1,
        VerticalSpan:new { width = CARD_GAP },
        card2,
        VerticalSpan:new { width = FRAME_PAD },
    }

    -- 全屏：FrameContainer 的背景是用 getSize() 画的，光传 dimen 不管用，
    -- 必须显式给 width/height（paintTo 里 container_width = self.width or my_size.w）
    self.dimen = Geom:new { x = 0, y = 0, w = SCR_W, h = SCR_H }
    self[1] = FrameContainer:new {
        radius     = 0,
        bordersize = 0,
        padding    = 0,
        margin     = 0,
        background = WHITE,
        width      = SCR_W,
        height     = SCR_H,
        content,
    }

    -- 整棵树建好后统一清一次布局缓存：确保首次 paintTo 按最终子项重算偏移，
    -- 不会因为构建期某次 getSize() 留下过期缓存而崩（见 resetLayoutTree 注释）
    resetLayoutTree(self)
end

-- 窗口自身尺寸就是整屏（FrameContainer 的 dimen 要等第一次 paintTo 才有值，不能依赖）
local function _frameDimen(self)
    return self.dimen
end

-- 只有左上角「<< 返回」和实体返回键能关窗；其余点击一律吞掉（不关窗、也不穿透翻页）
function CalendarStatsWindow:onTap(arg1, arg2)
    local ges = (arg2 and arg2.pos) and arg2 or arg1
    if ges and ges.pos then
        local px, py = ges.pos.x, ges.pos.y

        local b = self._back_rect
        if b and px >= b.x and px <= b.x + b.w and py >= b.y and py <= b.y + b.h then
            if not self._closing then
                self._closing = true
                if self._back_cell then self._back_cell.background = BLACK end
                if self._back_tw then self._back_tw.fgcolor = WHITE end
                UIManager:setDirty(self, function() return "ui", self.dimen end)
                UIManager:scheduleIn(0.15, function() self:onClose() end)
            end
            return true
        end

        for day, r in pairs(self._day_rects or {}) do
            if px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h then
                self:_selectDay(day)
                return true
            end
        end
    end
    return true
end

-- 滑动只滚动下面的书单（不关窗、不翻月）。
-- 上/左滑 = 往下看，下/右滑 = 往上看；书单不用滚时纯吞掉，避免穿透到下层翻页。
function CalendarStatsWindow:onSwipe(_arg, ges)
    local max_off = self._book_max_off or 0
    if max_off <= 0 then return true end

    local d = ges and ges.direction
    local forward = true
    if d == "south" or d == "down" or d == "west" or d == "left" then
        forward = false
    end

    local step = self._book_step or 1
    local off  = self._book_off or 0
    if forward then
        off = math.min(max_off, off + step)
    else
        off = math.max(0, off - step)
    end

    if off ~= (self._book_off or 0) then
        self:_rebuild { _book_off = off }
    end
    return true
end
function CalendarStatsWindow:onClose() UIManager:close(self); return true end
CalendarStatsWindow.onAnyKeyPressed = CalendarStatsWindow.onClose
CalendarStatsWindow.onMultiSwipe    = function() return true end

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

-- 两个宿主（阅读中 / 文件管理器）行为完全一致：先落库再开窗
local function flushStatsAndShow(ui_self)
    if ui_self.statistics and ui_self.statistics.insertDB then
        pcall(function() ui_self.statistics:insertDB() end)
    end
    showCalendarStats()
end

function ReaderUI:onCalendarStats()    flushStatsAndShow(self) end
function FileManager:onCalendarStats() flushStatsAndShow(self) end

local _M = {}
_M.show = showCalendarStats
-- 统计项已固定，不再导出 settings_menu（main.lua 也不再挂载）
return _M
