local refreshOnlyOncePerDay = true

local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
local ButtonDialog = require("frontend/ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local logger = require("logger")
local ReaderUI = require("apps/reader/readerui")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local SQ3 = require("lua-ljsqlite3/init")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local Screen = Device.screen
local gettext = require("gettext")
local T = require("ffi/util").template
local util = require("util")

-- 虚线分隔线
local function createDashedSeparator(width)
    local dash_len = 12
    local gap_len = 7
    local line_height = 2
    local segments = {}
    local x = 0
    while x < width do
        local seg_w = math.min(dash_len, width - x)
        table.insert(segments, LineWidget:new{
            dimen = Geom:new{ w = seg_w, h = line_height },
            style = "solid",
            color = Blitbuffer.COLOR_BLACK,
        })
        x = x + seg_w
        if x >= width then break end
        local gap_w = math.min(gap_len, width - x)
        if gap_w > 0 then
            table.insert(segments, HorizontalSpan:new{ width = gap_w })
            x = x + gap_w
        end
    end
    return HorizontalGroup:new(segments)
end

-- 本地化表（完整，不变）
local PATCH_L10N = {
    en = {
        ["Jan"] = "Jan", ["Feb"] = "Feb", ["Mar"] = "Mar", ["Apr"] = "Apr",
        ["May"] = "May", ["Jun"] = "Jun", ["Jul"] = "Jul", ["Aug"] = "Aug",
        ["Sep"] = "Sep", ["Oct"] = "Oct", ["Nov"] = "Nov", ["Dec"] = "Dec",
        ["January"] = "January", ["February"] = "February", ["March"] = "March",
        ["April"] = "April", ["June"] = "June", ["July"] = "July", ["August"] = "August",
        ["September"] = "September", ["October"] = "October", ["November"] = "November",
        ["December"] = "December",
        ["second read"] = "second read", ["seconds read"] = "seconds read",
        ["minute read"] = "minute read", ["minutes read"] = "minutes read",
        ["hour read"] = "hour read", ["hours read"] = "hours read",
        ["book"] = "book", ["books"] = "books",
        ["day"] = "day", ["days"] = "days",
        ["daily record"] = "daily record",
        ["day read"] = "day read", ["days read"] = "days read",
        ["page read"] = "page read", ["pages read"] = "pages read",
        ["week"] = "week", ["weeks"] = "weeks",
        ["weekly record"] = "weekly record",
        ["week in a row"] = "week in a row", ["weeks in a row"] = "weeks in a row",
        ["day in a row"] = "day in a row", ["days in a row"] = "days in a row",
        ["page"] = "page", ["pages"] = "pages",
        ["TODAY"] = "TODAY",
        ["No weekly streak"] = "No weekly streak", ["No daily streak"] = "No daily streak",
        ["CURRENT STREAK"] = "CURRENT STREAK", ["BEST STREAK"] = "BEST STREAK",
        ["DAYS READ PER MONTH"] = "DAYS READ PER MONTH",
        ["HOURS READ PER MONTH"] = "HOURS READ PER MONTH",
        ["Reading statistics: reading insights"] = "Reading statistics: reading insights",
        ["Unknown"] = "Unknown",
        ["No books read"] = "No books read",
        ["No books read in %1"] = "No books read in %1",
        ["No books read in "] = "No books read in ",
        ["%1 - Book Read (%2)"] = "%1 - Book Read (%2)",
        ["%1 - Books Read (%2)"] = "%1 - Books Read (%2)",
        ["Check for new stats"] = "Check for new stats",
        ["Force reload streaks"] = "Force reload streaks",
        ["Force reload "] = "Force reload ",
        [" insights"] = " insights",
        ["Reload streaks?"] = "Reload streaks?",
        ["Reload"] = "Reload",
        ["Cancel"] = "Cancel",
        ["Reload %1 insights?"] = "Reload %1 insights?",
        ["Reload all insights?"] = "Reload all insights?",
        ["hour"] = "hour", ["minute"] = "min",
        ["Total"] = "Total",
        ["Page count:"] = "Page count:",
        ["Duration:"] = "Duration:",
        ["Total pages:"] = "Total pages:",
        ["Total duration:"] = "Total duration:",
    },
    zh = {
        ["Jan"] = "1月", ["Feb"] = "2月", ["Mar"] = "3月", ["Apr"] = "4月",
        ["May"] = "5月", ["Jun"] = "6月", ["Jul"] = "7月", ["Aug"] = "8月",
        ["Sep"] = "9月", ["Oct"] = "10月", ["Nov"] = "11月", ["Dec"] = "12月",
        ["January"] = "一月", ["February"] = "二月", ["March"] = "三月",
        ["April"] = "四月", ["June"] = "六月", ["July"] = "七月", ["August"] = "八月",
        ["September"] = "九月", ["October"] = "十月", ["November"] = "十一月",
        ["December"] = "十二月",
        ["second read"] = "秒阅读", ["seconds read"] = "秒阅读",
        ["minute read"] = "分钟阅读", ["minutes read"] = "分钟阅读",
        ["hour read"] = "小时阅读", ["hours read"] = "小时阅读",
        ["book"] = "本书", ["books"] = "本书",
        ["day"] = "天", ["days"] = "天",
        ["daily record"] = "天连读记录",
        ["day read"] = "天阅读", ["days read"] = "天阅读",
        ["page read"] = "页阅读", ["pages read"] = "页阅读",
        ["week"] = "周", ["weeks"] = "周",
        ["weekly record"] = "周连读记录",
        ["week in a row"] = "连续周", ["weeks in a row"] = "连续周",
        ["day in a row"] = "连续天", ["days in a row"] = "连续天",
        ["page"] = "页", ["pages"] = "页",
        ["TODAY"] = "今天",
        ["No weekly streak"] = "无周连读", ["No daily streak"] = "无天连读",
        ["CURRENT STREAK"] = "当前连读", ["BEST STREAK"] = "最佳连读",
        ["DAYS READ PER MONTH"] = "每月阅读天数",
        ["HOURS READ PER MONTH"] = "每月阅读时长",
        ["Reading statistics: reading insights"] = "阅读统计：阅读分析",
        ["Unknown"] = "未知",
        ["No books read"] = "未读书籍",
        ["No books read in %1"] = "在 %1 无阅读书籍",
        ["No books read in "] = "未读书籍于 ",
        ["%1 - Book Read (%2)"] = "%1 - 已读 %2 本书",
        ["%1 - Books Read (%2)"] = "%1 - 已读 %2 本书",
        ["Check for new stats"] = "检查新统计数据",
        ["Force reload streaks"] = "强制刷新连读记录",
        ["Force reload "] = "强制刷新 ",
        [" insights"] = " 分析数据",
        ["Reload streaks?"] = "刷新连读记录？",
        ["Reload"] = "刷新",
        ["Cancel"] = "取消",
        ["Reload %1 insights?"] = "刷新 %1 年的分析？",
        ["Reload all insights?"] = "刷新所有分析数据？",
        ["Force reload all insights"] = "强制刷新所有分析数据",
        ["hour"] = "小时", ["minute"] = "分钟",
        ["Total"] = "总",
        ["Page count:"] = "页数：",
        ["Duration:"] = "时长：",
        ["Total pages:"] = "总页数：",
        ["Total duration:"] = "总时长：",
    },
    vi = {
        ["Jan"] = "Th1", ["Feb"] = "Th2", ["Mar"] = "Th3", ["Apr"] = "Th4",
        ["May"] = "Th5", ["Jun"] = "Th6", ["Jul"] = "Th7", ["Aug"] = "Th8",
        ["Sep"] = "Th9", ["Oct"] = "Th10", ["Nov"] = "Th11", ["Dec"] = "Th12",
        ["January"] = "Tháng 1", ["February"] = "Tháng 2", ["March"] = "Tháng 3",
        ["April"] = "Tháng 4", ["June"] = "Tháng 6", ["July"] = "Tháng 7", ["August"] = "Tháng 8",
        ["September"] = "Tháng 9", ["October"] = "Tháng 10", ["November"] = "Tháng 11",
        ["December"] = "Tháng 12",
        ["second read"] = "giây đã đọc", ["seconds read"] = "giây đã đọc",
        ["minute read"] = "phút đã đọc", ["minutes read"] = "phút đã đọc",
        ["hour read"] = "giờ đã đọc", ["hours read"] = "giờ đã đọc",
        ["book"] = "book", ["books"] = "books",
        ["day"] = "day", ["days"] = "days",
        ["daily record"] = "daily record",
        ["day read"] = "ngày đã đọc", ["days read"] = "ngày đã đọc",
        ["page read"] = "trang đã đọc", ["pages read"] = "trang đã đọc",
        ["week"] = "week", ["weeks"] = "weeks",
        ["weekly record"] = "weekly record",
        ["week in a row"] = "tuần liên tiếp", ["weeks in a row"] = "tuần liên tiếp",
        ["day in a row"] = "ngày liên tiếp", ["days in a row"] = "ngày liên tiếp",
        ["page"] = "trang", ["pages"] = "trang",
        ["TODAY"] = "HÔM NAY",
        ["No weekly streak"] = "Không có chuỗi tuần liên tiếp",
        ["No daily streak"] = "Không có chuỗi ngày liên tiếp",
        ["CURRENT STREAK"] = "CHUỖI LIÊN TIẾP HIỆN TẠI",
        ["BEST STREAK"] = "CHUỖI LIÊN TIẾP DÀI NHẤT",
        ["DAYS READ PER MONTH"] = "SỐ NGÀY ĐỌC MỖI THÁNG",
        ["HOURS READ PER MONTH"] = "SỐ GIỜ ĐỌC MỖI THÁNG",
        ["Reading statistics: reading insights"] = "Thống kê đọc: phân tích",
        ["Unknown"] = "Không rõ",
        ["No books read"] = "Chưa đọc sách nào",
        ["No books read in %1"] = "Không đọc sách nào trong %1",
        ["No books read in "] = "Không đọc sách nào trong ",
        ["%1 - Book Read (%2)"] = "%1 - Sách đã đọc (%2)",
        ["%1 - Books Read (%2)"] = "%1 - Sách đã đọc (%2)",
        ["hour"] = "giờ", ["minute"] = "phút",
        ["Total"] = "Tổng",
        ["Page count:"] = "Số trang:",
        ["Duration:"] = "Thời lượng:",
        ["Total pages:"] = "Tổng số trang:",
        ["Total duration:"] = "Tổng thời lượng:",
    },
}

local function l10nLookup(msg)
    local lang = "en"
    if G_reader_settings and G_reader_settings.readSetting then
        lang = G_reader_settings:readSetting("language") or "en"
    end
    local lang_base = lang:match("^([a-z]+)") or lang
    local map = PATCH_L10N[lang] or PATCH_L10N[lang_base] or PATCH_L10N.en or {}
    return map[msg]
end

local function _(msg)
    return l10nLookup(msg) or gettext(msg)
end

local function N_(singular, plural, n)
    local singular_override = l10nLookup(singular)
    local plural_override = l10nLookup(plural)
    if singular_override or plural_override then
        if n == 1 then
            return singular_override or plural_override
        end
        return plural_override or singular_override
    end
    return gettext.ngettext(singular, plural, n)
end

local function formatCount(value)
    if value == nil then return "" end
    return util.getFormattedSize(value)
end

local function formatNumber(value)
    if value == nil then return "" end
    if type(value) == "number" and value % 1 ~= 0 then
        return string.format("%.1f", value)
    end
    return formatCount(value)
end

local MONTH_NAMES_SHORT = {
    _("Jan"), _("Feb"), _("Mar"), _("Apr"), _("May"), _("Jun"),
    _("Jul"), _("Aug"), _("Sep"), _("Oct"), _("Nov"), _("Dec"),
}
local MONTH_NAMES_FULL = {
    _("January"), _("February"), _("March"), _("April"), _("June"), _("July"),
    _("August"), _("September"), _("October"), _("November"), _("December"),
}

local db_path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
local ReadingInsightsPopup

local INSIGHTS_MODE_KEY = "reading_insights_popup_mode"
local INSIGHTS_MODE_DAYS = "days"
local INSIGHTS_MODE_HOURS = "hours"

local function normalizeInsightsMode(mode)
    if mode == INSIGHTS_MODE_HOURS then
        return INSIGHTS_MODE_HOURS
    end
    return INSIGHTS_MODE_DAYS
end

local function readInsightsMode()
    if G_reader_settings and G_reader_settings.readSetting then
        return normalizeInsightsMode(G_reader_settings:readSetting(INSIGHTS_MODE_KEY, INSIGHTS_MODE_DAYS))
    end
    return INSIGHTS_MODE_DAYS
end

local function saveInsightsMode(mode)
    if G_reader_settings and G_reader_settings.saveSetting then
        G_reader_settings:saveSetting(INSIGHTS_MODE_KEY, mode)
    end
end

--CACHE
local insightsCache = G_reader_settings:readSetting("readingInsights_cache") or {
    streaks = nil,
    yearRange = nil,
    yearlyStats = nil,
    monthlyReadingDays = nil,
    monthlyReadingHours = nil,
}
local cache_timestamps = G_reader_settings:readSetting("readingInsights_cacheTimestamps") or {
    partialClear = 1262304000,
    fullClear = 1262304000,
    statsSynced = 1262304000,
    lastRefreshed = 1262304000,
}
local cachedLayout = nil

local function uploadCacheTimestampsTogreader()
    G_reader_settings:saveSetting("readingInsights_cacheTimestamps", cache_timestamps)
end
local function uploadInsightsCacheToGReader(item)
    logger.info("READING-INSIGHTS-POPUP: UPLOADING CACHE: ", item)
    G_reader_settings:saveSetting("readingInsights_cache", insightsCache)
end
local function set_cache_partialClear_timestamp(timestamp)
    cache_timestamps.partialClear = timestamp
    uploadCacheTimestampsTogreader()
end
local function set_cache_fullClear_timestamp(timestamp)
    cache_timestamps.fullClear = timestamp
    uploadCacheTimestampsTogreader()
end
local function getDbModTime()
    local lfs = require("libs/libkoreader-lfs")
    local attr = lfs.attributes(db_path, "modification")
    return attr and attr or 0
end

local function clearCache(year)
    if year then
        logger.info("READING-INSIGHTS-POPUP: ERASING CACHE FOR YEAR", year)
        insightsCache.streaks = nil
        insightsCache.yearRange = nil
        insightsCache.yearlyStats = insightsCache.yearlyStats or {}
        insightsCache.yearlyStats[year] = nil
        insightsCache.monthlyReadingDays = insightsCache.monthlyReadingDays or {}
        insightsCache.monthlyReadingDays[year] = nil
        insightsCache.monthlyReadingHours = insightsCache.monthlyReadingHours or {}
        insightsCache.monthlyReadingHours[year] = nil
    else
        logger.info("READING-INSIGHTS-POPUP: ERASING ALL CACHED DATA")
        insightsCache = {}
    end
    uploadInsightsCacheToGReader("clearCache")
end

local function clearCacheIfRequired()
    local ts_now = os.time()
    local t = os.date("*t", ts_now)
    t.hour = 0
    t.min = 0
    t.sec = 0
    local ts_midnight_today = os.time(t)

    local latest_db_mod_timestamp = getDbModTime()

    if refreshOnlyOncePerDay and (cache_timestamps.lastRefreshed > ts_midnight_today) then return end

    if cache_timestamps.statsSynced > cache_timestamps.fullClear then
        set_cache_fullClear_timestamp(cache_timestamps.statsSynced)
        set_cache_partialClear_timestamp(latest_db_mod_timestamp)
        cache_timestamps.lastRefreshed = ts_now
        return clearCache()
    end

    if latest_db_mod_timestamp > cache_timestamps.partialClear then
        for i = tonumber(os.date("%Y", cache_timestamps.partialClear)), tonumber(os.date("%Y", latest_db_mod_timestamp)) do
            clearCache(i)
        end
        cache_timestamps.lastRefreshed = ts_now
        return set_cache_partialClear_timestamp(latest_db_mod_timestamp)
    end

    if latest_db_mod_timestamp < (ts_midnight_today - 86400) and
        insightsCache.streaks and
        insightsCache.streaks.current_days and
        insightsCache.streaks.current_days ~= 0 then
        logger.info("READING-INSIGHTS-POPUP: CLEARING CACHED STREAKS")
        insightsCache.streaks = nil
        uploadInsightsCacheToGReader("clearCacheIfRequired")
    end
end

--FALLBACK ARRAY
local fallback_monthlyData = {}
for month_num = 1, 12 do
    table.insert(fallback_monthlyData, {
        month = "--",
        days = 0,
        hours = 0,
        label = MONTH_NAMES_SHORT[month_num],
        label_full = MONTH_NAMES_FULL[month_num],
    })
end
local fallbackTable = {
    streaks = {
        days = { current = 0, best = 0, best_start = 1, best_end = 1 },
        weeks = { current = 0, best = 0, best_start = 1, best_end = 1 },
    },
    yearRange = { min_year = 0, max_year = 0 },
    yearlyStats = { days = 0, pages = 0, duration = 0 },
    monthlyReadingDays = fallback_monthlyData,
    monthlyReadingHours = fallback_monthlyData,
    isPlaceholder = true
}

local function withStatsDb(fallback, fn)
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(db_path, "mode") ~= "file" then
        return fallback
    end

    local conn = SQ3.open(db_path)
    if not conn then return fallback end

    local ok, result = pcall(fn, conn)
    conn:close()
    if ok then
        return result
    end
    return fallback
end

local function withStatement(conn, sql, fn)
    local stmt = conn:prepare(sql)
    if not stmt then return end
    local ok, result = pcall(fn, stmt)
    stmt:close()
    if ok then
        return result
    end
end

local function computeStreaks(entries_desc, is_consecutive, is_current_start, weeksOrDays)
    local a = {
        current = 0,
        best = 0,
        best_start = 0,
        best_end = 0,
    }
    if #entries_desc == 0 then
        return a
    elseif #entries_desc == 1 then
        a.best = 1
        if is_current_start(entries_desc[1][1]) then
            a.current = 1
        end
        return a
    end
    a = nil

    local current = 0
    if is_current_start(entries_desc[1][1]) then
        current = 1
        for i = 2, #entries_desc do
            if is_consecutive(entries_desc[i - 1][1], entries_desc[i][1]) then
                current = current + 1
            else
                break
            end
        end
    end

    local best = 1
    local run = 1
    local best_start = 0
    local best_end = 0
    local best_end_temp = 0
    for i = 2, #entries_desc do
        if is_consecutive(entries_desc[i - 1][1], entries_desc[i][1]) then
            if run == 1 then best_end_temp = (i - 1) end
            run = run + 1
            if run > best then
                best = run
                best_start = i
                best_end = best_end_temp
            end
        else
            run = 1
        end
    end

    if weeksOrDays == 1 then -- days
        best_start = tonumber(entries_desc[best_start][2])
        best_end = tonumber(entries_desc[best_end][2])
    else
        best_start = tonumber(entries_desc[best_start][1])
        best_end = tonumber(entries_desc[best_end][2])
    end

    return {
        current = current,
        best = best,
        best_start = best_start,
        best_end = best_end,
    }
end

local function parseDateYMD(date_str)
    if not date_str then return end
    local year = tonumber(date_str:sub(1,4))
    local month = tonumber(date_str:sub(6,7))
    local day = tonumber(date_str:sub(9,10))
    if not year or not month or not day then return end
    return year, month, day
end

local function parseWeekYear(week_stamp)
    if not week_stamp then return end
    return os.date("%G-%V", week_stamp)
end

local function formatHoursRead(seconds)
    if (not seconds) or (seconds < 60) then
        return 0, _("hours read")
    end

    local h = math.floor(seconds / 3600)
    local h_unit = N_("hour read", "hours read", h)

    if h == 0 then
        h = math.floor((seconds / 3600) * 10) / 10
        return h, _("hours read")
    end

    return h, h_unit
end

local function buildSerifFonts()
    return {
        section = Font:getFace("NotoSans-Regular.ttf", 22),
        value = Font:getFace("NotoSans-Bold.ttf", 32),
        label = Font:getFace("NotoSans-Regular.ttf", 20),
        small = Font:getFace("NotoSans-Regular.ttf", 18),
        streakValue = Font:getFace("NotoSans-Bold.ttf", 57),
        streakLabel = Font:getFace("NotoSans-Regular.ttf", 17),
        streaRecordValue = Font:getFace("NotoSans-Bold.ttf", 22),
        streakStartEndWidget = Font:getFace("NotoSans-Regular.ttf", 10),
        author = Font:getFace("NotoSans-Regular.ttf", 14),
        titleLine1 = Font:getFace("NotoSans-Regular.ttf", 25),
        titleLine2 = Font:getFace("NotoSans-Regular.ttf", 14),
    }
end

local function buildLayout(max_widget_width, padding_h, column_gap)
    local content_width = max_widget_width - 2 * padding_h
    local col_width = math.floor((max_widget_width - Size.line.medium) / 2 ) - Screen:scaleBySize(2)
    local a = {
        full_width = max_widget_width,
        padding_h = padding_h,
        column_gap = column_gap,
        content_width = content_width,
        col_width = col_width,
    }
    cachedLayout = a
    return a
end

local function buildColumnSeparator(height)
    local v_padding = Size.padding.default
    return VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ height = v_padding },
        LineWidget:new{
            dimen = Geom:new{ w = Size.line.medium, h = height - 2 * v_padding },
            background = Blitbuffer.COLOR_GRAY,
        },
        VerticalSpan:new{ height = v_padding },
    }
