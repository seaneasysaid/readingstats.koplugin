--- stats_db.lua
--- KOReader 统计库（statistics.sqlite3）的统一访问层。
---
--- 日历阅读统计 / 阅读热力图 / 阅读报告 / 阅读分析 四个视图原本各自抄了一份
--- 「拼路径 → 判文件存在 → 打开 → 兜异常 → 跑语句 → 记日志」，
--- 四份写法还不一致（其中一处没兜 SQ3.open 的异常，库损坏时会直接抛错）。
--- 统一收到这里：以后 KOReader 若改了数据目录、或要调整错误处理，只改本文件。
---
--- 用法：
---   local StatsDb = require("stats_db")
---   local conn = StatsDb.open("CALENDAR")            -- 失败返回 nil，不抛异常
---   local rows = StatsDb.exec(conn, sql, "CALENDAR") -- 兼容旧表名，失败返回 nil

local DataStorage = require("datastorage")
local logger      = require("logger")

local M = {}

local _path      -- 惰性缓存：避免每次访问都拼一次路径字符串
local _lfs, _SQ3

local function lfs()
    if not _lfs then
        _lfs = require("libs/libkoreader-lfs")
    end
    return _lfs
end

local function sq3()
    if not _SQ3 then
        _SQ3 = require("lua-ljsqlite3/init")
    end
    return _SQ3
end

local function prefix(tag)
    return (tag and (tag .. ": ")) or "STATS_DB: "
end

--- 统计库的绝对路径（KOReader 的 settings 目录下）
function M.path()
    if not _path then
        _path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    end
    return _path
end

--- 库文件的修改时间（秒）。库不存在返回 0，用于判断缓存是否过期。
function M.mtime()
    return lfs().attributes(M.path(), "modification") or 0
end

--- 打开统计库连接。
--- 文件不存在 → 返回 nil（这是新用户的正常状态，只记 debug，不吵日志）
--- 打开抛异常（库损坏）→ 兜住、记 error、返回 nil
function M.open(tag)
    local path = M.path()
    -- 先确认文件存在：sqlite 打开一个不存在的路径会顺手新建出空库文件
    if lfs().attributes(path, "mode") ~= "file" then
        logger.dbg(prefix(tag) .. "statistics.sqlite3 不存在: " .. path)
        return nil
    end
    local ok, conn = pcall(sq3().open, path)
    if not ok or not conn then
        logger.err(prefix(tag) .. "打开统计库失败: " .. path .. " " .. tostring(conn))
        return nil
    end
    return conn
end

--- 关闭连接（不抛异常，可重复调用）
function M.close(conn)
    if conn then
        pcall(function() conn:close() end)
    end
end

--- 执行一条 exec 语句并取回结果表，失败返回 nil。
--- 兼容旧版 KOReader 的表名：page_stat 查不到时自动回退到 page_stat_data。
function M.exec(conn, sql, tag)
    if not conn or not sql then return nil end
    local ok, res = pcall(function() return conn:exec(sql) end)
    if not ok or type(res) ~= "table" then
        local sql2 = sql:gsub("page_stat", "page_stat_data")
        if sql2 ~= sql then
            ok, res = pcall(function() return conn:exec(sql2) end)
        end
    end
    if not ok or type(res) ~= "table" then
        logger.dbg(prefix(tag) .. "exec 失败: " .. tostring(sql))
        return nil
    end
    return res
end

--- prepare 一条语句交给 fn(stmt) 使用，语句必定关闭；出错记 error 并返回 nil。
function M.withStatement(conn, sql, fn, tag)
    if not conn then return nil end
    local stmt = conn:prepare(sql)
    if not stmt then
        logger.err(prefix(tag) .. "SQL prepare 失败: " .. tostring(sql))
        return nil
    end
    local ok, result = pcall(fn, stmt)
    pcall(function() stmt:close() end)
    if ok then return result end
    logger.err(prefix(tag) .. "SQL 执行失败: " .. tostring(result)
        .. " | " .. tostring(sql))
    return nil
end

--- 打开 → 跑 fn(conn) → 关闭；任一步失败都返回 fallback（不抛异常）。
function M.withDb(fallback, fn, tag)
    local conn = M.open(tag)
    if not conn then return fallback end
    local ok, result = pcall(fn, conn)
    M.close(conn)
    if ok then return result end
    logger.err(prefix(tag) .. "查询异常: " .. tostring(result))
    return fallback
end

return M
