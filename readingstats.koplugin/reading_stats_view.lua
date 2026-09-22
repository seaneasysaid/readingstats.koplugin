-- reading_stats_view.lua
-- 「阅读报告」：周 / 月 / 年 / 总 四个周期的阅读统计视图。
-- 数据来源：KOReader 本地 statistics.sqlite3（page_stat + book 表），纯本地、无任何云端依赖。
-- 版式：标题栏 + 分段周期标签 + 卡片流（概览 / 趋势 / 排行 / 偏好）+ 底部翻页。
-- 本文件为原创实现（MIT），未复制任何第三方（含 AGPL）项目代码。

local Blitbuffer          = require("ffi/blitbuffer")
local BottomContainer     = require("ui/widget/container/bottomcontainer")
local CenterContainer     = require("ui/widget/container/centercontainer")
local DataStorage         = require("datastorage")
local Device              = require("device")
local FocusManager        = require("ui/widget/focusmanager")
local Font                = require("ui/font")
local FrameContainer      = require("ui/widget/container/framecontainer")
local Geom                = require("ui/geometry")
local GestureRange        = require("ui/gesturerange")
local HorizontalGroup     = require("ui/widget/horizontalgroup")
local HorizontalSpan      = require("ui/widget/horizontalspan")
local InputContainer      = require("ui/widget/container/inputcontainer")
local LeftContainer       = require("ui/widget/container/leftcontainer")
local LineWidget          = require("ui/widget/linewidget")
local OverlapGroup        = require("ui/widget/overlapgroup")
local RightContainer      = require("ui/widget/container/rightcontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Screen              = Device.screen
local Size                = require("ui/size")
local SQ3                 = require("lua-ljsqlite3/init")
local TextBoxWidget       = require("ui/widget/textboxwidget")
local TextWidget          = require("ui/widget/textwidget")
local UIManager           = require("ui/uimanager")
local VerticalGroup       = require("ui/widget/verticalgroup")
local VerticalSpan        = require("ui/widget/verticalspan")
local logger              = require("logger")

local db_path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"

local TABS = {
    { mode = "week",  text = "周" },
    { mode = "month", text = "月" },
    { mode = "year",  text = "年" },
    { mode = "total", text = "总" },
}
local MODE_TITLE = { week = "本周", month = "本月", year = "本年", total = "累计" }
local CAPTION    = { week = "本周阅读", month = "本月阅读", year = "本年阅读", total = "累计阅读" }
local WEEKDAY_LABELS = { "一", "二", "三", "四", "五", "六", "日" } -- 周一..周日

-- ===================== 数据库访问 =====================
local function withStatsDb(fallback, fn)
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(db_path, "mode") ~= "file" then
        return fallback
    end
    local conn = SQ3.open(db_path)
    if not conn then return fallback end
    local ok, result = pcall(fn, conn)
    conn:close()
    if ok then return result end
    logger.err("READING_STATS_VIEW: db error: " .. tostring(result))
    return fallback
end

local function withStatement(conn, sql, fn)
    local stmt = conn:prepare(sql)
    if not stmt then return end
    local ok, result = pcall(fn, stmt)
    stmt:close()
    if ok then return result end
end

-- ===================== 周期边界 =====================
local function weekStart(ts)
    local d = os.date("*t", ts)
    local wday = d.wday - 1 -- 周日 = 0
    local diff = (wday == 0) and 6 or (wday - 1)
    d = os.date("*t", ts - diff * 86400)
    d.hour, d.min, d.sec = 0, 0, 0
    return os.time(d)
end

local function monthStart(ts)
    local d = os.date("*t", ts)
    d.day, d.hour, d.min, d.sec = 1, 0, 0, 0
    return os.time(d)
end

local function yearStart(ts)
    local y = tonumber(os.date("%Y", ts))
    return os.time({ year = y, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
end

-- { start_ts, end_ts, label, prev_base, next_base, allow_prev, allow_next }
local function getPeriodBounds(period, base_time)
    local now = os.time()
    if period == "week" then
        local s = weekStart(base_time or now)
        return {
            start_ts = s, end_ts = s + 7 * 86400,
            label = os.date("%Y.%m.%d", s) .. " - " .. os.date("%m.%d", s + 7 * 86400 - 1),
            prev_base = s - 7 * 86400,
            next_base = s + 7 * 86400,
            allow_prev = true,
            allow_next = (s + 7 * 86400) <= now,
        }
    elseif period == "month" then
        local s = monthStart(base_time or now)
        local e = os.time({ year = tonumber(os.date("%Y", s)), month = tonumber(os.date("%m", s)) + 1,
                            day = 1, hour = 0, min = 0, sec = 0 })
        return {
            start_ts = s, end_ts = e,
            label = os.date("%Y 年 %m 月", s),
            prev_base = os.time({ year = tonumber(os.date("%Y", s)), month = tonumber(os.date("%m", s)) - 1,
                                  day = 1, hour = 0, min = 0, sec = 0 }),
            next_base = e,
            allow_prev = true,
            allow_next = e <= now,
        }
    elseif period == "year" then
        local s = yearStart(base_time or now)
        local e = os.time({ year = tonumber(os.date("%Y", s)) + 1, month = 1, day = 1,
                            hour = 0, min = 0, sec = 0 })
        return {
            start_ts = s, end_ts = e,
            label = os.date("%Y 年", s),
            prev_base = os.time({ year = tonumber(os.date("%Y", s)) - 1, month = 1, day = 1,
                                  hour = 0, min = 0, sec = 0 }),
            next_base = e,
            allow_prev = true,
            allow_next = e <= now,
        }
    end
    return {
        start_ts = 0, end_ts = now + 1,
        label = "全部记录",
        prev_base = nil, next_base = nil,
        allow_prev = false, allow_next = false,
    }
end

-- ===================== 数据查询 =====================
local function fetchSummary(b)
    local s = { duration = 0, days = 0, books = 0, max_day = 0 }
    return withStatsDb(s, function(conn)
        local where = string.format("start_time >= %d AND start_time < %d", b.start_ts, b.end_ts)
        withStatement(conn,
            "SELECT COALESCE(SUM(duration),0), "
            .. "COUNT(DISTINCT date(start_time,'unixepoch','localtime')), "
            .. "COUNT(DISTINCT id_book) FROM page_stat WHERE " .. where,
            function(stmt)
                for row in stmt:rows() do
                    s.duration = tonumber(row[1]) or 0
                    s.days     = tonumber(row[2]) or 0
                    s.books    = tonumber(row[3]) or 0
                end
            end)
        withStatement(conn,
            "SELECT COALESCE(MAX(d),0) FROM (SELECT SUM(duration) AS d FROM page_stat WHERE "
            .. where .. " GROUP BY date(start_time,'unixepoch','localtime'))",
            function(stmt)
                for row in stmt:rows() do
                    s.max_day = tonumber(row[1]) or 0
                end
            end)
        return s
    end)
end

-- 读完本数 / 笔记条数。book 表列名在不同 KOReader 版本上略有差异，
-- 查不到就保持 0，不影响其它统计。
local function fetchExtras(b)
    local e = { finished = 0, notes = 0 }
    local where    = string.format("start_time >= %d AND start_time < %d", b.start_ts, b.end_ts)
    local where_ps = string.format("ps.start_time >= %d AND ps.start_time < %d", b.start_ts, b.end_ts)
    return withStatsDb(e, function(conn)
        -- 读完：周期内读到过的最大页码 >= 该书总页数
        withStatement(conn,
            "SELECT COUNT(*) FROM ("
            .. "SELECT ps.id_book AS bid, MAX(ps.page) AS mp, b.pages AS pages "
            .. "FROM page_stat ps LEFT JOIN book b ON ps.id_book = b.id "
            .. "WHERE " .. where_ps .. " GROUP BY ps.id_book) "
            .. "WHERE pages > 0 AND mp >= pages",
            function(stmt)
                for row in stmt:rows() do
                    e.finished = tonumber(row[1]) or 0
                end
            end)
        -- 笔记：周期内读过的书累计笔记数
        withStatement(conn,
            "SELECT COALESCE(SUM(notes),0) FROM book WHERE id IN ("
            .. "SELECT DISTINCT id_book FROM page_stat WHERE " .. where .. ")",
            function(stmt)
                for row in stmt:rows() do
                    e.notes = tonumber(row[1]) or 0
                end
            end)
        return e
    end)
end

-- 柱图数据：{ {label, ts_start, ts_end, value} ... }，value 单位秒
local function fetchBuckets(period, b)
    local units = {}
    if period == "week" then
        for i = 0, 6 do
            local day_ts = b.start_ts + i * 86400
            table.insert(units, { label = WEEKDAY_LABELS[i + 1], ts_start = day_ts,
                                  ts_end = day_ts + 86400, value = 0 })
        end
    elseif period == "month" then
        local days = tonumber(os.date("%d", b.end_ts - 1))
        for i = 1, days do
            local day_ts = b.start_ts + (i - 1) * 86400
            table.insert(units, { label = tostring(i), ts_start = day_ts,
                                  ts_end = day_ts + 86400, value = 0 })
        end
    elseif period == "year" then
        local y = tonumber(os.date("%Y", b.start_ts))
        for m = 1, 12 do
            table.insert(units, {
                label = tostring(m),
                ts_start = os.time({ year = y, month = m, day = 1, hour = 0, min = 0, sec = 0 }),
                ts_end   = os.time({ year = y, month = m + 1, day = 1, hour = 0, min = 0, sec = 0 }),
                value = 0,
            })
        end
    else -- total：最近 10 年（没阅读的年份也保留空位）
        local y_max = tonumber(os.date("%Y", os.time()))
        for y = y_max - 9, y_max do
            table.insert(units, {
                label = tostring(y),
                ts_start = os.time({ year = y, month = 1, day = 1, hour = 0, min = 0, sec = 0 }),
                ts_end   = os.time({ year = y + 1, month = 1, day = 1, hour = 0, min = 0, sec = 0 }),
                value = 0,
            })
        end
    end

    withStatsDb(nil, function(conn)
        if period == "total" then
            withStatement(conn,
                "SELECT strftime('%Y',start_time,'unixepoch','localtime') y, "
                .. "COALESCE(SUM(duration),0) FROM page_stat GROUP BY y",
                function(stmt)
                    for row in stmt:rows() do
                        local y = tonumber(row[1])
                        for _, u in ipairs(units) do
                            if tonumber(u.label) == y then u.value = tonumber(row[2]) or 0 end
                        end
                    end
                end)
        else
            withStatement(conn,
                "SELECT start_time, COALESCE(SUM(duration),0) FROM page_stat "
                .. "WHERE start_time >= " .. b.start_ts .. " AND start_time < " .. b.end_ts
                .. " GROUP BY date(start_time,'unixepoch','localtime')",
                function(stmt)
                    for row in stmt:rows() do
                        local ts = tonumber(row[1]) or 0
                        local v  = tonumber(row[2]) or 0
                        for _, u in ipairs(units) do
                            if ts >= u.ts_start and ts < u.ts_end then u.value = u.value + v end
                        end
                    end
                end)
        end
    end)

    -- 月视图天数太多，只保留有阅读的日子；周 / 年 / 总 保留完整刻度（没阅读的就没有柱子）
    if period == "month" then
        local active = {}
        for _, u in ipairs(units) do
            if u.value > 0 then table.insert(active, u) end
        end
        return active
    end
    return units
end

-- 阅读时段偏好：按 start_time 的小时归入 4 个时段
local function fetchPreference(b)
    local buckets = {
        { name = "凌晨 0-6 点", dur = 0 },
        { name = "上午 6-12 点", dur = 0 },
        { name = "下午 12-18 点", dur = 0 },
        { name = "晚上 18-24 点", dur = 0 },
    }
    withStatsDb(nil, function(conn)
        withStatement(conn,
            "SELECT strftime('%H',start_time,'unixepoch','localtime') h, "
            .. "COALESCE(SUM(duration),0) FROM page_stat "
            .. "WHERE start_time >= " .. b.start_ts .. " AND start_time < " .. b.end_ts
            .. " GROUP BY h",
            function(stmt)
                for row in stmt:rows() do
                    local hh = tonumber(row[1]) or 0
                    local v  = tonumber(row[2]) or 0
                    local idx = (hh < 6) and 1 or (hh < 12) and 2 or (hh < 18) and 3 or 4
                    buckets[idx].dur = buckets[idx].dur + v
                end
            end)
    end)
    return buckets
end

local function fetchTopBooks(b)
    local books = {}
    return withStatsDb(books, function(conn)
        local where = string.format(
            "page_stat.start_time >= %d AND page_stat.start_time < %d", b.start_ts, b.end_ts)
        withStatement(conn, [[
            SELECT book.title,
                   COALESCE(SUM(page_stat.duration),0) AS duration_seconds
            FROM page_stat
            JOIN book ON page_stat.id_book = book.id
            WHERE ]] .. where .. [[
            GROUP BY page_stat.id_book
            HAVING duration_seconds > 0
            ORDER BY duration_seconds DESC
            LIMIT 10
        ]], function(stmt)
            for row in stmt:rows() do
                local title = row[1] or ""
                if title == "" or title == "N/A" then title = "未知书名" end
                table.insert(books, {
                    title    = title,
                    duration = tonumber(row[2]) or 0,
                })
            end
        end)
        return books
    end)
end

-- ===================== 格式化 =====================
-- 全站统一的时长格式：99小时18分钟 / 45分钟 / <1分钟（只用「小时 / 分钟」两个单位）
local function fmtDuration(sec)
    sec = tonumber(sec) or 0
    if sec <= 0 then return "0分钟" end
    if sec < 60 then return "<1分钟" end
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then
        if m > 0 then return string.format("%d小时%d分钟", h, m) end
        return string.format("%d小时", h)
    end
    return string.format("%d分钟", m)
end

local fmtDurationShort = fmtDuration -- 列表 / 比例条用

-- 柱图数值轴刻度：15小时 / 4.5小时 / 45分钟 / <1分钟 / 0
local function fmtAxis(sec)
    sec = tonumber(sec) or 0
    if sec >= 3600 then
        local h = sec / 3600
        if h >= 10 then return string.format("%d小时", math.floor(h + 0.5)) end
        return string.format("%.1f小时", h)
    end
    if sec >= 60 then return string.format("%d分钟", math.floor(sec / 60 + 0.5)) end
    if sec > 0 then return "<1分钟" end
    return "0"
end

-- 概览卡片的大数字也走同一套格式（99小时18分钟 / 45分钟）
local fmtDurationTitle = fmtDuration

-- ===================== 视图 =====================
local ReadingStatsView = FocusManager:extend{
    ui = nil,
    mode = "month",
    base_time = nil,
    covers_fullscreen = true,
}

function ReadingStatsView:faces()
    return {
        big     = Font:getFace("tfont", 36),   -- 概览大数字
        unit    = Font:getFace("cfont", 22),   -- 大数字的单位（小时 / 分钟），比数字小一档
        caption = Font:getFace("cfont", 15),   -- 卡片内小字说明
        card    = Font:getFace("tfont", 18),   -- 卡片标题
        body    = Font:getFace("cfont", 16),   -- 正文 / 列表
        small   = Font:getFace("cfont", 13),   -- 柱图刻度
        tab     = Font:getFace("cfont", 18),   -- 周期标签
    }
end

-- 零高度撑条：把纵向组钉到内容宽度（FrameContainer 的 width 不约束内容）
function ReadingStatsView:widthPin()
    return HorizontalSpan:new{ width = self.content_width }
end

function ReadingStatsView:makeCard(inner)
    return FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = self.card_border,
        color      = Blitbuffer.COLOR_GRAY,
        radius     = Screen:scaleBySize(8),
        padding    = self.card_padding,
        margin     = 0,
        inner,
    }
end

function ReadingStatsView:cardTitle(text)
    local f = self.fonts
    return VerticalGroup:new{
        align = "left",
        TextWidget:new{ text = text, face = f.card, max_width = self.content_width },
        VerticalSpan:new{ width = Size.padding.small },
        LineWidget:new{
            dimen = Geom:new{ w = self.content_width, h = self.line_thin },
            background = Blitbuffer.COLOR_GRAY,
        },
        VerticalSpan:new{ width = Size.padding.default },
    }
end

-- 左标签 + 右数值，铺满内容宽度
function ReadingStatsView:kvLine(left, right, face, right_color)
    face = face or self.fonts.body
    local right_tw = TextWidget:new{ text = right, face = face,
        fgcolor = right_color or Blitbuffer.COLOR_BLACK }
    local rw = right_tw:getSize().w
    local left_tw = TextWidget:new{
        text = left, face = face,
        max_width = math.max(1, self.content_width - rw - Size.padding.default),
    }
    local gap = math.max(Size.padding.small, self.content_width - rw - left_tw:getSize().w)
    return HorizontalGroup:new{
        align = "center",
        left_tw,
        HorizontalSpan:new{ width = gap },
        right_tw,
    }
end

-- 比例条：「名称 …… 数值」+ 一根与占比成正比的实心条
-- 底下垫一层浅灰轨道，这样占比为 0 / 极小时也不会只留下一条莫名其妙的短线
function ReadingStatsView:proportionBar(name, value_text, ratio)
    ratio = math.max(0, math.min(1, tonumber(ratio) or 0))
    local layers = {
        LineWidget:new{
            dimen = Geom:new{ w = self.content_width, h = self.bar_thin },
            background = Blitbuffer.COLOR_GRAY_E,
        },
    }
    local bar_w = math.floor(ratio * self.content_width + 0.5)
    if bar_w > 0 then
        table.insert(layers, LineWidget:new{
            dimen = Geom:new{ w = bar_w, h = self.bar_thin },
            background = Blitbuffer.COLOR_BLACK,
        })
    end
    return VerticalGroup:new{
        align = "left",
        self:widthPin(),
        self:kvLine(name, value_text, self.fonts.body),
        VerticalSpan:new{ width = Size.padding.tiny },
        OverlapGroup:new(layers),
    }
end

-- ---------- 卡片 ----------
function ReadingStatsView:buildOverviewCard()
    local d, f = self.data, self.fonts
    local content = VerticalGroup:new{ align = "left", self:widthPin() }

    -- 第一行：总时长（大字）+ 「累计阅读 / 本月阅读」小字
    local cap_tw = TextWidget:new{ text = self.caption_text, face = f.caption,
        fgcolor = Blitbuffer.COLOR_GRAY_7 }
    local reserve = cap_tw:getSize().w + Size.padding.default
    local big_tw = TextWidget:new{
        text = fmtDurationTitle(d.total), face = f.big,
        max_width = math.max(1, self.content_width - reserve),
    }
    table.insert(content, HorizontalGroup:new{
        align = "bottom",
        big_tw,
        HorizontalSpan:new{ width = Size.padding.default },
        cap_tw,
    })

    -- 第二行：阅读 N 天 · 日均 X · 较上期 ↑ N%
    local daily = (d.days > 0) and math.floor(d.total / d.days) or 0
    local parts = { string.format("阅读 %d 天", d.days) }
    if d.days > 0 then
        parts[#parts + 1] = "日均 " .. fmtDuration(daily)
    end
    if d.compare then
        local pct = math.floor(math.abs(d.compare) * 100 + 0.5)
        if pct > 0 then
            parts[#parts + 1] = "较上期 " .. (d.compare > 0 and "↑" or "↓") .. pct .. "%"
        end
    end
    table.insert(content, VerticalSpan:new{ width = Size.padding.small })
    table.insert(content, TextBoxWidget:new{
        text = table.concat(parts, "  ·  "),
        face = f.body, width = self.content_width,
    })

    -- 第三行：读过 / 读完 / 阅读天数 / 笔记
    table.insert(content, VerticalSpan:new{ width = Size.padding.default })
    table.insert(content, LineWidget:new{
        dimen = Geom:new{ w = self.content_width, h = self.line_thin },
        background = Blitbuffer.COLOR_GRAY,
    })
    table.insert(content, VerticalSpan:new{ width = Size.padding.default })
    table.insert(content, TextBoxWidget:new{
        text = string.format("读过 %d 本      读完 %d 本      阅读 %d 天      笔记 %d 条",
            d.books, d.finished, d.days, d.notes),
        face = f.body, width = self.content_width,
    })

    return self:makeCard(content)
end

function ReadingStatsView:buildChartCard()
    local d, f = self.data, self.fonts
    local units = d.buckets
    if #units == 0 then return nil end

    local n = #units
    local maxv = 1
    for _, u in ipairs(units) do
        if u.value > maxv then maxv = u.value end
    end

    local chart_h = Screen:scaleBySize(104)
    -- 数值轴只保留峰值刻度（底部 0 刻度省略，避免在柱子前多出一个 0）
    local axis_top = TextWidget:new{ text = fmtAxis(maxv), face = f.small }
    local lh = axis_top:getSize().h
    local axis_w = axis_top:getSize().w
    local axis_col = VerticalGroup:new{
        align = "right",
        RightContainer:new{ dimen = Geom:new{ w = axis_w, h = lh }, axis_top },
        VerticalSpan:new{ width = math.max(0, chart_h - lh) },
    }

    local axis_gap = Size.padding.small
    local chart_w = math.max(Screen:scaleBySize(60), self.content_width - axis_w - axis_gap)
    local gap = Screen:scaleBySize(n > 16 and 2 or 5)
    local bar_w = math.floor((chart_w - (n - 1) * gap) / n)
    if bar_w < 1 then
        bar_w, gap = 1, 0
    end
    local label_step = (n <= 12) and 1 or math.max(1, math.ceil(n / 8))

    local bars_row   = HorizontalGroup:new{ align = "bottom" }
    local labels_row = HorizontalGroup:new{ align = "top" }
    for i, u in ipairs(units) do
        local bh = math.floor((u.value / maxv) * chart_h + 0.5)
        if bh == 0 and u.value > 0 then bh = 1 end
        local col = (bh > 0)
            and LineWidget:new{ dimen = Geom:new{ w = bar_w, h = bh }, background = Blitbuffer.COLOR_BLACK }
            or HorizontalSpan:new{ width = bar_w }
        table.insert(bars_row, BottomContainer:new{ dimen = Geom:new{ w = bar_w, h = chart_h }, col })

        local lbl = ((i - 1) % label_step == 0) and u.label or ""
        table.insert(labels_row, CenterContainer:new{
            dimen = Geom:new{ w = bar_w, h = lh + Screen:scaleBySize(2) },
            TextWidget:new{ text = lbl, face = f.small },
        })
        if i < n then
            table.insert(bars_row, HorizontalSpan:new{ width = gap })
            table.insert(labels_row, HorizontalSpan:new{ width = gap })
        end
    end

    local chart_col = VerticalGroup:new{
        align = "left",
        bars_row,
        LineWidget:new{ dimen = Geom:new{ w = chart_w, h = self.line_thin }, background = Blitbuffer.COLOR_BLACK },
        VerticalSpan:new{ width = Size.padding.tiny },
        labels_row,
    }

    local content = VerticalGroup:new{
        align = "left",
        self:widthPin(),
        self:cardTitle("阅读时长趋势"),
        HorizontalGroup:new{
            align = "top",
            axis_col,
            HorizontalSpan:new{ width = axis_gap },
            chart_col,
        },
    }
    return self:makeCard(content)
end

function ReadingStatsView:buildRankCard()
    local list = self.data.books_top
    if #list == 0 then return nil end
    local maxs = 1
    for _, it in ipairs(list) do
        if it.duration > maxs then maxs = it.duration end
    end

    local content = VerticalGroup:new{ align = "left", self:widthPin(), self:cardTitle("读书排行") }
    for i, it in ipairs(list) do
        if i > 1 then
            table.insert(content, VerticalSpan:new{ width = Size.padding.default })
        end
        table.insert(content, self:proportionBar(
            string.format("%d. %s", i, it.title),
            fmtDurationShort(it.duration),
            it.duration / maxs))
    end
    return self:makeCard(content)
end

function ReadingStatsView:buildPreferenceCard()
    local buckets = self.data.prefer
    local total = 0
    for _, b in ipairs(buckets) do
        total = total + b.dur
    end
    if total <= 0 then return nil end

    local content = VerticalGroup:new{ align = "left", self:widthPin(), self:cardTitle("阅读偏好") }
    for _, b in ipairs(buckets) do
        local ratio = b.dur / total
        table.insert(content, self:proportionBar(b.name, fmtDurationShort(b.dur), ratio))
        table.insert(content, VerticalSpan:new{ width = Size.padding.small })
    end

    return self:makeCard(content)
end

function ReadingStatsView:buildEmptyCard()
    return self:makeCard(VerticalGroup:new{
        align = "left",
        self:widthPin(),
        TextWidget:new{ text = "本周期还没有阅读记录。", face = self.fonts.body,
            max_width = self.content_width },
    })
end

function ReadingStatsView:buildContent()
    local page = VerticalGroup:new{ align = "left" }
    local function add(card)
        if not card then return end
        if #page > 0 then
            table.insert(page, VerticalSpan:new{ width = Size.padding.large })
        end
        table.insert(page, card)
    end
    if self.data.total <= 0 then
        add(self:buildEmptyCard())
        return page
    end
    add(self:buildOverviewCard())
    add(self:buildChartCard())
    add(self:buildRankCard())
    add(self:buildPreferenceCard())
    return page
end

-- ---------- 框架 ----------
-- 全屏视图下子控件的手势区域坐标不可靠（局部坐标会被当成屏幕坐标），
-- 因此由视图自身统一接收 tap，再用屏幕坐标做命中判断。
function ReadingStatsView:addHitRect(x, y, w, h, action)
    self.hit_rects[#self.hit_rects + 1] = { x = x, y = y, w = w, h = h, action = action }
end

-- 兼容两种回调约定：(_, ges) 与 (ges)
function ReadingStatsView:onTap(arg1, arg2)
    local ges = arg2 or arg1
    if ges and ges.pos then
        local px, py = ges.pos.x, ges.pos.y
        for _, r in ipairs(self.hit_rects) do
            if px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h then
                r.action()
                return true
            end
        end
    end
    return true -- 全屏页面：吞掉空白区点击，避免穿透到底层界面
end

function ReadingStatsView:buildTabBar(top)
    local n = #TABS
    local border = self.line_thin
    local cell_w = math.floor(self.screen_w / n)
    local inner_w = cell_w - 2 * border
    local cell_h = Screen:scaleBySize(40)
    local row = HorizontalGroup:new{ align = "center" }
    for i, tab in ipairs(TABS) do
        local mode = tab.mode
        local active = (mode == self.mode)
        local tw = TextWidget:new{
            text = tab.text, face = self.fonts.tab,
            fgcolor = active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
        }
        table.insert(row, FrameContainer:new{
            bordersize = border,
            color      = Blitbuffer.COLOR_GRAY,
            background = active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
            padding = 0, margin = 0,
            CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = cell_h }, tw },
        })
        self:addHitRect((i - 1) * cell_w, top, cell_w, cell_h + 2 * border, function()
            if mode ~= self.mode then self:rebuild(mode, nil) end
        end)
    end
    return row
end

function ReadingStatsView:buildNavRow(top, cell_h, pad)
    local b = self.bounds
    if not b.allow_prev and not b.allow_next then return nil end

    local border = self.line_thin
    local gap = Size.padding.default
    local cell_w = math.floor((self.screen_w - 2 * pad - gap) / 2)

    local function navCell(text, enabled)
        local tw = TextWidget:new{
            text = text, face = self.fonts.body,
            fgcolor = enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY,
        }
        return FrameContainer:new{
            bordersize = border,
            color      = Blitbuffer.COLOR_GRAY,
            background = Blitbuffer.COLOR_WHITE,
            padding = 0, margin = 0,
            CenterContainer:new{ dimen = Geom:new{ w = cell_w - 2 * border, h = cell_h }, tw },
        }
    end

    if b.allow_prev then
        self:addHitRect(pad, top, cell_w, cell_h + 2 * border, function()
            self:rebuild(self.mode, b.prev_base)
        end)
    end
    if b.allow_next then
        self:addHitRect(pad + cell_w + gap, top, cell_w, cell_h + 2 * border, function()
            self:rebuild(self.mode, b.next_base)
        end)
    end

    return FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0, padding = pad, margin = 0,
        HorizontalGroup:new{
            align = "center",
            navCell("‹  上一周期", b.allow_prev),
            HorizontalSpan:new{ width = gap },
            navCell("下一周期  ›", b.allow_next),
        },
    }
end

function ReadingStatsView:buildHeader()
    local title = MODE_TITLE[self.mode] or "阅读报告"
    local label = self.bounds.label
    if label and label ~= "" then
        title = title .. "·" .. label
    end

    local border = self.line_thin
    local close_tw = TextWidget:new{ text = "关闭", face = self.fonts.body }
    local close_w = close_tw:getSize().w + Screen:scaleBySize(24)
    local close_h = Screen:scaleBySize(32)
    local close_fc = FrameContainer:new{
        bordersize = border,
        color      = Blitbuffer.COLOR_GRAY,
        background = Blitbuffer.COLOR_WHITE,
        padding = 0, margin = 0,
        CenterContainer:new{ dimen = Geom:new{ w = close_w, h = close_h }, close_tw },
    }
    -- 标题在整屏居中：左右预留对称空间（左侧留出与「关闭」等宽的区域）
    local close_cell_w = close_w + 2 * border
    local gap    = Size.padding.default
    local margin = Size.padding.large
    local title_w = math.max(1, self.screen_w - 2 * close_cell_w - 2 * margin - gap)
    local title_tw = TextWidget:new{ text = title, face = self.fonts.card, max_width = title_w }
    local row_h = math.max(title_tw:getSize().h, close_h + 2 * border)

    local left_pad = close_cell_w + margin
    self:addHitRect(left_pad + title_w + gap, 0, close_cell_w, row_h, function() self:onClose() end)

    local row = HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = left_pad },
        CenterContainer:new{ dimen = Geom:new{ w = title_w, h = row_h }, title_tw },
        HorizontalSpan:new{ width = gap },
        close_fc,
        HorizontalSpan:new{ width = margin },
    }

    return VerticalGroup:new{
        align = "left",
        row,
        LineWidget:new{
            dimen = Geom:new{ w = self.screen_w, h = self.line_thin },
            background = Blitbuffer.COLOR_BLACK,
        },
    }