end

local function buildValueLine(font_value, font_label, column_gap, value, unit)
    return HorizontalGroup:new{
        HorizontalSpan:new{ width = column_gap },
        TextWidget:new{ text = value, face = font_value },
        HorizontalSpan:new{ width = Size.padding.large },
        TextWidget:new{ text = unit, face = font_label },
    }
end

-- 主界面年份模块（不变）
local function buildYearHeader(popup_self, font_section, layout, yearRange)
    local selected_year = popup_self.selected_year
    local prev_enabled = selected_year > yearRange.min_year
    local next_enabled = selected_year < yearRange.max_year

    local sample_nav = TextWidget:new{ text = "0000", face = font_section }
    local icon_width = Screen:scaleBySize(15)
    local nav_width = sample_nav:getSize().w + icon_width
    sample_nav:free()

    -- ⚠️ 两个 dialog 必须在这里一起声明（下面 hold_buttons / tap_buttons 的闭包要引用它们）。
    -- 少声明一个就会变成全局变量，多实例时会「关错对话框」。
    local year_button_tap_dialog, year_button_hold_dialog
    local tap_buttons = {}
    local yearCount = popup_self.yearRange.max_year - popup_self.yearRange.min_year
    if yearCount >= 1 then
        for i = popup_self.yearRange.min_year, popup_self.yearRange.max_year do
            local a = {
                text = i,
                callback = function()
                    UIManager:close(year_button_tap_dialog)
                    popup_self:onGoToPrevYear(popup_self, i)
                end,
            }
            table.insert(tap_buttons, {a})
        end
    end

    year_button_tap_dialog = ButtonDialog:new{
        shrink_unneeded_width = true,
        modal = true,
        buttons = tap_buttons
    }
    year_button_tap_dialog.onCloseWidget = function(self)
        UIManager:setDirty(nil, function()
            return "ui", self.movable.dimen
        end)
    end

    local hold_buttons = {
        {{
            text = _("Check for new stats"),
            align = "left",
            callback = function()
                UIManager:close(year_button_hold_dialog)
                local orig_refreshOnlyOncePerDay = refreshOnlyOncePerDay
                refreshOnlyOncePerDay = false
                clearCacheIfRequired()
                refreshOnlyOncePerDay = orig_refreshOnlyOncePerDay
                popup_self:onGoToPrevYear(popup_self, popup_self.selected_year)
                return true
            end,
        }},
        {{
            text = _("Force reload streaks"),
            align = "left",
            callback = function()
                local confirm = ConfirmBox:new{
                    text = _("Reload streaks?"),
                    ok_text = _("Reload"),
                    cancel_text = _("Cancel"),
                    ok_callback = function()
                        UIManager:close(year_button_hold_dialog)
                        insightsCache.streaks = nil
                        uploadInsightsCacheToGReader("force reload streaks")
                        popup_self:onGoToPrevYear(popup_self, popup_self.selected_year)
                    end,
                }
                return UIManager:show(confirm)
            end,
        }},
        {{
            text = _("Force reload ") .. popup_self.selected_year .. _(" insights"),
            align = "left",
            callback = function()
                local confirm = ConfirmBox:new{
                    text = T(_("Reload %1 insights?"), popup_self.selected_year),
                    ok_text = _("Reload"),
                    cancel_text = _("Cancel"),
                    ok_callback = function()
                        UIManager:close(year_button_hold_dialog)
                        clearCache(popup_self.selected_year)
                        popup_self:onGoToPrevYear(popup_self, popup_self.selected_year)
                    end,
                }
                return UIManager:show(confirm)
            end,
        }},
        {{
            text = _("Force reload all insights"),
            align = "left",
            callback = function()
                local confirm = ConfirmBox:new{
                    text = _("Reload all insights?"),
                    ok_text = _("Reload"),
                    cancel_text = _("Cancel"),
                    ok_callback = function()
                        UIManager:close(year_button_hold_dialog)
                        clearCache()
                        popup_self:onGoToPrevYear(popup_self, popup_self.selected_year)
                    end,
                }
                return UIManager:show(confirm)
            end,
        }},
    }

    year_button_hold_dialog = ButtonDialog:new{
        shrink_unneeded_width = true,
        modal = true,
        buttons = hold_buttons
    }
    year_button_hold_dialog.onCloseWidget = function(self)
        UIManager:setDirty(nil, function()
            return "ui", self.movable.dimen
        end)
    end

    local year_label = TextWidget:new{
        text = tostring(selected_year),
        face = font_section,
    }
    year_label = HorizontalGroup:new{
        HorizontalSpan:new{ width = Size.padding.large },
        year_label,
        HorizontalSpan:new{ width = Size.padding.large },
    }
    year_label = FrameContainer:new{
        bordersize = Screen:scaleBySize(1),
        color = Blitbuffer.COLOR_GRAY_E,
        radius = Screen:scaleBySize(7),
        margin = 0,
        padding = 0,
        focusable = true,
        focus_border_size = Screen:scaleBySize(1),
        focus_border_color = Blitbuffer.COLOR_BLACK,
        year_label,
    }
    local year_dimen = year_label:getSize()
    local tappable_year_label = InputContainer:new{
        dimen = Geom:new{ w = year_dimen.w, h = year_dimen.h },
        year_label,
        focusable = true,
    }
    tappable_year_label.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = function() return tappable_year_label.dimen end,
            }
        },
        Hold = {
            GestureRange:new{
                ges = "hold",
                range = function() return tappable_year_label.dimen end,
            }
        },
    }
    function tappable_year_label:onTap()
        if yearCount >= 1 then
            UIManager:show(year_button_tap_dialog, "ui")
        end
        return true
    end
    function tappable_year_label:onHold()
        UIManager:show(year_button_hold_dialog)
    end

    table.insert(popup_self.layout, 1, {tappable_year_label})

    local function navButton(text, _, prevOrNext)
        local btn = Button:new{
            text = text,
            bordersize = 0,
            padding = 0,
            margin = 0,
            background = Blitbuffer.COLOR_GRAY_E,
            text_font_face = font_section.orig_font,
            text_font_size = font_section.orig_size,
            text_font_bold = false,
            focusable = true,
            callback = function()
                if prevOrNext == 0 then
                    popup_self:onGoToPrevYear(popup_self)
                else
                    popup_self:onGoToNextYear(popup_self)
                end
            end,
        }
        local left_icon = function() return IconWidget:new{ icon = "chevron.left", width = icon_width, alpha = true, is_icon = true } end
        local right_icon = function() return IconWidget:new{ icon = "chevron.right", width = icon_width, alpha = true, is_icon = true } end
        if prevOrNext == 0 then return HorizontalGroup:new{ left_icon(), btn }
        else return HorizontalGroup:new{ btn, right_icon() } end
    end

    local prev_widget = prev_enabled
        and navButton(tostring(selected_year - 1), selected_year - 1, 0)
        or HorizontalSpan:new{ width = nav_width }
    local next_widget = next_enabled
        and navButton(tostring(selected_year + 1), selected_year + 1, 1)
        or HorizontalSpan:new{ width = nav_width }

    local prev_w = prev_enabled and prev_widget:getSize().w or nav_width
    local next_w = next_enabled and next_widget:getSize().w or nav_width
    local remaining = layout.full_width - prev_w - year_dimen.w - next_w - 2 * Size.padding.large - Screen:scaleBySize(2)
    local side_space = math.floor(remaining / 2)

    return FrameContainer:new{
        background = Blitbuffer.COLOR_GRAY_E,
        color = Blitbuffer.COLOR_GRAY_E,
        bordersize = Screen:scaleBySize(1),
        radius = Screen:scaleBySize(7),
        padding = 0,
        padding_bottom = Screen:scaleBySize(2),
        margin = 0,
        HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = Size.padding.large },
            LeftContainer:new{
                dimen = Geom:new{ w = prev_w + side_space, h = year_dimen.h },
                prev_widget,
            },
            tappable_year_label,
            LeftContainer:new{
                dimen = Geom:new{ w = next_w + side_space, h = year_dimen.h },
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = side_space },
                    next_widget,
                },
            },
            HorizontalSpan:new{ width = Size.padding.large },
        },
    }
