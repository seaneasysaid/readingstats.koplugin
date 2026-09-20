-- heatmap_view.lua
-- 「阅读热力图」独立视图 —— GitHub 贡献图风格。
--
-- 算法与配色移植自 inkstain.koplugin（墨痕壁纸）的 drawHeatmap / heatmapLevelColor：
--   * 网格为「周（列） × 7 天（行）」，起始日对齐周一
--   * 5 级灰阶：0 = 无阅读（白），1~4 阅读量递增、颜色渐深
--   * 阈值按 p90 分位归一化后再按 25 / 50 / 75 / 100% 切分
-- 原实现绘制在 Blitbuffer 上（生成 PNG 壁纸），这里改为 KOReader 屏幕控件绘制，
-- 因此能直接在屏幕上交互、翻页。
--
-- 注意：绝不能用 `_` 当循环变量，会遮蔽上面的 gettext。

local Blitbuffer      = require("ffi/blitbuffer")
local Button          = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage     = require("datastorage")
local db_location     = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local SQ3             = require("lua-ljsqlite3/init")
local Screen          = Device.screen
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local Widget          = require("ui/widget/widget")
local logger          = require("logger")
local _               = require("gettext")

local SECS_DAY = 86400
local WHITE    = Blitbuffer.COLOR_WHITE
local BLACK    = Blitbuffer.COLOR_BLACK

local FONT_BOLD = "NotoSans-Bold.ttf"
local FONT_REG  = "NotoSans-Regular.ttf"

-- ============================================================
-- 设置（与月历的 mini_rs_sett 分开存，避免互相覆盖）
-- ============================================================

local HM_DEFAULTS = { weeks = 26 }
local HM_SETT = G_reader_settings:readSetting("mini_hm_sett", HM_DEFAULTS)
if type(HM_SETT) ~= "table" then HM_SETT = HM_DEFAULTS end
if HM_SETT.weeks ~= 26 and HM_SETT.weeks ~= 52 then HM_SETT.weeks = HM_DEFAULTS.weeks end

local function saveSett()
    pcall(function() G_reader_settings:saveSetting("mini_hm_sett", HM_SETT) end)
end

-- ============================================================
-- 颜色：inkstain 的 5 级灰阶
-- ============================================================

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

-- inkstain 的 HEATMAP_LEVEL_GRAY 是「黑度」{0.16, 0.34, 0.52, 0.70, 0.90}，
-- 取值时用的是 [level + 1]，而 level 0 已提前返回白色 —— 所以实际生效的是
-- 0.34 / 0.52 / 0.70 / 0.90（0.16 那一项没被用到）。这里换算成 0~255 亮度
-- （值越小越黑），以对齐它真实的渲染效果。
local HM_LEVEL_V = { [1] = 168, [2] = 122, [3] = 76, [4] = 25 }
local HM_FILL = {}
for _i = 1, 4 do
    HM_FILL[_i] = makeGray(HM_LEVEL_V[_i])
              or (_i <= 2 and (Blitbuffer.COLOR_GRAY_4 or Blitbuffer.COLOR_GRAY_3))
              or (Blitbuffer.COLOR_GRAY_1 or Blitbuffer.COLOR_GRAY_2)
              or BLACK
end
-- 格子边框：inkstain 用黑度 0.85
local HM_BORDER = makeGray(38) or Blitbuffer.COLOR_GRAY_1 or BLACK

-- ============================================================
-- 方块控件（与月历的 ColorBox 同款画法）
-- ============================================================

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

-- ============================================================
-- 数据库：按天聚合阅读秒数
-- ============================================================

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

-- 返回 { ["2026-09-19"] = seconds }
local function queryDailyRange(conn, start_ts, end_ts)
    if not conn then return {} end
    local sql = string.format([[
        SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS ds,
               sum(duration) AS dur
        FROM page_stat
        WHERE start_time >= %d AND start_time < %d
        GROUP BY ds;
    ]], start_ts, end_ts)
    local res = dbQuery(conn, sql)
    local daily = {}
    if res and type(res[1]) == "table" then
        for i = 1, #res[1] do
            local ds   = res[1][i]
            local secs = tonumber(res[2] and res[2][i]) or 0
            if ds and ds ~= "" then
                daily[ds] = (daily[ds] or 0) + secs
            end
        end
    end
    return daily