end

function ReadingStatsView:init()
    self.fonts    = self:faces()
    self.screen_w = Screen:getWidth()
    self.screen_h = Screen:getHeight()
    self.dimen    = Geom:new{ x = 0, y = 0, w = self.screen_w, h = self.screen_h }

    self.line_thin    = math.max(1, Screen:scaleBySize(1))
    self.bar_thin     = math.max(1, Screen:scaleBySize(6))
    self.outer_margin = Screen:scaleBySize(8)
    self.card_border  = Screen:scaleBySize(1)
    self.card_padding = Screen:scaleBySize(12)

    local scrollbar_reserve = 3 * Screen:scaleBySize(6)
    local usable_w = self.screen_w - scrollbar_reserve - 2 * self.outer_margin
    local inner_w  = usable_w - 2 * self.card_border - 2 * self.card_padding
    self.content_width = math.max(Screen:scaleBySize(120), inner_w)

    -- 数据
    self.bounds = getPeriodBounds(self.mode, self.base_time)
    local b = self.bounds
    local sum = fetchSummary(b)
    local extra = fetchExtras(b)
    self.data = {
        total    = sum.duration,
        days     = sum.days,
        books    = sum.books,
        max_day  = sum.max_day,
        finished = extra.finished,
        notes    = extra.notes,
        buckets  = fetchBuckets(self.mode, b),
        books_top = fetchTopBooks(b),
        prefer   = fetchPreference(b),
    }
    if self.mode ~= "total" and b.prev_base then
        local prev = fetchSummary(getPeriodBounds(self.mode, b.prev_base))
        if prev.duration > 0 then
            self.data.compare = (self.data.total - prev.duration) / prev.duration
        end
    end

    self.caption_text = CAPTION[self.mode] or "累计阅读"

    -- 框架：点击区域按屏幕坐标登记，由视图自身统一命中
    self.hit_rects = {}
    local header   = self:buildHeader()
    local header_h = header:getSize().h
    local tab_bar  = self:buildTabBar(header_h)
    local tab_h    = tab_bar:getSize().h
    local nav_pad  = Screen:scaleBySize(6)
    local nav_cell = Screen:scaleBySize(42)
    local nav_row  = self:buildNavRow(
        self.screen_h - (nav_cell + 2 * self.line_thin + 2 * nav_pad), nav_cell, nav_pad)

    local top_h = header_h + tab_h
    local nav_h = nav_row and nav_row:getSize().h or 0
    local scroll_h = math.max(Screen:scaleBySize(80), self.screen_h - top_h - nav_h)

    local scroll = ScrollableContainer:new{
        dimen = Geom:new{ w = self.screen_w, h = scroll_h },
        show_parent = self,
        HorizontalGroup:new{
            align = "top",
            HorizontalSpan:new{ width = self.outer_margin },
            VerticalGroup:new{
                align = "left",
                VerticalSpan:new{ width = self.outer_margin },
                self:buildContent(),
                VerticalSpan:new{ width = self.outer_margin },
            },
        },
    }

    local body = VerticalGroup:new{ align = "left", header, tab_bar, scroll }
    if nav_row then
        table.insert(body, nav_row)
    end

    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0, padding = 0, margin = 0,
        dimen = self.dimen:copy(),
        body,
    }

    if Device:isTouchDevice() then
        -- 全屏视图：由自己统一接收 tap，再按 hit_rects 命中（周/月/年/总、翻页、关闭）
        self.ges_events = {
            Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        }
    end

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
end

function ReadingStatsView:onShow()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
    return true
end

function ReadingStatsView:onCloseWidget()
    UIManager:setDirty(nil, function() return "ui", self.dimen end)
end

function ReadingStatsView:onClose()
    UIManager:close(self)
    return true
end

-- 切换周期 / 翻页：关掉当前视图，用新参数重建
function ReadingStatsView:rebuild(mode, base_time)
    local ui = self.ui
    UIManager:close(self)
    ReadingStatsView.show(ui, mode, base_time)
    return true
end

-- 注意：这里用点号调用（X.show(ui, mode, base)），所以不能写成冒号方法，
-- 否则参数会整体错位一格，mode 永远回落成默认值。
function ReadingStatsView.show(ui, mode, base_time)
    local view = ReadingStatsView:new{
        ui        = ui,
        mode      = mode or "month",
        base_time = base_time,
    }
    UIManager:show(view)
    return view
end

return ReadingStatsView