end

local function buildYearlyRow(popup_self, yearly_stats, fonts, layout)
    local left_value = ""
    local left_unit = ""
    if popup_self.mode == INSIGHTS_MODE_HOURS then
        left_value, left_unit = formatHoursRead(yearly_stats.duration)
    else
        left_value = formatCount(yearly_stats.days)
        left_unit = N_("day read", "days read", yearly_stats.days)
    end
    local left_line = buildValueLine(
        fonts.value,
        fonts.streakLabel,
        layout.column_gap,
        left_value,
        left_unit
    )
    local left_line_dimen = left_line:getSize()
    local pages_val = buildValueLine(
        fonts.value,
        fonts.streakLabel,
        layout.column_gap,
        formatCount(yearly_stats.pages),
        N_("page read", "pages read", yearly_stats.pages)
    )
    local pages_val_dimen = pages_val:getSize()

    local selected_year_for_tap = popup_self.selected_year

    local left_focusable = FrameContainer:new{
        bordersize = Screen:scaleBySize(1),
        radius = Screen:scaleBySize(7),
        color = Blitbuffer.COLOR_WHITE,
        margin = 0,
        padding = 0,
        focusable = true,
        focus_border_size = Screen:scaleBySize(1),
        focus_border_color = Blitbuffer.COLOR_BLACK,
        LeftContainer:new{
            dimen = Geom:new{ w = layout.col_width, h = left_line_dimen.h + 2 },
            left_line,
        }
    }
    local left_focusable_dimen = left_focusable:getSize()
    local left_cell = InputContainer:new{
        dimen = Geom:new{ w = left_focusable_dimen.w, h = left_focusable_dimen.h + 2 },
        left_focusable,
    }
    left_cell.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = function() return left_cell.dimen end,
            }
        },
    }
    function left_cell:onTap()
        popup_self:toggleInsightsMode(popup_self)
        return true
    end

    local right_focusable = FrameContainer:new{
        bordersize = 1,
        radius = Screen:scaleBySize(7),
        color = Blitbuffer.COLOR_WHITE,
        margin = 0,
        padding = 0,
        focusable = true,
        focus_border_size = 1,
        focus_border_color = Blitbuffer.COLOR_BLACK,
        LeftContainer:new{
            dimen = Geom:new{ w = layout.col_width, h = pages_val_dimen.h + 2 },
            pages_val,
        }
    }
    local right_focusable_dimen = right_focusable:getSize()
    local right_cell = InputContainer:new{
        dimen = Geom:new{ w = right_focusable_dimen.w, h = right_focusable:getSize().h + 2 },
        right_focusable,
    }
    right_cell.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = function() return right_cell.dimen end,
            }
        },
    }
    function right_cell:onTap()
        popup_self:showBooksForYear(selected_year_for_tap)
        return true
    end

    local foc_mgr_secondRow = { left_cell, right_cell }
    table.insert(popup_self.layout, foc_mgr_secondRow)

    return FrameContainer:new{
        bordersize = 0,
        padding = 0,
        HorizontalGroup:new{
            left_cell,
            buildColumnSeparator(left_focusable_dimen.h),
            right_cell,
        },
    }