end

-- ============================================================
-- 时间区间：以周对齐，offset = 0 表示「最近 N 周」
-- ============================================================

local function midnight(ts)
    local ok, t = pcall(os.date, "*t", ts or os.time())
    if not ok or type(t) ~= "table" then return os.time() end
    t.hour, t.min, t.sec = 0, 0, 0
    local ok2, r = pcall(os.time, t)
    return (ok2 and r) or os.time()
end

-- 0 = 周一 ... 6 = 周日
local function mondayIndex(ts)
    local wday = tonumber(os.date("%w", ts)) or 1  -- 0=周日, 1=周一 ... 6=周六
    return (wday == 0) and 6 or (wday - 1)
end

-- 返回 [start_ts, end_ts)，两端都是周一 00:00
local function periodRange(weeks, offset)
    offset = offset or 0
    local today  = midnight(os.time())
    -- 本周日 24:00 == 下周一 00:00
    local end_ts = today + (7 - mondayIndex(today)) * SECS_DAY
    end_ts = end_ts + offset * weeks * 7 * SECS_DAY
    local start_ts = end_ts - weeks * 7 * SECS_DAY
    return start_ts, end_ts
end

-- ============================================================
-- 分级：p90 归一化 + 四分位（与 inkstain 一致）
-- ============================================================

