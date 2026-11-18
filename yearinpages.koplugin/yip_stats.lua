--[[
Reads KOReader's statistics database and turns one calendar year into a
plain table of numbers. Pure Lua: it only needs a `query(sql)` function that
returns an array of rows, each row an array of column values. That keeps it
testable off-device.
]]

local Stats = {}

local function n(v)
    return tonumber(v) or 0
end

local LOCAL = "'unixepoch', 'localtime'"

local function yearFilter(year, col)
    col = col or "start_time"
    return string.format("strftime('%%Y', %s, %s) = '%04d'", col, LOCAL, year)
end

--- Years that have any reading recorded, newest first.
function Stats.years(query)
    local out = {}
    local rows = query("SELECT DISTINCT strftime('%Y', start_time, " .. LOCAL .. ") AS y "
        .. "FROM page_stat_data WHERE start_time > 0 ORDER BY y DESC")
    for _, r in ipairs(rows) do
        local y = tonumber(r[1])
        if y then table.insert(out, y) end
    end
    return out
end

local function totals(query, year)
    local r = query("SELECT COALESCE(SUM(duration), 0), "
        .. "COUNT(DISTINCT id_book || ':' || page), "
        .. "COUNT(DISTINCT id_book), "
        .. "COUNT(DISTINCT date(start_time, " .. LOCAL .. ")) "
        .. "FROM page_stat_data WHERE " .. yearFilter(year))[1] or {}
    return { seconds = n(r[1]), pages = n(r[2]), books = n(r[3]), days = n(r[4]) }
end

local function buckets(query, year, fmt, size, offset)
    local out = {}
    for i = 1, size do out[i] = 0 end
    local rows = query("SELECT strftime('" .. fmt .. "', start_time, " .. LOCAL .. ") AS k, SUM(duration) "
        .. "FROM page_stat_data WHERE " .. yearFilter(year) .. " GROUP BY k")
    for _, r in ipairs(rows) do
        local idx = n(r[1]) + offset
        if out[idx] then out[idx] = out[idx] + n(r[2]) end
    end
    return out
end

local function argmax(t)
    local best, best_i = -1, nil
    for i, v in ipairs(t) do
        if v > best then best, best_i = v, i end
    end
    return best_i, best
end

local function days(query, year)
    local rows = query("SELECT date(start_time, " .. LOCAL .. ") AS d, "
        .. "CAST(julianday(date(start_time, " .. LOCAL .. ")) AS INTEGER), SUM(duration) "
        .. "FROM page_stat_data WHERE " .. yearFilter(year) .. " GROUP BY d ORDER BY d")
    local streak = { days = 0 }
    local best_day = { seconds = 0 }
    local cur, cur_start, prev = 0, nil, nil
    for _, r in ipairs(rows) do
        local jd = n(r[2])
        if prev and jd == prev + 1 then
            cur = cur + 1
        else
            cur, cur_start = 1, r[1]
        end
        if cur > streak.days then
            streak = { days = cur, from = cur_start, to = r[1] }
        end
        prev = jd
        if n(r[3]) > best_day.seconds then
            best_day = { date = r[1], seconds = n(r[3]) }
        end
    end
    return streak, best_day
end

-- A book counts as finished once its last page was read that year and the
-- reader spent at least this long in it that year (skips books merely opened
-- at the end).
Stats.MIN_FINISH_SECONDS = 600

local function books(query, year)
    local rows = query("SELECT p.id_book, b.title, b.authors, SUM(p.duration), COUNT(DISTINCT p.page) "
        .. "FROM page_stat_data p LEFT JOIN book b ON b.id = p.id_book "
        .. "WHERE " .. yearFilter(year, "p.start_time") .. " "
        .. "GROUP BY p.id_book ORDER BY SUM(p.duration) DESC")
    local list, by_id = {}, {}
    for _, r in ipairs(rows) do
        local title = r[2]
        if title == nil or title == "" then title = "Untitled" end
        local authors = r[3]
        if authors == "N/A" then authors = nil end
        local b = { id = n(r[1]), title = title, authors = authors, seconds = n(r[4]), pages = n(r[5]) }
        table.insert(list, b)
        by_id[b.id] = b
    end

    local ends = query("SELECT id_book, MIN(date(start_time, " .. LOCAL .. ")) "
        .. "FROM page_stat_data WHERE " .. yearFilter(year) .. " "
        .. "AND total_pages > 0 AND page >= total_pages - 1 GROUP BY id_book")
    local finished = {}
    for _, r in ipairs(ends) do
        local b = by_id[n(r[1])]
        if b and b.seconds >= Stats.MIN_FINISH_SECONDS then
            b.finished_on = r[2]
            table.insert(finished, b)
        end
    end
    table.sort(finished, function(a, b) return a.finished_on < b.finished_on end)
    return list, finished
end

-- Hour of the day (0-23) -> reader type.
local PERSONAS = {
    { key = "early_bird", from = 5, to = 11 },
    { key = "afternoon", from = 12, to = 16 },
    { key = "evening", from = 17, to = 21 },
    { key = "night_owl", from = 22, to = 28 }, -- wraps to 4am
}

local function persona(hours)
    local best_key, best = nil, -1
    for _, p in ipairs(PERSONAS) do
        local sum = 0
        for h = p.from, p.to do
            sum = sum + hours[(h % 24) + 1]
        end
        if sum > best then best_key, best = p.key, sum end
    end
    return best_key
end

--- Everything the recap shows for `year`.
function Stats.collect(query, year)
    year = tonumber(year)
    local t = totals(query, year)
    local s = {
        year = year,
        seconds = t.seconds,
        pages = t.pages,
        book_count = t.books,
        days = t.days,
        prev_seconds = totals(query, year - 1).seconds,
    }
    if t.seconds <= 0 then
        s.empty = true
        return s
    end
    s.months = buckets(query, year, "%m", 12, 0)            -- 1..12
    s.weekdays = buckets(query, year, "%w", 7, 1)           -- 1 = Sunday
    s.hours = buckets(query, year, "%H", 24, 1)             -- 1 = midnight
    s.top_month = argmax(s.months)
    s.top_weekday = argmax(s.weekdays)
    s.top_hour = argmax(s.hours) - 1
    s.persona = persona(s.hours)
    s.streak, s.best_day = days(query, year)
    s.books, s.finished = books(query, year)
    return s
end

return Stats
