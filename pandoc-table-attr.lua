-- Pandoc Lua filter: allow table attributes at the end of table captions.
--
-- Example:
--   Table: Caption text. {#id .class key=value}
--
-- Usage:
--   pandoc --lua-filter=pandoc-table-attr.lua input.md -o output.html

local function tokenize_attributes(s)
  local tokens = {}
  local i = 1

  while i <= #s do
    while i <= #s and s:sub(i, i):match("%s") do
      i = i + 1
    end
    if i > #s then break end

    local start = i
    local quote = nil
    while i <= #s do
      local c = s:sub(i, i)
      if quote then
        if c == quote then quote = nil end
      elseif c == '"' or c == "'" then
        quote = c
      elseif c:match("%s") then
        break
      end
      i = i + 1
    end
    if quote then return nil end
    tokens[#tokens + 1] = s:sub(start, i - 1)
  end

  return tokens
end

local function parse_attributes(s)
  local tokens = tokenize_attributes(s)
  if not tokens then return nil end

  local identifier = ""
  local classes = pandoc.List()
  local attributes = {}
  local i = 1

  while i <= #tokens do
    local token = tokens[i]

    if token:match("^#[A-Za-z][A-Za-z0-9_:%.-]*$") then
      if identifier ~= "" then return nil end
      identifier = token:sub(2)
      i = i + 1
    elseif token:match("^%.[_A-Za-z][_A-Za-z0-9%-]*$") then
      classes:insert(token:sub(2))
      i = i + 1
    else
      local key, value = token:match("^([_a-z][_a-z0-9%.%-]*)=(.*)$")

      if not key then
        key = token:match("^([_a-z][_a-z0-9%.%-]*)$")
        if not key then return nil end
        i = i + 1
        if tokens[i] == "=" then
          i = i + 1
          value = tokens[i]
        elseif tokens[i] and tokens[i]:sub(1, 1) == "=" then
          value = tokens[i]:sub(2)
          if value == "" then
            i = i + 1
            value = tokens[i]
          end
        else
          return nil
        end
      else
        i = i + 1
        if value == "" then
          value = tokens[i]
          i = i + 1
        end
      end

      if not value then return nil end
      local first = value:sub(1, 1)
      if first == '"' or first == "'" then
        if #value < 2 or value:sub(-1) ~= first then return nil end
        value = value:sub(2, -2)
      elseif value:find("[\"'{}]") then
        return nil
      end
      attributes[key] = value
      i = i + 1
    end
  end

  if identifier == "" and #classes == 0 and next(attributes) == nil then
    return nil
  end
  return pandoc.Attr(identifier, classes, attributes)
end

local function trim_inlines(inlines, length)
  local result = pandoc.Inlines()
  local remaining = length

  for _, inline in ipairs(inlines) do
    if remaining <= 0 then break end

    local text = pandoc.utils.stringify(inline)
    if #text <= remaining then
      result:insert(inline)
      remaining = remaining - #text
    elseif inline.t == "Str" then
      local prefix = inline.text:sub(1, remaining)
      if prefix ~= "" then result:insert(pandoc.Str(prefix)) end
      remaining = 0
    else
      -- The attribute suffix should normally consist of plain text nodes.
      -- If it cuts through a non-text inline, leave the caption unchanged.
      return nil
    end
  end

  return result
end

function Table(tbl)
  local blocks = tbl.caption.long
  if #blocks == 0 then return nil end

  local last = blocks[#blocks]
  if last.t ~= "Para" and last.t ~= "Plain" then return nil end

  local inlines = last.content
  local text = pandoc.utils.stringify(inlines)
  local trimmed = text:gsub("%s+$", "")
  local open = nil
  local pos = 1

  -- Try each opening brace from right to left. Only a valid attribute list
  -- at the end of the caption is accepted.
  while true do
    local found = text:find("{", pos, true)
    if not found then break end
    open = found
    pos = found + 1
  end
  if not open then return nil end

  local prefix = text:sub(1, open - 1)
  local whitespace_prefix = prefix:match("^(.*)%s$")
  if open > 1 and not whitespace_prefix then return nil end

  local attr_text = trimmed:sub(open + 1)
  if trimmed:sub(-1) ~= "}" then return nil end
  local attr = parse_attributes(attr_text:sub(1, -2))
  if not attr then return nil end

  local caption_end = open - 1
  while caption_end > 0 and text:sub(caption_end, caption_end):match("%s") do
    caption_end = caption_end - 1
  end

  local new_inlines = trim_inlines(inlines, caption_end)
  if not new_inlines then return nil end

  if #new_inlines == 0 then
    table.remove(blocks, #blocks)
  else
    last.content = new_inlines
  end
  tbl.caption.long = blocks
  tbl.attr = attr
  return tbl
end

return { Table = Table }
