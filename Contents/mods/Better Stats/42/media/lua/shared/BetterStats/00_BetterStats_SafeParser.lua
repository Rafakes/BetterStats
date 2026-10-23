-- 00_BetterStats_SafeParser.lua
--
-- PZ 42.20.4 / 42.19.2 / 41.78.21 removed loadstring/loadstream entirely
-- ("Fixed security vulnerabilities... the loadstring and loadstream methods
-- have been removed"). BetterStats.loadStateFromFile used to compile and
-- execute the saved state file (written by serializeValue in
-- 00_BetterStats_Shared.lua) as raw Lua text via loadstring; that is no
-- longer possible on any engine version. This parses it as DATA instead --
-- it never calls load/loadstring/dofile and never executes arbitrary code.
--
-- serializeValue only ever emits: nil, numbers, booleans, %q-quoted strings,
-- and nested table constructors (bare-identifier keys or bracket [key]=value
-- keys for non-identifier/non-string keys such as numeric history days).
-- That is exactly the grammar this parser supports -- no function calls, no
-- local declarations, nothing executable.

BetterStats = BetterStats or {}

local KEYWORDS = {
    ["nil"] = true, ["true"] = true, ["false"] = true, ["or"] = true, ["and"] = true, ["return"] = true,
}

local PUNCT_CHARS = {
    ["{"] = true, ["}"] = true, [","] = true, ["="] = true, ["["] = true, ["]"] = true, [";"] = true,
}

local ESCAPE_MAP = {
    n = "\n", t = "\t", r = "\r", a = "\a", b = "\b", f = "\f", v = "\v",
    ["\\"] = "\\", ['"'] = '"', ["'"] = "'",
}

local function isDigit(c) return c ~= nil and c ~= "" and c >= "0" and c <= "9" end
local function isAlpha(c)
    return c ~= nil and c ~= "" and ((c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_")
end
local function isAlnum(c) return isAlpha(c) or isDigit(c) end

local function tokenize(text)
    local tokens = {}
    local i, n, line = 1, #text, 1

    local function peek(o)
        local idx = i + (o or 0)
        if idx > n then return "" end
        return text:sub(idx, idx)
    end

    local function advance()
        local c = text:sub(i, i)
        if c == "\n" then line = line + 1 end
        i = i + 1
        return c
    end

    local function fail(msg)
        error(string.format("line %d: %s", line, msg), 0)
    end

    while i <= n do
        local c = peek()

        if c == " " or c == "\t" or c == "\r" or c == "\n" then
            advance()

        elseif c == "-" and peek(1) == "-" then
            i = i + 2
            if peek() == "[" and peek(1) == "[" then
                i = i + 2
                local closeStart = text:find("]]", i, true)
                if not closeStart then fail("unterminated block comment") end
                i = closeStart + 2
            else
                while i <= n and text:sub(i, i) ~= "\n" do i = i + 1 end
            end

        elseif c == '"' or c == "'" then
            local quote = c
            advance()
            local buf = {}
            while true do
                local ch = peek()
                if ch == "" then fail("unterminated string") end
                if ch == quote then advance() break end
                if ch == "\\" then
                    advance()
                    local esc = peek()
                    if ESCAPE_MAP[esc] then
                        buf[#buf + 1] = ESCAPE_MAP[esc]
                        advance()
                    elseif isDigit(esc) then
                        local numStr, cnt = "", 0
                        while cnt < 3 and isDigit(peek()) do
                            numStr = numStr .. peek()
                            advance()
                            cnt = cnt + 1
                        end
                        buf[#buf + 1] = string.char(tonumber(numStr) % 256)
                    else
                        -- Covers Lua's "backslash + literal newline" escape too
                        -- (what %q emits for embedded newlines): esc is just
                        -- appended as-is, which is correct for that case.
                        buf[#buf + 1] = esc
                        advance()
                    end
                else
                    buf[#buf + 1] = ch
                    advance()
                end
            end
            tokens[#tokens + 1] = { type = "string", value = table.concat(buf), line = line }

        elseif isDigit(c) then
            local start = i
            while isDigit(peek()) do advance() end
            if peek() == "." and isDigit(peek(1)) then
                advance()
                while isDigit(peek()) do advance() end
            end
            if peek() == "e" or peek() == "E" then
                local save = i
                advance()
                if peek() == "+" or peek() == "-" then advance() end
                if isDigit(peek()) then
                    while isDigit(peek()) do advance() end
                else
                    i = save
                end
            end
            tokens[#tokens + 1] = { type = "number", value = tonumber(text:sub(start, i - 1)), line = line }

        elseif isAlpha(c) then
            local start = i
            while isAlnum(peek()) do advance() end
            local word = text:sub(start, i - 1)
            tokens[#tokens + 1] = { type = KEYWORDS[word] and "keyword" or "name", value = word, line = line }

        elseif PUNCT_CHARS[c] then
            advance()
            tokens[#tokens + 1] = { type = "punct", value = c, line = line }

        elseif c == "-" then
            advance()
            tokens[#tokens + 1] = { type = "punct", value = c, line = line }

        else
            fail("unexpected character '" .. c .. "'")
        end
    end

    tokens[#tokens + 1] = { type = "eof", value = "<eof>", line = line }
    return tokens
end

local function newCursor(tokens)
    local c = { tokens = tokens, pos = 1 }

    function c:cur() return self.tokens[self.pos] end
    function c:peekNext() return self.tokens[self.pos + 1] end
    function c:atEnd() return self:cur().type == "eof" end

    function c:fail(msg)
        local t = self:cur()
        error(string.format("line %s: %s (got %s '%s')", tostring(t.line), msg, t.type, tostring(t.value)), 0)
    end

    function c:advance()
        local t = self:cur()
        if t.type ~= "eof" then self.pos = self.pos + 1 end
        return t
    end

    function c:checkPunct(v)
        local t = self:cur()
        return t.type == "punct" and t.value == v
    end

    function c:checkKeyword(v)
        local t = self:cur()
        return t.type == "keyword" and t.value == v
    end

    function c:expectPunct(v)
        if not self:checkPunct(v) then self:fail("expected '" .. v .. "'") end
        return self:advance()
    end

    function c:expectKeyword(v)
        if not self:checkKeyword(v) then self:fail("expected '" .. v .. "'") end
        return self:advance()
    end

    return c
end

local parseExpr, parseTable

local function parsePrimary(c)
    if c:checkPunct("-") then
        c:advance()
        local t = c:cur()
        if t.type ~= "number" then c:fail("expected number after unary '-'") end
        c:advance()
        return { kind = "literal", value = -t.value }
    end

    local t = c:cur()
    if t.type == "string" then
        c:advance()
        return { kind = "literal", value = t.value }
    elseif t.type == "number" then
        c:advance()
        return { kind = "literal", value = t.value }
    elseif t.type == "keyword" and t.value == "nil" then
        c:advance()
        return { kind = "literal" }
    elseif t.type == "keyword" and t.value == "true" then
        c:advance()
        return { kind = "literal", value = true }
    elseif t.type == "keyword" and t.value == "false" then
        c:advance()
        return { kind = "literal", value = false }
    elseif t.type == "punct" and t.value == "{" then
        return parseTable(c)
    end
    c:fail("unexpected token in expression (only literals and tables are supported)")
end

parseExpr = function(c)
    local left = parsePrimary(c)
    while c:checkKeyword("or") or c:checkKeyword("and") do
        local op = c:advance().value
        local right = parsePrimary(c)
        left = { kind = "logic", op = op, left = left, right = right }
    end
    return left
end

parseTable = function(c)
    c:expectPunct("{")
    local fields = {}
    while not c:checkPunct("}") do
        local field
        if c:checkPunct("[") then
            c:advance()
            local keyExpr = parseExpr(c)
            c:expectPunct("]")
            c:expectPunct("=")
            field = { keyExpr = keyExpr, valExpr = parseExpr(c) }
        elseif c:cur().type == "name" and c:peekNext() and c:peekNext().type == "punct" and c:peekNext().value == "=" then
            local key = c:advance().value
            c:expectPunct("=")
            field = { key = key, valExpr = parseExpr(c) }
        else
            field = { valExpr = parseExpr(c) }
        end
        fields[#fields + 1] = field
        if c:checkPunct(",") or c:checkPunct(";") then
            c:advance()
        else
            break
        end
    end
    c:expectPunct("}")
    return { kind = "table", fields = fields }
end

local function evalExpr(node)
    local kind = node.kind
    if kind == "literal" then
        return node.value
    elseif kind == "logic" then
        local l = evalExpr(node.left)
        if node.op == "or" then
            if l then return l end
            return evalExpr(node.right)
        else
            if not l then return l end
            return evalExpr(node.right)
        end
    elseif kind == "table" then
        local t = {}
        local arrayIdx = 0
        for _, field in ipairs(node.fields) do
            if field.keyExpr then
                t[evalExpr(field.keyExpr)] = evalExpr(field.valExpr)
            elseif field.key then
                t[field.key] = evalExpr(field.valExpr)
            else
                arrayIdx = arrayIdx + 1
                t[arrayIdx] = evalExpr(field.valExpr)
            end
        end
        return t
    end
    error("internal parser error: unknown node kind '" .. tostring(kind) .. "'", 0)
end

-- Parses `text` (the contents of a BetterStats_*.txt state file) as data and
-- returns the resulting table. Returns (table) on success, or (nil,
-- errorMessage) on failure -- never executes anything.
function BetterStats.parseSafeLuaData(text)
    local ok, resultOrErr = pcall(function()
        local tokens = tokenize(text)
        local c = newCursor(tokens)
        c:expectKeyword("return")
        local rootExpr = parseTable(c)
        if not c:atEnd() then
            c:fail("unexpected content after the top-level return")
        end
        return evalExpr(rootExpr)
    end)

    if not ok then
        return nil, tostring(resultOrErr)
    end
    return resultOrErr
end
