--[[
Turns the table from yip_stats into an HTML book: one "card" per page.
KOReader opens it like any other book, so the recap pages turn with the
usual taps and swipes, and the same file reads fine in a web browser.
Pure Lua, no KOReader modules.
]]

local Render = {}

local MONTHS = { "January", "February", "March", "April", "May", "June", "July",
    "August", "September", "October", "November", "December" }
local WEEKDAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }

local PERSONAS = {
    early_bird = { "Early Bird", "Most of your pages were turned before noon." },
    afternoon = { "Afternoon Reader", "You did most of your reading between lunch and dinner." },
    evening = { "Evening Reader", "Evenings were your reading time." },
    night_owl = { "Night Owl", "Your best reading happened after 10 pm." },
}

local function esc(s)
    s = tostring(s or "")
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end
Render.esc = esc

local function round(x)
    return math.floor(x + 0.5)
end

local function int(v)
    local s = tostring(math.floor(v))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end
Render.int = int

local function plural(count, one, many)
    return int(count) .. " " .. (count == 1 and one or many)
end

local function duration(secs)
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then
        if m > 0 then return string.format("%s h %d min", int(h), m) end
        return int(h) .. " h"
    end
    return string.format("%d min", math.max(m, 1))
end
Render.duration = duration

local function day(date)
    local y, mo, d = tostring(date or ""):match("^(%d+)-(%d+)-(%d+)$")
    if not y then return esc(date) end
    return MONTHS[tonumber(mo)] .. " " .. tonumber(d)
end
Render.day = day

local function hour12(h)
    local suffix = h < 12 and "am" or "pm"
    local hh = h % 12
    if hh == 0 then hh = 12 end
    return hh .. " " .. suffix
end