end

-- 修复柱状图焦点索引
local function buildMonthlyChart(popup_self, monthly_data, layout, fonts)
    if #monthly_data == 0 then
        return nil
    end

    local value_key = popup_self.mode == INSIGHTS_MODE_HOURS and "hours" or "days"
    local max_value = 1
    for _, m in ipairs(monthly_data) do
        local v = tonumber(m[value_key]) or 0
        if v > max_value then max_value = v end
    end

    local chart_width = layout.content_width
    local bar_height = tonumber(Screen:scaleBySize(60))
    local bar_width = math.floor(chart_width / 6) - tonumber(Screen:scaleBySize(8))
    local bar_gap = math.floor((chart_width - bar_width * 6) / 5)
    local font_small = fonts.small

    local sample_label = TextWidget:new{ text = "0", face = font_small }
    local label_height = sample_label:getSize().h
    sample_label:free()

    local current_year = tonumber(os.date("%Y"))
    local current_month = os.date("%Y-%m")

    local function createBarRow(data_slice)
        local bars_row = HorizontalGroup:new{ align = "bottom" }
        local month_labels_row = HorizontalGroup:new{ align = "top" }
        local baseline_h = Size.line.medium
        local total_bar_height = bar_height + label_height

        for i, m in ipairs(data_slice) do
            local value = tonumber(m[value_key]) or 0
            local ratio = max_value > 0 and (value / max_value) or 0
            local bar_h = math.floor(ratio * bar_height + 0.5)
            if bar_h == 0 and value > 0 then bar_h = 1 end

            local is_current = (popup_self.selected_year == current_year) and (m.month == current_month)
            local bar_color = is_current and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY

            local value_label = TextWidget:new{
                text = formatNumber(value),
                face = font_small,
            }
            local centered_label = CenterContainer:new{
                dimen = Geom:new{ w = bar_width, h = label_height },
                value_label,
            }

            local bar_column = VerticalGroup:new{ align = "center" }
            table.insert(bar_column, centered_label)
            if bar_h > 0 then
                table.insert(bar_column, LineWidget:new{
                    dimen = Geom:new{ w = bar_width, h = bar_h },
                    background = bar_color,
                })
            end
            table.insert(bar_column, LineWidget:new{
                dimen = Geom:new{ w = bar_width, h = baseline_h },
                background = bar_color,
            })

            local bar_container = BottomContainer:new{
                dimen = Geom:new{ w = bar_width, h = total_bar_height },
                bar_column,
            }

            local focusable_bar = FrameContainer:new{
                bordersize = 1,
                color = Blitbuffer.COLOR_WHITE,
                margin = 0,
                padding = 0,
                focus_border_size = 1,
                focus_border_color = Blitbuffer.COLOR_BLACK,
                focusable = true,
                bar_container,
            }

            local tappable_bar = InputContainer:new{
                dimen = Geom:new{ w = bar_width, h = total_bar_height },
                focusable_bar,
            }
            local month_data = m
            local month_label = m.label_full or MONTH_NAMES_FULL[m.month_num] or m.label or "?"
            local month_year_label = month_label .. " " .. popup_self.selected_year
            tappable_bar.ges_events = {
                Tap = {
                    GestureRange:new{
                        ges = "tap",
                        range = function() return tappable_bar.dimen end,
                    }
                },
            }
            function tappable_bar:onTap()
                popup_self:showBooksForMonth(month_data.month, month_year_label)
                return true
            end

            table.insert(bars_row, tappable_bar)

            local month_label_widget = TextWidget:new{
                text = string.lower(_(m.label)),
                face = font_small,
            }
            table.insert(month_labels_row, CenterContainer:new{
                dimen = Geom:new{ w = bar_width, h = month_label_widget:getSize().h },
                month_label_widget,
            })

            if i < #data_slice then
                table.insert(bars_row, HorizontalSpan:new{ width = bar_gap })
                table.insert(month_labels_row, HorizontalSpan:new{ width = bar_gap })
            end
        end

        return VerticalGroup:new{
            align = "center",
            bars_row,
            VerticalSpan:new{ height = Size.padding.small },
            month_labels_row,
        }
    end

    local foc_mgr_thirdRow = {}
    local foc_mgr_fourthRow = {}
    local chart = VerticalGroup:new{ align = "center" }
    local row_index = 0

    for i = 1, #monthly_data, 6 do
        local row_data = {}
        local nonZeroPositions = {}
        for j = i, math.min(i + 5, #monthly_data) do
            local m = monthly_data[j]
            table.insert(row_data, m)
            local target_value = popup_self.mode == INSIGHTS_MODE_HOURS and "hours" or "days"
            if m[target_value] ~= 0 then
                table.insert(nonZeroPositions, #row_data)
            end
        end
        if #row_data > 0 then
            if row_index > 0 then
                table.insert(chart, VerticalSpan:new{ height = Size.padding.default })
            end
            local bar_row_group = createBarRow(row_data)
            local bars_row = bar_row_group[1]
            for _, pos in ipairs(nonZeroPositions) do
                local idx = (pos * 2) - 1
                local bar_widget = bars_row[idx]
                if bar_widget then
                    if row_index == 0 then
                        table.insert(foc_mgr_thirdRow, bar_widget)
                    else
                        table.insert(foc_mgr_fourthRow, bar_widget)
                    end
                end
            end
            table.insert(chart, bar_row_group)
            row_index = row_index + 1
        end
    end

    if #foc_mgr_thirdRow > 0 then table.insert(popup_self.layout, foc_mgr_thirdRow) end
    if #foc_mgr_fourthRow > 0 then table.insert(popup_self.layout, foc_mgr_fourthRow) end

    return chart
end

local function buildCurrentStreakWidget(streaks_dimen, value, weeksOrDays, fonts, streaks_colors)
    local heading_text = weeksOrDays == 0 and _("weeks in a row") or _("days in a row")
    local heading_text_widget = TextWidget:new{
        text = heading_text,
        padding = 0,
        face = fonts.streakLabel,
        fgcolor = weeksOrDays == 0 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
    }
    local value_widget = TextWidget:new{
        text = value,
        padding = 0,
        face = fonts.streakValue,
        fgcolor = weeksOrDays == 0 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
    }
    local boxContents = VerticalGroup:new{
        heading_text_widget,
        value_widget,
    }
    return FrameContainer:new{
        padding = 0,
        bordersize = Screen:scaleBySize(1),
        margin = 0,
        color = weeksOrDays == 0 and streaks_colors.darkGray or streaks_colors.lightGray,
        background = weeksOrDays == 0 and streaks_colors.darkGray or streaks_colors.lightGray,
        radius = Screen:scaleBySize(7),
        CenterContainer:new{
            dimen = Geom:new{ w = streaks_dimen.box_width, h = streaks_dimen.box_height },
            boxContents,
        }
    }
end

local function buildBestStreakWidget(streaks, streaks_dimen, fonts, streaks_colors)
    local function buildBestModule(value, weekOrDay, isLongest, ts_start, ts_end)
        local heading_text = weekOrDay == 0 and _("weekly record") or _("daily record")
        if isLongest then heading_text = heading_text .. " ★" end
        local heading_text_widget = TextBoxWidget:new{
            width = streaks_dimen.box_width - Screen:scaleBySize(10),
            padding = 0,
            text = heading_text,
            face = fonts.streakLabel,
            fgcolor = streaks_colors.midGray,
        }
        local value_text = weekOrDay == 0 and N_("week", "weeks", streaks.weeks.best) or N_("day", "days", streaks.days.best)
        value_text = value .. " " .. value_text
        local value_widget = TextBoxWidget:new{
            width = streaks_dimen.box_width - Screen:scaleBySize(10),
            padding = 0,
            line_height = 0,
            text = value_text,
            face = fonts.streaRecordValue,
            fgcolor = streaks_colors.black,
        }
        local widget = VerticalGroup:new{
            heading_text_widget,
            VerticalSpan:new{ width = -Screen:scaleBySize(3) },
            value_widget,
        }
        if value > 1 and ts_start and ts_end then
            local startDay = os.date("%Y.%m.%d", ts_start)
            local endDay = os.date("%y.%m.%d", ts_end)
            local startEndWidget_txt = startDay .. "-" .. endDay
            local startEndWidget = TextBoxWidget:new{
                width = streaks_dimen.box_width - Screen:scaleBySize(10),
                padding = 0,
                text = startEndWidget_txt,
                face = fonts.streakStartEndWidget,
                fgcolor = streaks_colors.black,
            }
            table.insert(widget, startEndWidget)
        end
        return widget
    end

    local isLongest_w = (streaks.weeks.best > 1) and (streaks.weeks.best == streaks.weeks.current) and true or false
    local isLongest_d = (streaks.days.best > 1) and (streaks.days.best == streaks.days.current) and true or false

    local bestModule = VerticalGroup:new{
        buildBestModule(streaks.weeks.best, 0, isLongest_w, streaks.weeks.best_start, streaks.weeks.best_end),
        VerticalSpan:new{ width = Screen:scaleBySize(5) },
        buildBestModule(streaks.days.best, 1, isLongest_d, streaks.days.best_start, streaks.days.best_end),
    }
    local bestModule_dimen = bestModule:getSize()
    if bestModule_dimen.h > streaks_dimen.box_height then
        streaks_dimen.box_height = bestModule_dimen.h + Screen:scaleBySize(6)
    end
    return FrameContainer:new{
        padding = 0,
        bordersize = Screen:scaleBySize(1),
        margin = 0,
        color = streaks_colors.midGray,
        radius = Screen:scaleBySize(7),
        CenterContainer:new{
            dimen = Geom:new{ w = streaks_dimen.box_width, h = streaks_dimen.box_height },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = Screen:scaleBySize(9) },
                bestModule
            },
        }
    }
