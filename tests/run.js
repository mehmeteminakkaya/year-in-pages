// Off-device tests: runs the plugin's pure Lua modules in fengari (a Lua VM in
// JavaScript) against a real SQLite database with KOReader's statistics schema.
//   cd tests && npm install && npm test
const fs = require("fs");
const path = require("path");
const { DatabaseSync } = require("node:sqlite");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const PLUGIN = path.join(__dirname, "..", "yearinpages.koplugin");
const OUT = path.join(__dirname, "out");

// ---------- fixture database (KOReader statistics schema) ----------
function makeDb() {
  const db = new DatabaseSync(":memory:");
  db.exec(`
    CREATE TABLE book (id INTEGER PRIMARY KEY autoincrement, title TEXT, authors TEXT, notes INTEGER,
      last_open INTEGER, highlights INTEGER, pages INTEGER, series TEXT, language TEXT, md5 TEXT,
      total_read_time INTEGER, total_read_pages INTEGER);
    CREATE TABLE page_stat_data (id_book INTEGER, page INTEGER NOT NULL DEFAULT 0,
      start_time INTEGER NOT NULL DEFAULT 0, duration INTEGER NOT NULL DEFAULT 0,
      total_pages INTEGER NOT NULL DEFAULT 0, UNIQUE (id_book, page, start_time));
  `);
  const addBook = db.prepare("INSERT INTO book (id, title, authors) VALUES (?, ?, ?)");
  addBook.run(1, "Dune", "Frank Herbert");
  addBook.run(2, 'Tom & Jerry <"Special">', "N/A");
  addBook.run(3, "Last Year's Book", "Someone");
  addBook.run(4, "Peeked At The End", "Nobody");

  const page = db.prepare("INSERT INTO page_stat_data VALUES (?, ?, ?, ?, ?)");
  const t = (y, mo, d, h, mi = 0) => Math.floor(new Date(y, mo - 1, d, h, mi).getTime() / 1000);

  // Dune: 100 pages, read Mar 10-14 2026 (5-day streak) at 23:00, finished Mar 14.
  let pg = 1;
  for (let d = 10; d <= 14; d++) {
    for (let i = 0; i < 20; i++) page.run(1, pg++, t(2026, 3, d, 23, i), 120, 100);
  }
  // Book 2: 30 pages on Jun 1 and Jun 3 2026, 21:00 (not finished, total 300).
  for (let i = 0; i < 15; i++) page.run(2, i + 1, t(2026, 6, 1, 21, i), 60, 300);
  for (let i = 0; i < 15; i++) page.run(2, i + 16, t(2026, 6, 3, 21, i), 60, 300);
  // Book 4: only opened on its last page for a minute -> must NOT count as finished.
  page.run(4, 200, t(2026, 7, 1, 10), 60, 200);
  // Book 3: 2025 only, 10 pages x 360 s = 1 h.
  for (let i = 0; i < 10; i++) page.run(3, i + 1, t(2025, 5, 5, 8, i), 360, 50);
  return db;
}

function luaLiteral(v) {
  if (v === null || v === undefined) return "nil";
  if (typeof v === "number" || typeof v === "bigint") return String(v);
  return '"' + String(v).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n").replace(/\r/g, "\\r") + '"';
}

// ---------- Lua VM ----------
function newLua(db) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  // package.path -> plugin folder
  lauxlib.luaL_dostring(L, to_luastring(`package.path = ${luaLiteral(PLUGIN.replace(/\\/g, "/") + "/?.lua;")} .. package.path`));
  lua.lua_pushjsfunction(L, (L) => {
    const sql = lua.lua_tojsstring(L, 1);
    const rows = db.prepare(sql).all();
    const src = "return {" + rows.map((r) => "{" + Object.values(r).map(luaLiteral).join(",") + "}").join(",") + "}";
    lua.lua_pushstring(L, to_luastring(src));
    return 1;
  });
  lua.lua_setglobal(L, to_luastring("__js_query"));
  return L;
}

function runLua(L, code) {
  const status = lauxlib.luaL_dostring(L, to_luastring(code));
  if (status !== lua.LUA_OK) {
    throw new Error("Lua error: " + lua.lua_tojsstring(L, -1));
  }
  const out = lua.lua_tojsstring(L, -1);
  lua.lua_settop(L, 0);
  return out;
}