local CSS = [[
body { font-family: serif; margin: 0; }
.card { page-break-before: always; text-align: center; padding: 8% 6% 0 6%; }
.card.first { page-break-before: avoid; }
.kicker { font-size: 0.9em; letter-spacing: 0.15em; text-transform: uppercase; margin: 0 0 1.5em 0; }
.big { font-size: 4em; font-weight: bold; line-height: 1.1; margin: 0.2em 0; }
.mid { font-size: 1.8em; font-weight: bold; margin: 0.3em 0; }
.say { font-size: 1.15em; margin: 0.6em 0; }
.small { font-size: 0.85em; margin-top: 2em; }
table.list { margin: 1.2em auto 0 auto; border-collapse: collapse; text-align: left; }
table.list td { padding: 0.25em 0.5em; vertical-align: top; }
td.num { text-align: right; white-space: nowrap; }
td.who { font-size: 0.85em; }
table.bars { width: 100%; border-collapse: collapse; margin-top: 1em; }
table.bars td { padding: 0.12em 0.3em; font-size: 0.9em; }
td.label { width: 3em; text-align: left; }
td.bar { width: 75%; }
div.fill { height: 0.8em; background-color: #000; }
td.val { text-align: right; white-space: nowrap; }
]]

local function card(parts, first)
    return '<div class="card' .. (first and " first" or "") .. '">\n' .. table.concat(parts, "\n") .. "\n</div>\n"
end

local function p(class, html)
    return '<p class="' .. class .. '">' .. html .. "</p>"
end

local function h(title)
    return '<h2 class="kicker">' .. esc(title) .. "</h2>"
end

local function bookRows(list, limit, valueFn)
    local rows = { '<table class="list">' }
    for i = 1, math.min(#list, limit) do
        local b = list[i]
        local who = b.authors and ('<br/><span class="who">' .. esc(b.authors) .. "</span>") or ""
        table.insert(rows, string.format('<tr><td class="num">%d.</td><td><b>%s</b>%s</td><td class="num">%s</td></tr>',
            i, esc(b.title), who, valueFn(b)))
    end
    table.insert(rows, "</table>")
    return table.concat(rows, "\n")
end

local function changeLine(s)
    if not s.prev_seconds or s.prev_seconds <= 0 then return nil end
    local pct = round((s.seconds - s.prev_seconds) / s.prev_seconds * 100)
    if pct > 0 then
        return p("say", string.format("That is %d%% more than in %d.", pct, s.year - 1))
    elseif pct < 0 then
        return p("say", string.format("That is %d%% less than in %d.", -pct, s.year - 1))
    end
    return p("say", string.format("Exactly as much as in %d.", s.year - 1))
end

function Render.html(s)
    local title = "Your " .. s.year .. " in Pages"
    local out = {
        '<?xml version="1.0" encoding="UTF-8"?>',
        "<!DOCTYPE html>",
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><meta charset="UTF-8"/>',
        "<title>" .. esc(title) .. "</title>",
        "<style>" .. CSS .. "</style></head><body>",
    }
    local function add(parts, first) table.insert(out, card(parts, first)) end

    if s.empty then
        add({
            h("Year in Pages"),
            p("mid", "No reading recorded in " .. s.year),
            p("say", "Turn on KOReader's Reading statistics plugin and your next recap will fill itself in."),
        }, true)
        table.insert(out, "</body></html>")
        return table.concat(out, "\n")
    end

    local hours = s.seconds / 3600

    -- 1. Cover
    add({
        p("kicker", "Year in Pages"),
        '<h1 class="big">' .. s.year .. "</h1>",
        p("mid", "Your year in reading"),
        p("say", "Turn the page."),
    }, true)

    -- 2. Time
    local time = {
        h("Time well spent"),
        p("big", int(round(hours))),
        p("mid", round(hours) == 1 and "hour of reading" or "hours of reading"),
        p("say", "spread over " .. plural(s.days, "day", "days") .. "."),
    }
    local change = changeLine(s)
    if change then table.insert(time, change) end
    if hours >= 4 then
        table.insert(time, p("small", "That is about " .. plural(round(hours / 2), "film", "films") .. " worth of time."))
    end
    add(time)

    -- 3. Pages
    local cm = s.pages * 0.005 -- two pages per sheet, ~0.1 mm per sheet
    local pages = {
        h("Page after page"),
        p("big", int(s.pages)),
        p("mid", s.pages == 1 and "page" or "pages"),
        p("say", "across " .. plural(s.book_count, "book", "books") .. "."),
    }
    if cm >= 1 then
        table.insert(pages, p("small", string.format("Printed, that stack would stand about %s cm tall.", int(round(cm)))))
    end
    add(pages)

    -- 4. Finished
    if #s.finished > 0 then
        add({
            h("Finished"),
            p("big", int(#s.finished)),
            p("mid", #s.finished == 1 and "book read to the end" or "books read to the end"),
            bookRows(s.finished, 15, function(b) return day(b.finished_on) end),
        })
    end

    -- 5. Favourites
    if #s.books > 0 then
        local top = s.books[1]
        add({
            h("Your top books"),
            p("say", "You spent the most time with"),
            p("mid", esc(top.title)),
            top.authors and p("say", "by " .. esc(top.authors)) or "",
            bookRows(s.books, 5, function(b) return duration(b.seconds) end),
        })
    end

    -- 6. Months
    local maxm = 0
    for _, v in ipairs(s.months) do if v > maxm then maxm = v end end
    local bars = { '<table class="bars">' }
    for i, v in ipairs(s.months) do
        local width = maxm > 0 and round(v / maxm * 100) or 0
        local fill = width > 0 and string.format('<div class="fill" style="width:%d%%"></div>', width) or ""
        table.insert(bars, string.format('<tr><td class="label">%s</td><td class="bar">%s</td><td class="val">%s</td></tr>',
            MONTHS[i]:sub(1, 3), fill, v > 0 and duration(v) or ""))
    end
    table.insert(bars, "</table>")
    add({
        h("Month by month"),
        p("say", "Your biggest month was"),
        p("mid", MONTHS[s.top_month]),
        table.concat(bars, "\n"),
    })

    -- 7. Reader type
    local persona = PERSONAS[s.persona] or PERSONAS.evening
    add({
        h("What kind of reader"),
        p("say", "Your reader type"),
        p("big", persona[1]),
        p("say", persona[2]),
        p("small", "Favourite day: <b>" .. WEEKDAYS[s.top_weekday] .. "</b> · Busiest hour: <b>" .. hour12(s.top_hour) .. "</b>"),
    })

    -- 8. Streak and best day
    local streak = {
        h("On a roll"),
        p("say", "Your longest streak"),
        p("big", int(s.streak.days)),
        p("mid", s.streak.days == 1 and "day" or "days in a row"),
    }
    if s.streak.days > 1 then
        table.insert(streak, p("say", day(s.streak.from) .. " to " .. day(s.streak.to)))
    end
    if s.best_day.date then
        table.insert(streak, p("small", "Your biggest day was <b>" .. day(s.best_day.date) .. "</b>, with "
            .. duration(s.best_day.seconds) .. " of reading."))
    end
    add(streak)

    -- 9. Closing
    add({
        h("That was " .. s.year),
        p("mid", int(round(hours)) .. " h · " .. int(s.pages) .. " pages · " .. plural(#s.finished, "book", "books") .. " finished"),
        p("say", "See you in " .. (s.year + 1) .. "."),
        p("small", "Made with Year in Pages for KOReader."),
    })

    table.insert(out, "</body></html>")
    return table.concat(out, "\n")
end

return Render