end

local function buildInsightsSections(popup_self, streaks, yearly_stats, yearRange, monthly_data, fonts, layout, year)
    popup_self.layout = {}

    local sections = VerticalGroup:new{ align = "left" }

    local streakBoxWidth = math.floor((layout.full_width - (2 * Size.padding.large) - 3 * Screen:scaleBySize(2)) / 3)
    local streaks_dimen = {
        box_width = streakBoxWidth,
        box_height = streakBoxWidth,
    }
    local streaks_colors = {
        lightGray = Blitbuffer.COLOR_GRAY_E,
        darkGray = Blitbuffer.COLOR_GRAY_4,
        midGray = Blitbuffer.COLOR_GRAY_7,
        black = Blitbuffer.COLOR_BLACK,
    }

    local maxCurrentStreak = math.max(streaks.days.current, streaks.weeks.current)
    if maxCurrentStreak > 1999 then
        fonts.streakValue = Font:getFace("NotoSans-Bold.ttf", 50)
    elseif maxCurrentStreak > 199 then
        fonts.streakValue = Font:getFace("NotoSans-Bold.ttf", 55)
    end

    local bestStreakWidget = buildBestStreakWidget(streaks, streaks_dimen, fonts, streaks_colors)
    local streaks_weekWidget = buildCurrentStreakWidget(streaks_dimen, streaks.weeks.current, 0, fonts, streaks_colors)
    local streaks_dayWidget = buildCurrentStreakWidget(streaks_dimen, streaks.days.current, 1, fonts, streaks_colors)
    local streaksBlock = HorizontalGroup:new{
        streaks_weekWidget,
        HorizontalSpan:new{ width = Size.padding.large },
        streaks_dayWidget,
        HorizontalSpan:new{ width = Size.padding.large },
        bestStreakWidget,
    }
    streaksBlock = VerticalGroup:new{
        streaksBlock,
        VerticalSpan:new{ width = Size.padding.large },
    }

    local year_header = buildYearHeader(popup_self, fonts.section, layout, yearRange)
    local yearly_row = buildYearlyRow(popup_self, yearly_stats, fonts, layout)

    local chart = buildMonthlyChart(popup_self, monthly_data, layout, fonts)
    local yearDataBlock
    if chart and year_header and yearly_row then
        yearDataBlock = VerticalGroup:new{
            year_header,
            yearly_row,
            chart,
        }
        yearDataBlock = FrameContainer:new{
            padding = 0,
            margin = 0,
            width = streaksBlock:getSize().w,
            height = yearDataBlock:getSize().h,
            color = Blitbuffer.COLOR_GRAY_E,
            bordersize = 0,
            radius = Screen:scaleBySize(7),
            yearDataBlock,
        }
    end
    table.insert(sections, streaksBlock)
    table.insert(sections, yearDataBlock)
    return sections
end

Dispatcher:registerAction("reading_insights_popup", {
    category = "none",
    event = "ShowReadingInsightsPopup",
    title = _("Reading statistics: reading insights"),
    general = true,
})

ReadingInsightsPopup = FocusManager:extend{
    modal = true,
    ui = nil,
    width = nil,
    height = nil,
    selected_year = nil,
    mode = nil,
    selected = { x = 1, y = 2 }
}

function ReadingInsightsPopup:calculateStreaks()
    local streaks = {
        days = { current = 0, best = 0, best_start = 0, best_end = 0 },
        weeks = { current = 0, best = 0, best_start = 0, best_end = 0 },
    }

    return withStatsDb(streaks, function(conn)
        local dates = {}
        local sql = [[
            SELECT date(start_time, 'unixepoch', 'localtime') as d,
                   min(start_time) as timestamp
            FROM page_stat
            GROUP BY d
            ORDER BY d DESC
        ]]
        withStatement(conn, sql, function(stmt)
            for row in stmt:rows() do
                table.insert(dates, { row[1], tonumber(row[2]) })
            end
        end)

        local today = os.date("%Y-%m-%d")
        local yesterday = os.date("%Y-%m-%d", os.time() - 86400)

        local function isCurrentDayStart(first_date)
            return first_date == today or first_date == yesterday
        end

        local function isConsecutiveDay(prev_date, curr_date)
            local year, month, day = parseDateYMD(prev_date)
            if not year then return false end
            local prev_time = os.time({ year = year, month = month, day = day })
            local expected_prev = os.date("%Y-%m-%d", prev_time - 86400)
            return curr_date == expected_prev
        end

        streaks.days = computeStreaks(dates, isConsecutiveDay, isCurrentDayStart, 1)

        local weeks = {}
        local sql_weeks = [[
            SELECT strftime('%G-%V', start_time, 'unixepoch', 'localtime') as week,
                   MIN(start_time) as first_timestamp,
                   MAX(start_time) as last_timestamp
            FROM page_stat
            GROUP BY week
            ORDER BY week DESC
        ]]
        withStatement(conn, sql_weeks, function(stmt_weeks)
            for row in stmt_weeks:rows() do
                table.insert(weeks, { tonumber(row[2]), tonumber(row[3]) })
            end
        end)

        local current_week = os.date("%G-%V")
        local last_week = os.date("%G-%V", os.time() - 7 * 86400)

        local function isCurrentWeekStart(first_week_stamp)
            local first_week = os.date("%G-%V", first_week_stamp)
            return first_week == current_week or first_week == last_week
        end

        local function isConsecutiveWeek(prev_week_stamp, curr_week_stamp)
            local prev_year_wk = parseWeekYear(prev_week_stamp)
            local curr_year_wk = parseWeekYear(curr_week_stamp)
            if not prev_year_wk or not curr_year_wk then return false end
            local expected_curr_year_wk = os.date("%G-%V", prev_week_stamp - (7 * 86400))
            return curr_year_wk == expected_curr_year_wk
        end

        streaks.weeks = computeStreaks(weeks, isConsecutiveWeek, isCurrentWeekStart, 0)

        insightsCache.streaks = streaks
        if streaks then uploadInsightsCacheToGReader("streaks") end
        return streaks
    end)
end

function ReadingInsightsPopup:getMonthlyReadingDays(year)
    local months = {}
    return withStatsDb(months, function(conn)
        local year_str = tostring(year)
        local sql = string.format([[
            SELECT strftime('%%Y-%%m', start_time, 'unixepoch', 'localtime') AS month,
                   COUNT(DISTINCT date(start_time, 'unixepoch', 'localtime')) AS days_read
            FROM page_stat
            WHERE strftime('%%Y', start_time, 'unixepoch', 'localtime') = '%s'
            GROUP BY month
            ORDER BY month ASC
        ]], year_str)

        local results = {}
        withStatement(conn, sql, function(stmt)
            for row in stmt:rows() do
                results[row[1]] = row[2]
            end
        end)

        for month_num = 1, 12 do
            local year_month = string.format("%04d-%02d", year, month_num)
            local days = tonumber(results[year_month]) or 0
            table.insert(months, {
                month = year_month,
                days = days,
                label = MONTH_NAMES_SHORT[month_num],
                label_full = MONTH_NAMES_FULL[month_num],
                month_num = month_num
            })
        end

        for _, m in ipairs(months) do
            if not m.label_full then
                local month_num = m.month_num or tonumber(m.month:match("%d+$"))
                if month_num then
                    m.label = MONTH_NAMES_SHORT[month_num] or m.label
                    m.label_full = MONTH_NAMES_FULL[month_num] or m.label_full
                end
            end
        end

        insightsCache.monthlyReadingDays = insightsCache.monthlyReadingDays or {}
        insightsCache.monthlyReadingDays[year] = months
        if months then uploadInsightsCacheToGReader("MonthlyReadingDays") end
        return months
    end)
end