const PRELUDE = `
local Stats = require("yip_stats")
local Render = require("yip_render")
local query = function(sql) return load(__js_query(sql))() end
local fails = {}
local function eq(name, got, want)
  if got ~= want then table.insert(fails, name .. ": got " .. tostring(got) .. ", want " .. tostring(want)) end
end
local function has(name, s, needle)
  if not s:find(needle, 1, true) then table.insert(fails, name .. ": missing " .. needle) end
end
local function hasnt(name, s, needle)
  if s:find(needle, 1, true) then table.insert(fails, name .. ": should not contain " .. needle) end
end
`;

const TESTS = `
local years = Stats.years(query)
eq("years count", #years, 2)
eq("years newest first", years[1], 2026)

local s = Stats.collect(query, 2026)
eq("seconds", s.seconds, 100*120 + 30*60 + 60)
eq("pages", s.pages, 100 + 30 + 1)
eq("book_count", s.book_count, 3)
eq("days", s.days, 5 + 2 + 1)
eq("prev_seconds", s.prev_seconds, 3600)
eq("streak days", s.streak.days, 5)
eq("streak from", s.streak.from, "2026-03-10")
eq("streak to", s.streak.to, "2026-03-14")
eq("best day", s.best_day.seconds, 20*120)
eq("finished count", #s.finished, 1)
eq("finished title", s.finished[1].title, "Dune")
eq("finished on", s.finished[1].finished_on, "2026-03-14")
eq("top book", s.books[1].title, "Dune")
eq("authors N/A dropped", s.books[2].authors, nil)
eq("top month", s.top_month, 3)
eq("persona", s.persona, "night_owl")
eq("top hour", s.top_hour, 23)

local html = Render.html(s)
has("html title", html, "Your 2026 in Pages")
has("html escaped", html, "Tom &amp; Jerry &lt;&quot;Special&quot;&gt;")
hasnt("html raw tag", html, "<\\"Special\\">")
has("html persona", html, "Night Owl")
has("html change", html, "% more than in 2025")
has("html streak", html, "March 10 to March 14")
has("html month", html, "March")

local empty = Stats.collect(query, 2019)
eq("empty flag", empty.empty, true)
has("empty html", Render.html(empty), "No reading recorded in 2019")

local s25 = Stats.collect(query, 2025)
eq("2025 persona", s25.persona, "early_bird")
eq("2025 finished none", #s25.finished, 0)
local h25 = Render.html(s25)
hasnt("no change line without prev", h25, "than in 2024")

eq("int", Render.int(1234567), "1,234,567")
eq("int small", Render.int(12), "12")
eq("duration h", Render.duration(3*3600 + 5*60), "3 h 5 min")
eq("duration min", Render.duration(30), "1 min")
eq("day", Render.day("2026-12-01"), "December 1")

return #fails == 0 and "OK" or table.concat(fails, "\\n")
`;

// ---------- run ----------
let failed = false;

// 1. Every plugin file must parse.
for (const file of fs.readdirSync(PLUGIN).filter((f) => f.endsWith(".lua"))) {
  const L = lauxlib.luaL_newstate();
  const src = fs.readFileSync(path.join(PLUGIN, file));
  const status = lauxlib.luaL_loadbuffer(L, src, null, to_luastring(file));
  if (status !== lua.LUA_OK) {
    failed = true;
    console.log(`FAIL parse ${file}: ${lua.lua_tojsstring(L, -1)}`);
  } else {
    console.log(`ok   parse ${file}`);
  }
}

// 2. Stats + render against the fixture database.
const db = makeDb();
const L = newLua(db);
const result = runLua(L, PRELUDE + TESTS);
if (result === "OK") {
  console.log("ok   stats and render");
} else {
  failed = true;
  console.log("FAIL stats and render:\n" + result);
}

// 3. Write a sample recap to look at.
fs.mkdirSync(OUT, { recursive: true });
const html = runLua(newLua(db), PRELUDE + `return Render.html(Stats.collect(query, 2026))`);
fs.writeFileSync(path.join(OUT, "sample-2026.html"), html);
console.log("wrote tests/out/sample-2026.html");

process.exit(failed ? 1 : 0);