local function computeLevels(day_list)
    local sorted = {}
    for _i, d in ipairs(day_list) do
        if d.seconds > 0 then sorted[#sorted + 1] = d.seconds end
    end
    table.sort(sorted)

    local max_sec = 60
    if #sorted > 0 then
        local p90_idx = math.max(1, math.floor(#sorted * 0.9))
        max_sec = math.max(60, sorted[p90_idx] or 60)
    end

    for _i, d in ipairs(day_list) do
        if d.seconds <= 0 or max_sec <= 0 then
            d.level = 0
        else
            local ratio = d.seconds / max_sec
            if ratio <= 0.25 then      d.level = 1
            elseif ratio <= 0.50 then  d.level = 2
            elseif ratio <= 0.75 then  d.level = 3
            else                       d.level = 4
            end
        end
    end
    return max_sec
end

local function fmtDuration(secs)
    secs = math.floor(tonumber(secs) or 0)
    if secs < 0 then secs = 0 end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then return string.format(_("%d小时%d分"), h, m) end
    if m > 0 then return string.format(_("%d分钟"), m) end
    return string.format(_("%d秒"), secs)
end

local function fmtDate(ts)
    local ok, s = pcall(os.date, "%Y-%m-%d", ts)
    return (ok and s) or ""
end

-- ============================================================
-- 窗口
-- ============================================================

local HeatmapWindow = InputContainer:extend{ modal = true, name = "heatmap_window" }

function HeatmapWindow:init()
    -- 必须给实例自己的表：直接用继承来的会改到 InputContainer 的类表（污染全局）
    self.ges_events = {}
    self.key_events = {}
    if self._offset == nil then self._offset = 0 end
    if self._weeks  == nil then self._weeks = HM_SETT.weeks or 26 end

    if Device:hasKeys() then
        local any_group = Device.input and Device.input.group and Device.input.group.Any
        if any_group then
            self.key_events.AnyKeyPressed = { { any_group } }
        end
    end
    if Device:isTouchDevice() then
        local function rng() return Screen:getSize() end
        self.ges_events.Swipe = { GestureRange:new { ges = "swipe", range = rng } }
        self.ges_events.Tap = { GestureRange:new { ges = "tap", range = rng } }
        self.ges_events.MultiSwipe = { GestureRange:new { ges = "multiswipe", range = rng } }
    end

    self:_build()
end

-- 翻页：整段位移（不重叠），不允许翻到未来
function HeatmapWindow:_switchTo(offset)
    if offset > 0 then offset = 0 end
    UIManager:close(self)
    UIManager:show(HeatmapWindow:new { _offset = offset, _weeks = self._weeks }, "ui")
end

function HeatmapWindow:_prev() self:_switchTo((self._offset or 0) - 1) end
function HeatmapWindow:_next() self:_switchTo((self._offset or 0) + 1) end

function HeatmapWindow:_build()
    local self_ref = self
    local weeks    = self._weeks or 26
    local offset   = self._offset or 0

    local FRAME_PAD    = Screen:scaleBySize(12)
    local CORNER_R     = Screen:scaleBySize(12)
    local CELL_R       = Screen:scaleBySize(1)  -- 近方形；圆角大了会像胶囊
    local SECTION_GAP  = Screen:scaleBySize(10)
    local NAV_BTN_PAD  = Screen:scaleBySize(6)
    local GAP          = Screen:scaleBySize(2)
    local CELL_MAX     = Screen:scaleBySize(44) -- 单格上限，防止极端宽屏上格子过大
    local MONTH_H      = Screen:scaleBySize(14)

    local function scaleLine(v)
        local s = Screen:scaleBySize(v)
        if s < 1 then s = 1 end
        return s
    end
    local FRAME_BORDER = scaleLine(0.6)
    local CELL_BW      = scaleLine(0.4)

    local face_title = Font:getFace(FONT_BOLD, 18)
    local face_sub   = Font:getFace(FONT_REG,  14)
    local face_tiny  = Font:getFace(FONT_REG,  11)

    local start_ts, end_ts = periodRange(weeks, offset)

    -- ---- 取数 ----
    local daily = {}
    local conn = dbOpen()
    if conn then
        local ok, res = pcall(queryDailyRange, conn, start_ts, end_ts)
        if ok and type(res) == "table" then daily = res end
        pcall(function() conn:close() end)
    end

    -- ---- 构造天列表（起始日已对齐周一，故第 i 天就是第 i%7 行）----
    local today_ts = midnight(os.time())
    local day_list = {}
    local total_secs, active_days, max_day = 0, 0, 0
    for i = 0, weeks * 7 - 1 do
        local ts = start_ts + i * SECS_DAY
        local secs = tonumber(daily[fmtDate(ts)]) or 0
        if secs < 0 then secs = 0 end
        day_list[#day_list + 1] = { ts = ts, seconds = secs, level = 0, future = ts > today_ts }
        total_secs = total_secs + secs
        if secs > 0 then active_days = active_days + 1 end
        if secs > max_day then max_day = secs end
    end
    computeLevels(day_list)

    -- ---- 格子尺寸 ----
    local screen_w = Screen:getWidth()
    local inner_w  = screen_w - (FRAME_PAD + FRAME_BORDER) * 2
    if inner_w < 100 then inner_w = 100 end

    -- ---- 分行：每行最多 26 周，52 周自动变 2 行（每行 26 周）----
    -- 这样 52 周的格子跟 26 周一样大，横向铺满，纵向排两排。
    local row_blocks = math.max(1, math.ceil(weeks / 26))
    local cols       = math.ceil(weeks / row_blocks)

    local screen_h = Screen:getHeight()
    local wd_w = 0
    local show_weekday = false

    -- 先按宽度算：格子尽量吃满可用宽度
    local function cellByWidth()
        local avail_w = inner_w - wd_w
        local c = math.floor((avail_w - GAP * (cols - 1)) / cols)
        if c < 4 then c = 4 end
        return c
    end
    -- 再按高度算：整块（月份标签 + 7 行网格）要能塞进屏幕
    local function cellByHeight()
        -- 窗口里除网格外的固定高度
        local fixed_h = 26 + 2 + 18 + SECTION_GAP          -- 标题 + 区间
                      + SECTION_GAP + 16 + 6 + 18          -- 图例 + 汇总
                      + (FRAME_PAD + FRAME_BORDER) * 2
        local block_fixed = row_blocks * (MONTH_H + Screen:scaleBySize(4) + GAP * 6)
                          + (row_blocks - 1) * SECTION_GAP
        local avail_h = screen_h * 0.94 - fixed_h - block_fixed
        local c = math.floor(avail_h / (7 * row_blocks))
        if c < 4 then c = 4 end
        return c
    end

    local cell = cellByWidth()
    -- 格子够大时才显示左侧「一/三/五」，否则行高撑不住文字会错位
    if cell >= 12 then
        show_weekday = true
        wd_w = Screen:scaleBySize(18)
        cell = cellByWidth()   -- 留出星期标签宽度后重算
    end
    local cap = math.min(CELL_MAX, cellByHeight())
    if cell > cap then cell = cap end
    if cell < 4  then cell = 4  end

    local grid_w = cell * cols + GAP * (cols - 1)

    -- ---- 标题行 ----
    local title_str = _("阅读热力图")
    local range_str = string.format(_("%s ~ %s"), fmtDate(start_ts), fmtDate(end_ts - SECS_DAY))
    local span_str  = string.format(_("近%d周"), weeks)
    if row_blocks > 1 then
        span_str = span_str .. string.format(_("（%d行）"), row_blocks)
    end

    local prev_btn = Button:new {
        text = "◀", bordersize = 0, text_font_face = "cfont",
        text_font_size = 12, text_font_bold = true, padding = NAV_BTN_PAD,
        callback = function() self_ref:_prev() end,
    }
    local next_btn = Button:new {
        text = "▶", bordersize = 0, text_font_face = "cfont",
        text_font_size = 12, text_font_bold = true, padding = NAV_BTN_PAD,
        callback = function() self_ref:_next() end,
    }

    local title_row = HorizontalGroup:new {
        align = "center",
        TextWidget:new { text = title_str, face = face_title, fgcolor = BLACK },
        HorizontalSpan:new { width = Screen:scaleBySize(8) },
        prev_btn,
        next_btn,
    }
    local title_cc = CenterContainer:new {
        dimen = Geom:new { w = inner_w, h = Screen:scaleBySize(26) },
        title_row,
    }

    local range_row = CenterContainer:new {
        dimen = Geom:new { w = inner_w, h = Screen:scaleBySize(18) },
        TextWidget:new {
            text = range_str .. "  ·  " .. span_str,
            face = face_sub, fgcolor = BLACK,
        },
    }

    -- 注意：HorizontalGroup 的 align 是「垂直」对齐，只认 center/top/bottom。
    -- 传 "left" 会让它走 invalid alignment 分支 —— 直接什么都不画（只往 stderr 写警告）。
    local WEEKDAY_LABELS = { _("一"), "", _("三"), "", _("五"), "", "" }
    local BLOCK_MONTH_GAP = Screen:scaleBySize(4)

    -- 第 b 行块的月份标签行
    local prev_block_last_label = nil   -- 上一行末尾显示的月份标签（用于跨行去重）
    local function buildMonthLabels(b)
        local row = HorizontalGroup:new { align = "top" }
        local col_w = cell + GAP
        local last_month = nil
        local last_label_col = -99
        local block_last_label = nil
        for c = 0, cols - 1 do
            local w = b * cols + c
            local d = (w < weeks) and day_list[w * 7 + 1] or nil
            local label = nil
            if d then
                local ok_t, t = pcall(os.date, "*t", d.ts)
                if ok_t and type(t) == "table" and t.month ~= last_month then
                    last_month = t.month
                    -- 至少隔 2 列，避免标签互相压住
                    if (c - last_label_col) >= 2 then
                        label = tostring(t.month) .. _("月")
                        last_label_col = c
                    end
                end
            end
            -- 跨行衔接处：若本行首个标签与上一行末尾相同（如都是「3月」），跳过避免重复
            if label and b > 0 and block_last_label == nil and label == prev_block_last_label then
                label = nil
            end
            if label then
                block_last_label = label
                row[#row + 1] = LeftContainer:new {
                    dimen = Geom:new { w = col_w, h = MONTH_H },
                    TextWidget:new { text = label, face = face_tiny, fgcolor = BLACK },
                }
            else
                row[#row + 1] = HorizontalSpan:new { width = col_w }
            end
        end
        prev_block_last_label = block_last_label
        return row
    end

    local function buildWeekdayCell(r)
        local txt = WEEKDAY_LABELS[r + 1] or ""
        if txt ~= "" then
            return LeftContainer:new {
                dimen = Geom:new { w = wd_w, h = cell },
                TextWidget:new { text = txt, face = face_tiny, fgcolor = BLACK },
            }
        end
        return HorizontalSpan:new { width = wd_w }
    end

    -- ---- 网格：row_blocks 个「月份标签 + 7 行」块，纵向堆叠 ----
    local grid_blocks = VerticalGroup:new { align = "left" }
    for b = 0, row_blocks - 1 do
        local month_row = HorizontalGroup:new { align = "top" }
        if show_weekday then
            month_row[#month_row + 1] = HorizontalSpan:new { width = wd_w }
        end
        month_row[#month_row + 1] = buildMonthLabels(b)
        grid_blocks[#grid_blocks + 1] = month_row
        grid_blocks[#grid_blocks + 1] = VerticalSpan:new { width = BLOCK_MONTH_GAP }

        for r = 0, 6 do
            local row = HorizontalGroup:new { align = "top" }
            if show_weekday then
                row[#row + 1] = buildWeekdayCell(r)
            end
            for c = 0, cols - 1 do
                local w = b * cols + c
                if w < weeks then
                    local d = day_list[w * 7 + r + 1]
                    local level = (d and d.level) or 0
                    local bg, border, bw
                    if d and d.future then
                        bg, border, bw = WHITE, nil, 0    -- 未来日期留白，不画边框
                    else
                        bg     = (level > 0) and (HM_FILL[level] or HM_FILL[4]) or WHITE
                        border, bw = HM_BORDER, CELL_BW
                    end
                    row[#row + 1] = colorBox(cell, cell, bg, CELL_R, border, bw)
                else
                    -- 末行可能不满 26 列，占位对齐
                    row[#row + 1] = HorizontalSpan:new { width = cell }
                end
                if c < cols - 1 then
                    row[#row + 1] = HorizontalSpan:new { width = GAP }
                end
            end
            grid_blocks[#grid_blocks + 1] = row
            if r < 6 then
                grid_blocks[#grid_blocks + 1] = VerticalSpan:new { width = GAP }
            end
        end
        if b < row_blocks - 1 then
            grid_blocks[#grid_blocks + 1] = VerticalSpan:new { width = SECTION_GAP }
        end
    end

    -- 高度直接算，不依赖 group:getSize()（它在某些机型上还没布局就返回 0，
    -- 会把 CenterContainer 裁成 0 高 → 整块网格不可见）
    local block_h = MONTH_H + BLOCK_MONTH_GAP + cell * 7 + GAP * 6
    local grid_h  = row_blocks * block_h + (row_blocks - 1) * SECTION_GAP
    local gs = grid_blocks:getSize()
    logger.warn(string.format(
        "HEATMAP[diag]: weeks=%d blocks=%d cols=%d offset=%d range=%s~%s active_days=%d "
        .. "cell=%d wd=%s grid_w=%d grid_h=%d getSize_h=%s border=%s fill1=%s",
        weeks, row_blocks, cols, offset, fmtDate(start_ts), fmtDate(end_ts - SECS_DAY),
        active_days, cell, tostring(show_weekday), grid_w, grid_h,
        tostring(gs and gs.h), tostring(HM_BORDER), tostring(HM_FILL[1])))

    local grid_cc = CenterContainer:new {
        dimen = Geom:new { w = inner_w, h = grid_h },
        grid_blocks,
    }

    -- ---- 图例 ----
    local legend = HorizontalGroup:new { align = "center" }
    legend[#legend + 1] = TextWidget:new { text = _("少"), face = face_tiny, fgcolor = BLACK }
    legend[#legend + 1] = HorizontalSpan:new { width = Screen:scaleBySize(4) }
    for lvl = 0, 4 do
        local bg = (lvl > 0) and (HM_FILL[lvl] or HM_FILL[4]) or WHITE
        legend[#legend + 1] = colorBox(Screen:scaleBySize(12), Screen:scaleBySize(12),
                                       bg, CELL_R, HM_BORDER, CELL_BW)
        legend[#legend + 1] = HorizontalSpan:new { width = Screen:scaleBySize(2) }
    end
    legend[#legend + 1] = HorizontalSpan:new { width = Screen:scaleBySize(2) }
    legend[#legend + 1] = TextWidget:new { text = _("多"), face = face_tiny, fgcolor = BLACK }

    -- ---- 汇总 ----
    local summary_str = string.format(_("阅读 %d 天 · 合计 %s · 单日最长 %s"),
        active_days, fmtDuration(total_secs), fmtDuration(max_day))

    local content = VerticalGroup:new {
        align = "center",
        title_cc,
        VerticalSpan:new { width = Screen:scaleBySize(2) },
        range_row,
        VerticalSpan:new { width = SECTION_GAP },
        grid_cc,
        VerticalSpan:new { width = SECTION_GAP },
        CenterContainer:new {
            dimen = Geom:new { w = inner_w, h = Screen:scaleBySize(16) },
            legend,
        },
        VerticalSpan:new { width = Screen:scaleBySize(6) },
        CenterContainer:new {
            dimen = Geom:new { w = inner_w, h = Screen:scaleBySize(18) },
            TextWidget:new { text = summary_str, face = face_sub, fgcolor = BLACK },
        },
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

function HeatmapWindow:onTap() UIManager:close(self) end
function HeatmapWindow:onSwipe(_a, _g) self:onClose() end
function HeatmapWindow:onClose() UIManager:close(self); return true end
HeatmapWindow.onAnyKeyPressed = HeatmapWindow.onClose
HeatmapWindow.onMultiSwipe    = HeatmapWindow.onClose

function HeatmapWindow:onShow()
    local d = _frameDimen(self)
    if d then
        UIManager:setDirty(self, function() return "ui", d end)
    else
        UIManager:setDirty(self, "ui")
    end
    return true
end

function HeatmapWindow:onCloseWidget()
    local d = _frameDimen(self) or Screen:getSize()
    if d then
        UIManager:setDirty(nil, function() return "ui", d end)
    end
end

local function showHeatmap()
    local ok, err = pcall(function()
        UIManager:show(HeatmapWindow:new {}, "ui")
    end)
    if not ok then
        logger.err("READINGSTATS: showHeatmap failed: " .. tostring(err))
        pcall(function()
            local Notification = require("ui/widget/notification")
            Notification:notify(_("阅读热力图") .. "：" .. _("执行失败"))
        end)
    end
end

-- ============================================================
-- 设置项：热力图跨度 26 / 52 周
-- ============================================================

local heatmap_settings_menu = {
    text_func = function()
        return string.format(_("热力图跨度（%d周）"), HM_SETT.weeks or 26)
    end,
    help_text = _("热力图显示的时间跨度。\n26 周约半年，单行铺满屏幕；\n52 周为整年，拆成上下两行、每行 26 周，格子大小与 26 周一致。"),
    sub_item_table = {
        {
            text = _("26 周（半年）"),
            checked_func = function() return (HM_SETT.weeks or 26) == 26 end,
            callback = function() HM_SETT.weeks = 26; saveSett() end,
        },
        {
            text = _("52 周（整年）"),
            checked_func = function() return (HM_SETT.weeks or 26) == 52 end,
            callback = function() HM_SETT.weeks = 52; saveSett() end,
        },
    },
}

local _M = {}
_M.show = showHeatmap
_M.settings_menu = heatmap_settings_menu
-- 供离线单元测试使用（不参与菜单与渲染）
_M._test = {
    periodRange   = periodRange,
    computeLevels = computeLevels,
    mondayIndex   = mondayIndex,
    midnight      = midnight,
}
return _M