function ReadingInsightsPopup:getMonthlyReadingHours(year)
    local months = {}
    return withStatsDb(months, function(conn)
        local year_str = tostring(year)
        local sql = string.format([[
            SELECT dates AS month,
                   SUM(sum_duration) / 3600.0 AS hours_read
            FROM (
                SELECT strftime('%%Y-%%m', start_time, 'unixepoch', 'localtime') AS dates,
                       sum(duration) AS sum_duration
                FROM page_stat
                WHERE strftime('%%Y', start_time, 'unixepoch', 'localtime') = '%s'
                GROUP BY id_book, page, dates
            )
            GROUP BY dates
            ORDER BY dates ASC
        ]], year_str)

        local results = {}
        withStatement(conn, sql, function(stmt)
            for row in stmt:rows() do
                results[row[1]] = row[2]
            end
        end)

        for month_num = 1, 12 do
            local year_month = string.format("%04d-%02d", year, month_num)
            local hours = tonumber(results[year_month]) or 0
            if hours >= 1 then
                hours = math.floor(hours)
            elseif hours > 0 then
                hours = (math.floor(hours * 10)) / 10
            end
            table.insert(months, {
                month = year_month,
                hours = hours,
                label = MONTH_NAMES_SHORT[month_num],
                label_full = MONTH_NAMES_FULL[month_num],
                month_num = month_num
            })
        end

        for _, m in ipairs(months) do
            if not m.label_full then
                local month_num = m.month_num or tonumber(m.month:match("%d+$"))
                if month_num then
                    m.label = MONTH_NAMES_SHORT[month_num] or m.label
                    m.label_full = MONTH_NAMES_FULL[month_num] or m.label_full
                end
            end
        end

        insightsCache.monthlyReadingHours = insightsCache.monthlyReadingHours or {}
        insightsCache.monthlyReadingHours[year] = months
        if months then uploadInsightsCacheToGReader("MonthlyReadingHours") end
        return months
    end)
end

function ReadingInsightsPopup:getYearlyStats(year)
    local stats = { days = 0, pages = 0, duration = 0 }
    return withStatsDb(stats, function(conn)
        local year_str = tostring(year)

        local sql_days = string.format([[
            SELECT COUNT(DISTINCT date(start_time, 'unixepoch', 'localtime'))
            FROM page_stat
            WHERE strftime('%%Y', start_time, 'unixepoch', 'localtime') = '%s'
        ]], year_str)
        withStatement(conn, sql_days, function(stmt_days)
            for row in stmt_days:rows() do
                stats.days = tonumber(row[1]) or 0
            end
        end)

        local sql_pages = string.format([[
            SELECT count(*)
            FROM (
                SELECT 1
                FROM page_stat
                WHERE strftime('%%Y', start_time, 'unixepoch', 'localtime') = '%s'
                GROUP BY id_book, page
            )
        ]], year_str)
        withStatement(conn, sql_pages, function(stmt_pages)
            for row in stmt_pages:rows() do
                stats.pages = tonumber(row[1]) or 0
            end
        end)

        local sql_duration = string.format([[
            SELECT sum(duration)
            FROM page_stat
            WHERE strftime('%%Y', start_time, 'unixepoch', 'localtime') = '%s'
        ]], year_str)
        withStatement(conn, sql_duration, function(stmt_duration)
            for row in stmt_duration:rows() do
                stats.duration = tonumber(row[1]) or 0
            end
        end)

        insightsCache.yearlyStats = insightsCache.yearlyStats or {}
        insightsCache.yearlyStats[year] = stats
        if stats then uploadInsightsCacheToGReader("YearlyStats") end
        return stats
    end)
end

function ReadingInsightsPopup:getYearRange()
    local current_year = tonumber(os.date("%Y"))
    local range = { min_year = current_year, max_year = current_year }
    return withStatsDb(range, function(conn)
        local sql = [[
            SELECT MIN(strftime('%Y', start_time, 'unixepoch', 'localtime')) AS min_year,
                   MAX(strftime('%Y', start_time, 'unixepoch', 'localtime')) AS max_year
            FROM page_stat
        ]]
        withStatement(conn, sql, function(stmt)
            for row in stmt:rows() do
                if row[1] then range.min_year = tonumber(row[1]) or current_year end
                if row[2] then range.max_year = tonumber(row[2]) or current_year end
            end
        end)

        insightsCache.yearRange = range
        if range then uploadInsightsCacheToGReader("YearRange") end
        return range
    end)
end

-- 修复 SQL 拼接
local function getBooksForPeriod(period_format, period_value)
    local books = {}
    local pagesTotal = 0
    local durationTotal = 0
    local result = withStatsDb(books, function(conn)
        local sql = [[
            SELECT book.title, book.authors,
                   COUNT(DISTINCT page_stat.page) as pages_read,
                   SUM(page_stat.duration) as duration_seconds
            FROM page_stat
            JOIN book ON page_stat.id_book = book.id
            WHERE strftime(']] .. period_format .. [[', start_time, 'unixepoch', 'localtime') = ']] .. period_value .. [['
            GROUP BY page_stat.id_book
            ORDER BY pages_read DESC
        ]]
        withStatement(conn, sql, function(stmt)
            for row in stmt:rows() do
                local pages_curr = tonumber(row[3]) or 0
                local duration_sec = tonumber(row[4]) or 0
                table.insert(books, {
                    title = row[1] or _("Unknown"),
                    authors = row[2] or "",
                    pages = pages_curr,
                    duration = duration_sec,
                })
                pagesTotal = pagesTotal + pages_curr
                durationTotal = durationTotal + duration_sec
            end
        end)
        return { books, pagesTotal, durationTotal }
    end)
    if not result or not result[1] then return {}, 0, 0 end

    if #result[1] > 500 then
        local limited_books = {}
        for i = 1, 500 do
            table.insert(limited_books, result[1][i])
        end
        return limited_books, result[2], result[3]
    end

    return result[1], result[2], result[3]
end

function ReadingInsightsPopup:getBooksForMonth(year_month)
    return getBooksForPeriod("%Y-%m", year_month)
end

-- ======================== 书单弹窗（八行版，已改为七行显示） ========================

local function getItemsPerPage()
    local s = G_reader_settings:readSetting("mini_ri_sett", {})
    if type(s) == "table" and type(s.items_per_page) == "number" then
        return s.items_per_page
    end
    return 7
end
local BookListPopup = FocusManager:extend{
    modal = true,
    books = nil,
    title_line1 = nil,
    title_line2 = nil,
    current_page = 1,
    items_per_page = 7,  -- 改为七行
    return_data = nil,
    ui = nil,
    target_height = nil,
    total_pages = 1,
    pages_total = 0,
    duration_total = 0,
    _skip_close_full_refresh = false,
    _changing_page = false,
}

function BookListPopup:_formatDuration(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if hours > 0 then
        return tostring(hours) .. _("hour") .. tostring(minutes) .. _("minute")
    else
        return tostring(minutes) .. _("minute")
    end
end

function BookListPopup:init()
    -- 重置事件表，避免与旧事件冲突
    self.ges_events = {}
    self.key_events = {}
    self._skip_close_full_refresh = false
    self._changing_page = false
    self.items_per_page = getItemsPerPage()

    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local max_widget_width = math.floor(screen_w * 4/5)
    if screen_w > screen_h then
        max_widget_width = math.floor(max_widget_width * screen_h / screen_w)
    end

    self.dimen = Geom:new{ w = screen_w, h = screen_h }

    local fonts = buildSerifFonts()
    local popup_border = Screen:scaleBySize(2)
    local layout = buildLayout(max_widget_width, Screen:scaleBySize(15) + popup_border, Screen:scaleBySize(20))

    local total_items = #self.books
    local total_pages = math.max(1, math.ceil(total_items / self.items_per_page))
    self.total_pages = total_pages
    if self.current_page < 1 then self.current_page = 1 end
    if self.current_page > total_pages then self.current_page = total_pages end

    local start_idx = (self.current_page - 1) * self.items_per_page + 1
    local end_idx = math.min(start_idx + self.items_per_page - 1, total_items)

    local border_size = Screen:scaleBySize(1)
    local title_frame_width = layout.content_width + 2 * border_size

    local list = VerticalGroup:new{ align = "left" }
    local last_row_h = Screen:scaleBySize(60)
    local max_row_height = 0

    local list_padding = Size.padding.default + Screen:scaleBySize(2)
    local list_content_width = layout.content_width - 2 * list_padding

    local rank_sample = TextWidget:new{ text = "99", face = fonts.small }
    local rank_w = rank_sample:getSize().w + Screen:scaleBySize(10)
    rank_sample:free()
    local pages_sample = TextWidget:new{ text = "9999 " .. _("pages"), face = fonts.small }
    local pages_w = pages_sample:getSize().w + Screen:scaleBySize(6)
    pages_sample:free()
    local title_w = list_content_width - rank_w - pages_w - 2 * Screen:scaleBySize(8)

    local white = Blitbuffer.COLOR_WHITE
    local black = Blitbuffer.COLOR_BLACK

    for idx = start_idx, end_idx do
        local book = self.books[idx]
        if not book then break end

        if idx > start_idx then
            table.insert(list, createDashedSeparator(list_content_width))
        end

        local rank_tw = TextWidget:new{ text = tostring(idx), face = fonts.small, fgcolor = white }
        local rank_circle_diameter = math.max(rank_tw:getSize().w, rank_tw:getSize().h) + Screen:scaleBySize(1)
        local rank_bg = FrameContainer:new{
            background = Blitbuffer.COLOR_GRAY_4,
            radius = math.floor(rank_circle_diameter / 2),
            bordersize = 0,
            padding = 0,
            margin = 0,
            CenterContainer:new{
                dimen = Geom:new{ w = rank_circle_diameter, h = rank_circle_diameter },
                rank_tw,
            },
        }

        local pages_str = formatCount(book.pages) .. " " .. N_("page", "pages", book.pages)
        local pages_tw = TextWidget:new{ text = pages_str, face = fonts.small, fgcolor = black }

        local duration_str = self:_formatDuration(book.duration or 0)
        local duration_tw = TextWidget:new{ text = duration_str, face = fonts.author, fgcolor = black }

        local right_col = VerticalGroup:new{
            align = "right",
            pages_tw,
            VerticalSpan:new{ height = Screen:scaleBySize(2) },
            duration_tw,
        }

        local title_col
        if book.authors and book.authors ~= "" then
            title_col = VerticalGroup:new{
                align = "left",
                TextWidget:new{ text = book.title, face = fonts.small, max_width = title_w, fgcolor = black },
                VerticalSpan:new{ height = Screen:scaleBySize(2) },
                TextWidget:new{ text = "作者：" .. book.authors, face = fonts.author, max_width = title_w, fgcolor = black },
            }
        else
            title_col = TextWidget:new{ text = book.title, face = fonts.small, max_width = title_w, fgcolor = black }
        end

        local rank_h = rank_bg:getSize().h
        local title_h = title_col:getSize().h
        local right_h = right_col:getSize().h
        local row_h = math.max(rank_h, title_h, right_h) + Screen:scaleBySize(8)
        last_row_h = row_h
        if row_h > max_row_height then max_row_height = row_h end

        local rank_container = CenterContainer:new{
            dimen = Geom:new{ w = rank_w, h = row_h },
            rank_bg,
        }
        local title_container = LeftContainer:new{
            dimen = Geom:new{ w = title_w, h = row_h },
            title_col,
        }
        local right_container = RightContainer:new{
            dimen = Geom:new{ w = pages_w, h = row_h },
            right_col,
        }

        local row = HorizontalGroup:new{
            align = "center",
            rank_container,
            HorizontalSpan:new{ width = Screen:scaleBySize(8) },
            title_container,
            HorizontalSpan:new{ width = Screen:scaleBySize(8) },
            right_container,
        }

        table.insert(list, row)
    end

    if max_row_height == 0 then max_row_height = last_row_h end

    local actual_items = end_idx - start_idx + 1
    local has_summary = (self.current_page == total_pages)

    if has_summary then
        if actual_items > 0 then
            table.insert(list, createDashedSeparator(list_content_width))
        end
        local total_pages_text = _("Total pages:") .. formatCount(self.pages_total or 0) .. " " .. N_("page", "pages", self.pages_total or 0)
        local total_duration_text = _("Total duration:") .. self:_formatDuration(self.duration_total or 0)
        local summary_left = TextWidget:new{ text = total_pages_text, face = fonts.small, fgcolor = black }
        local summary_right = TextWidget:new{ text = total_duration_text, face = fonts.small, fgcolor = black }

        local gap_width = list_content_width - summary_left:getSize().w - summary_right:getSize().w - 2 * Screen:scaleBySize(8)
        if gap_width < 0 then gap_width = 0 end

        local summary_content = HorizontalGroup:new{
            align = "center",
            summary_left,
            HorizontalSpan:new{ width = gap_width },
            summary_right,
        }

        local summary_row = CenterContainer:new{
            dimen = Geom:new{ w = list_content_width, h = max_row_height },
            summary_content,
        }
        table.insert(list, summary_row)
    end

    -- 填充空行
    local fill_count = self.items_per_page - actual_items - (has_summary and 1 or 0)
    if fill_count > 0 then
        for i = 1, fill_count do
            if actual_items > 0 or i > 1 then
                table.insert(list, createDashedSeparator(list_content_width))
            end
            table.insert(list, FrameContainer:new{
                bordersize = 0, padding = 0, margin = 0,
                background = Blitbuffer.COLOR_WHITE,
                CenterContainer:new{
                    dimen = Geom:new{ w = list_content_width, h = max_row_height },
                    TextWidget:new{ text = " ", face = fonts.small, fgcolor = Blitbuffer.COLOR_WHITE },
                },
            })
        end
    end

    local list_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 1,
        color = Blitbuffer.COLOR_BLACK,
        radius = 30,
        width = title_frame_width,
        padding_top = Size.padding.default,
        padding_bottom = Size.padding.default,
        padding_left = list_padding,
        padding_right = list_padding,
        margin = 0,
        list,
    }

    local popup_self = self

    local function navBtn(direction, target_page, enabled)
        local icon_name = direction == "left" and "chevron.left" or "chevron.right"
        local icon_width = Screen:scaleBySize(11)
        local btn_icon = IconWidget:new{ icon = icon_name, width = icon_width, alpha = true, is_icon = true }
        local icon_size = btn_icon:getSize()
        local btn_side = math.max(icon_size.w, icon_size.h) + Screen:scaleBySize(2)
        local btn_w, btn_h = btn_side, btn_side

        local btn_fc
        if enabled then
            btn_fc = FrameContainer:new{
                background = Blitbuffer.COLOR_GRAY_E,
                color = Blitbuffer.COLOR_BLACK,
                bordersize = 0,
                radius = Screen:scaleBySize(8),
                padding = 0, margin = 0,
                CenterContainer:new{ dimen = Geom:new{ w = btn_w, h = btn_h }, btn_icon },
            }
        else
            btn_fc = FrameContainer:new{
                background = Blitbuffer.COLOR_WHITE,
                color = Blitbuffer.COLOR_BLACK,
                bordersize = 0,
                radius = Screen:scaleBySize(8),
                padding = 0, margin = 0,
                CenterContainer:new{ dimen = Geom:new{ w = btn_w, h = btn_h }, btn_icon },
            }
        end

        local ic = InputContainer:new{
            dimen = Geom:new{ w = btn_w, h = btn_h },
            btn_fc,
        }
        ic.ges_events = {
            Tap = { GestureRange:new{ ges = "tap", range = function() return ic.dimen end } },
            Hold = { GestureRange:new{ ges = "hold", range = function() return ic.dimen end } },
        }
        function ic:onTap()
            if enabled then
                popup_self:changePage(target_page)
            end
            return true
        end
        function ic:onHold()
            if direction == "left" then
                popup_self:changePage(1)
            else
                popup_self:changePage(popup_self.total_pages)
            end
            return true
        end
        return ic
    end

    local page_label_font = Font:getFace("NotoSans-Regular.ttf", 15)
    local page_label = TextWidget:new{
        text = tostring(self.current_page) .. " / " .. tostring(total_pages),
        face = page_label_font,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    local page_label_with_padding = FrameContainer:new{
        bordersize = 0,
        padding_top = Screen:scaleBySize(2),
        padding_bottom = Screen:scaleBySize(2),
        padding_left = 0,
        padding_right = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        page_label,
    }
    local page_label_dimen = page_label_with_padding:getSize()
    local nav_btn_h = navBtn("left", 1, true):getSize().h
    local page_label_container = CenterContainer:new{
        dimen = Geom:new{ w = page_label_dimen.w + Screen:scaleBySize(20), h = math.max(page_label_dimen.h, nav_btn_h) },
        page_label_with_padding,
    }

    local nav_row = HorizontalGroup:new{
        align = "center",
        navBtn("left", self.current_page - 1, self.current_page > 1),
        HorizontalSpan:new{ width = Size.padding.large },
        page_label_container,
        HorizontalSpan:new{ width = Size.padding.large },
        navBtn("right", self.current_page + 1, self.current_page < total_pages),
    }

    local line1_widget = TextWidget:new{ text = self.title_line1 or "", face = fonts.titleLine1, fgcolor = Blitbuffer.COLOR_BLACK, padding = 0 }
    local title_group = VerticalGroup:new{
        align = "center",
        line1_widget,
    }

    local title_frame_with_padding = FrameContainer:new{
        bordersize = 0,
        padding_top = Screen:scaleBySize(4),
        padding_bottom = Screen:scaleBySize(8),
        padding_left = 0,
        padding_right = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        title_group,
    }
    local title_frame_dimen = title_frame_with_padding:getSize()

    local title_tap = InputContainer:new{
        dimen = Geom:new{ w = title_frame_width, h = title_frame_dimen.h },
        CenterContainer:new{
            dimen = Geom:new{ w = title_frame_width, h = title_frame_dimen.h },
            title_frame_with_padding,
        },
    }
    title_tap.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return title_tap.dimen end } },
    }
    function title_tap:onTap()
        UIManager:close(popup_self)
        if popup_self.return_data then
            local rd = popup_self.return_data
            if rd and rd.ui then
                local ok, new_popup = pcall(ReadingInsightsPopup.new, ReadingInsightsPopup, {
                    ui = rd.ui,
                    selected_year = rd.selected_year,
                    mode = rd.mode,
                })
                if ok and new_popup then
                    UIManager:show(new_popup)
                end
            end
        end
        return true
    end

    local nav_container = CenterContainer:new{
        dimen = Geom:new{ w = title_frame_width, h = nav_row:getSize().h + Screen:scaleBySize(4) },
        nav_row,
    }

    local content = VerticalGroup:new{
        align = "left",
        title_tap,
        list_frame,
        VerticalSpan:new{ width = Screen:scaleBySize(2) },
        nav_container,
    }

    local content_size = content:getSize()
    if not self.target_height then
        self.target_height = content_size.h
    end
    if content_size.h < self.target_height then
        table.insert(content, VerticalSpan:new{ height = self.target_height - content_size.h })
    end

    self.popup_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 2,
        color = Blitbuffer.COLOR_BLACK,
        radius = 45,
        padding_top = Screen:scaleBySize(4),
        padding_bottom = Screen:scaleBySize(4),
        padding_left = Screen:scaleBySize(15),
        padding_right = Screen:scaleBySize(15),
        content,
    }

    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        self.popup_frame,
    }

    -- 计算卡片在屏幕上的绝对区域，用于局部刷新
    local popup_frame_size = self.popup_frame:getSize()
    self._card_dimen = Geom:new{
        x = math.floor((Screen:getWidth() - popup_frame_size.w) / 2),
        y = math.floor((Screen:getHeight() - popup_frame_size.h) / 2),
        w = popup_frame_size.w,
        h = popup_frame_size.h,
    }

    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{ ges = "tap", range = self.dimen }
        }
    end
    if Device:hasKeys() then
        self.key_events.AnyKeyPressed = {{{ "Back", "Home" }}}
    end
end

-- 修复：关闭旧弹窗时跳过全屏刷新，避免闪烁，且不残留双弹窗
function BookListPopup:changePage(new_page)
    if new_page < 1 then new_page = 1 end
    if new_page > self.total_pages then new_page = self.total_pages end
    if new_page == self.current_page then return end
    if self._changing_page then return end
    self._changing_page = true

    local books = self.books
    local title_line1 = self.title_line1
    local title_line2 = self.title_line2
    local pages_total = self.pages_total or 0
    local duration_total = self.duration_total or 0
    local return_data = self.return_data
    local target_height = self.target_height
    local items_per_page = self.items_per_page

    -- 标记跳过关闭时的全屏刷新
    self._skip_close_full_refresh = true

    UIManager:close(self)

    local new_popup = BookListPopup:new{
        books = books,
        title_line1 = title_line1,
        title_line2 = title_line2,
        pages_total = pages_total,
        duration_total = duration_total,
        current_page = new_page,
        return_data = return_data,
        target_height = target_height,
        items_per_page = items_per_page,
    }
    UIManager:show(new_popup)
end

function BookListPopup:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self.popup_frame.dimen) then
        UIManager:close(self)
    end
    return true
end

function BookListPopup:onAnyKeyPressed()
    UIManager:close(self)
    return true
end

function BookListPopup:onShow()
    UIManager:setDirty(self, "ui", self.popup_frame.dimen)
    return true
end

function BookListPopup:onCloseWidget()
    if self._skip_close_full_refresh then
        -- 翻页关闭时，不进行全屏刷新，避免闪烁
        return
    end
    if self._card_dimen then
        UIManager:setDirty(nil, "ui", self._card_dimen)
    else
        UIManager:setDirty(nil, function() return "full" end)
    end
end

-- 显示书单
local function showBooksForPeriod(popup_self, books, pages_total, duration_total, empty_text, title_line1, title_line2)
    if #books == 0 then
        UIManager:show(InfoMessage:new{ text = empty_text })
        return
    end

    local return_data = {
        selected_year = popup_self.selected_year,
        mode = popup_self.mode,
        ui = popup_self.ui,
    }

    UIManager:close(popup_self)

    local popup = BookListPopup:new{
        title_line1 = title_line1,
        title_line2 = title_line2 or "",
        books = books,
        pages_total = pages_total or 0,
        duration_total = duration_total or 0,
        current_page = 1,
        return_data = return_data,
    }
    UIManager:show(popup)
end

function ReadingInsightsPopup:showBooksForMonth(year_month, month_label_full)
    local books, pages_total, duration_total = self:getBooksForMonth(year_month)
    local bookCount = #books
    local month_num = tonumber(string.sub(year_month, 6, 7))
    local line1 = string.format("%d月书籍排行top%d", month_num, bookCount)

    showBooksForPeriod(self, books, pages_total, duration_total, T(_("No books read in %1"), month_label_full), line1, "")
end

function ReadingInsightsPopup:getBooksForYear(year)
    return getBooksForPeriod("%Y", tostring(year))
end

function ReadingInsightsPopup:showBooksForYear(year)
    local books, pages_total, duration_total = self:getBooksForYear(year)
    local bookCount = #books
    local line1 = string.format("%d年书籍排行top%d", year, bookCount)

    showBooksForPeriod(self, books, pages_total, duration_total, _("No books read in ") .. year, line1, "")
end

local function populateEverything(popup_self, year, yearRange)
    logger.info("READING-INSIGHTS-POPUP: POPULATE EVERYTHING CALLED")
    return {
        yearRange = yearRange,
        streaks = insightsCache.streaks or popup_self:calculateStreaks(),
        yearlyStats = insightsCache.yearlyStats and insightsCache.yearlyStats[year] or popup_self:getYearlyStats(year),
        monthlyReadingDays = insightsCache.monthlyReadingDays and insightsCache.monthlyReadingDays[year] or popup_self:getMonthlyReadingDays(year),
        monthlyReadingHours = insightsCache.monthlyReadingHours and insightsCache.monthlyReadingHours[year] or popup_self:getMonthlyReadingHours(year),
    }
end

local function yearExistsInCache(year)
    if insightsCache and insightsCache.yearlyStats and insightsCache.yearlyStats[year] then
        return true
    end
    return false
end

local function getDataToBeDisplayed(popup_self)
    clearCacheIfRequired()
    local yearRange = insightsCache.yearRange or popup_self:getYearRange()
    popup_self.yearRange = yearRange
    if not popup_self.selected_year then
        popup_self.selected_year = yearRange.max_year
    end
    if (not yearExistsInCache(popup_self.selected_year)) or (not insightsCache.streaks) then
        popup_self.modal = false
        logger.info("READING-INSIGHTS-POPUP: RETURNING FALLBACK ARRAY")
        return fallbackTable
    end
    return populateEverything(popup_self, popup_self.selected_year, yearRange)
end

function ReadingInsightsPopup:init()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local max_widget_width = screen_w * 5/6
    if screen_w > screen_h then
        max_widget_width = math.floor(max_widget_width * screen_h / screen_w)
    end

    self.mode = normalizeInsightsMode(self.mode or readInsightsMode())
    local everything = getDataToBeDisplayed(self)
    local yearRange = self.yearRange
    local streaks = everything.streaks
    local yearly_stats = everything.yearlyStats
    local monthly_data
    if self.mode == INSIGHTS_MODE_HOURS then
        monthly_data = everything.monthlyReadingHours
    else
        monthly_data = everything.monthlyReadingDays
    end

    local fonts = buildSerifFonts()
    local widget_layout = cachedLayout or buildLayout(max_widget_width, Size.padding.large, Screen:scaleBySize(20))
    local sections = buildInsightsSections(
        self,
        streaks,
        yearly_stats,
        yearRange,
        monthly_data,
        fonts,
        widget_layout,
        self.selected_year
    )

    self.popup_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Screen:scaleBySize(1),
        radius = Screen:scaleBySize(16),
        padding = Screen:scaleBySize(15),
        sections,
    }

    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        VerticalGroup:new{ self.popup_frame }
    }

    -- 计算卡片在屏幕上的绝对区域，用于局部刷新
    local popup_frame_size = self.popup_frame:getSize()
    self._card_dimen = Geom:new{
        x = math.floor((Screen:getWidth() - popup_frame_size.w) / 2),
        y = math.floor((Screen:getHeight() - popup_frame_size.h) / 2),
        w = popup_frame_size.w,
        h = popup_frame_size.h,
    }

    if everything.isPlaceholder then
        self:onGoToPrevYear(self, self.selected_year)
    end

    self.dimen = Geom:new{ w = screen_w, h = screen_h }

    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{ ges = "tap", range = self.dimen }
        }
        self.ges_events.Swipe = {
            GestureRange:new{ ges = "swipe", range = function() return self.dimen end }
        }
    end

    if Device:hasKeys() then
        self.key_events.AnyKeyPressed = {{{ "RPgBack", "LPgBack", "RPgFwd", "LPgFwd", "Back", "Home" }}}
    end
end

function ReadingInsightsPopup:update(popup_self, selected_year, mode)
    popup_self.selected_year = selected_year
    popup_self.mode = mode
    pcall(function()
        popup_self:init()
        UIManager:setDirty(popup_self, "ui", popup_self.popup_frame.dimen)
    end)
end

function ReadingInsightsPopup:toggleInsightsMode(popup_self)
    local new_mode = popup_self.mode == INSIGHTS_MODE_HOURS and INSIGHTS_MODE_DAYS or INSIGHTS_MODE_HOURS
    saveInsightsMode(new_mode)
    popup_self:update(popup_self, popup_self.selected_year, new_mode)
    return true
end

local function buildAndShowTargetYear(popup_self, target_year)
    if (not yearExistsInCache(target_year)) or (not insightsCache.streaks) then
        local txt
        if not yearExistsInCache(target_year) then
            txt = "Loading insights for " .. target_year .. "..."
        elseif not insightsCache.streaks then
            txt = "Loading streaks..."
        end

        local loading = InfoMessage:new{ text = txt }
        UIManager:show(loading)
        UIManager:tickAfterNext(function()
            populateEverything(popup_self, target_year, popup_self.yearRange)
            UIManager:tickAfterNext(function()
                UIManager:close(loading)
                popup_self:update(popup_self, target_year, popup_self.mode)
            end)
        end)
        return true
    end
    popup_self:update(popup_self, target_year, popup_self.mode)
end

function ReadingInsightsPopup:onGoToPrevYear(popup_self, forced_year)
    local target_year = forced_year
        or (popup_self.selected_year > popup_self.yearRange.min_year and popup_self.selected_year - 1)
    if not target_year then return end
    buildAndShowTargetYear(popup_self, target_year)
end

function ReadingInsightsPopup:onGoToNextYear(popup_self)
    if popup_self.selected_year >= popup_self.yearRange.max_year then return end
    buildAndShowTargetYear(popup_self, popup_self.selected_year + 1)
end

function ReadingInsightsPopup:onAnyKeyPressed(_, key)
    if key and key:match({ { "RPgBack", "LPgBack" } }) then
        return self:onGoToPrevYear(self)
    end
    if key and key:match({ { "RPgFwd", "LPgFwd" } }) then
        return self:onGoToNextYear(self)
    end
    UIManager:close(self)
    return true
end

function ReadingInsightsPopup:onSwipe(arg, ges_ev)
    if ges_ev.direction == "east" then
        return self:onGoToPrevYear(self)
    elseif ges_ev.direction == "west" then
        return self:onGoToNextYear(self)
    else
        UIManager:close(self)
        return true
    end
end

function ReadingInsightsPopup:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.popup_frame.dimen
    end)
    return true
end

function ReadingInsightsPopup:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self.popup_frame.dimen) then
        UIManager:close(self)
    end
    return true
end

function ReadingInsightsPopup:onCloseWidget()
    if self._card_dimen then
        UIManager:setDirty(nil, "ui", self._card_dimen)
    else
        UIManager:setDirty(nil, function() return "full" end)
    end
end

-- Hook
function ReaderUI.onShowReadingInsightsPopup(this)
    local popup = ReadingInsightsPopup:new{ ui = this }
    UIManager:show(popup)
    return true
end

function FileManager:onShowReadingInsightsPopup()
    local popup = ReadingInsightsPopup:new{ ui = self }
    UIManager:show(popup)
    return true
end

-- Patch stats plugin
local ok_up, userpatch = pcall(require, "userpatch")

local function saveLastSyncTimestamp(plugin)
    local original_plugin_onSyncBookStats = plugin.onSyncBookStats
    function plugin:onSyncBookStats()
        cache_timestamps.statsSynced = os.time()
        uploadCacheTimestampsTogreader()
        return original_plugin_onSyncBookStats(self)
    end
end

if ok_up and userpatch and userpatch.registerPatchPluginFunc then
    local ok, err = pcall(userpatch.registerPatchPluginFunc, userpatch, "statistics", saveLastSyncTimestamp)
    if not ok then
        logger.warn("READING-INSIGHTS-POPUP: Failed to register patch:", err)
    end
end

local _M = {}
_M.show = function(ui)
    local popup = ReadingInsightsPopup:new{ ui = ui }
    UIManager:show(popup)
    return true
end
return _M
