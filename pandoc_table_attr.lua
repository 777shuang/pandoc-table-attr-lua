-- Pandoc Lua filter: table attributes in captions.
--
-- Example:
--   Table: Caption text. {#id .class key=value}
--
-- Attributes at the end of a table caption are moved to the Table's Attr.
-- Run with: pandoc input.md --lua-filter=pandoc_table_attr.lua

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Split an attribute list into tokens, respecting single/double quoted values.
local function tokenize(s)
  local tokens = {}
  local i, n = 1, #s

  while i <= n do
    while i <= n and s:sub(i, i):match("%s") do
      i = i + 1
    end
    if i > n then break end

    local start = i
    local quote = nil
    while i <= n do
      local ch = s:sub(i, i)
      if quote then
        if ch == quote then quote = nil end
      elseif ch == "'" or ch == '"' then
        quote = ch
      elseif ch:match("%s") then
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
  local tokens = tokenize(s)
  if not tokens or #tokens == 0 then return nil end

  local identifier = ""
  local classes = {}
  local attributes = {}
  local seen_identifier = false

  for _, token in ipairs(tokens) do
    if token:sub(1, 1) == "#" then
      local id = token:sub(2)
      if seen_identifier or not id:match("^[A-Za-z][A-Za-z0-9_:%.-]*$") then
        return nil
      end
      identifier = id
      seen_identifier = true
    elseif token:sub(1, 1) == "." then
      local class = token:sub(2)
      if not class:match("^[_A-Za-z][_A-Za-z0-9-]*$") then return nil end
      classes[#classes + 1] = class
    else
      local key, value = token:match("^([_a-z][_a-z0-9%.%-]*)=(.*)$")
      if not key or value == "" then return nil end

      local first = value:sub(1, 1)
      local last = value:sub(-1)
      if first == '"' or first == "'" then
        if #value < 2 or last ~= first then return nil end
        value = value:sub(2, -2)
      elseif value:find("[\"'={}]", 1) then
        return nil
      end
      attributes[#attributes + 1] = { key, value }
    end
  end

  return pandoc.Attr(identifier, classes, attributes)
end

-- Find a trailing {...} attribute list and return the clean caption and Attr.
local function extract_caption_attributes(text)
  local start = nil
  -- Captions can contain braces as ordinary text. Only consider a final
  -- brace pair whose contents parse completely as an attribute list.
  for i = #text, 1, -1 do
    if text:sub(i, i) == "{" then
      start = i
      break
    end
  end
  if not start then return nil end

  local before = text:sub(1, start - 1)
  local body = text:sub(start + 1, -2)
  if text:sub(-1) ~= "}" or body == "" then return nil end

  local attr = parse_attributes(body)
  if not attr then return nil end
  if before ~= "" and not before:sub(-1):match("%s") then return nil end

  return trim(before), attr
end

local function caption_inlines(table)
  local caption = table.caption
  if not caption or not caption.long or #caption.long == 0 then return nil end

  -- Markdown table captions are normally represented by one Plain block.
  -- Support Para as well, while leaving multi-block captions unchanged.
  if #caption.long ~= 1 then return nil end
  local block = caption.long[1]
  if not (block.t == "Plain" or block.t == "Para") then return nil end
  return block.content, block.t
end

function PandocTableAttr(table)
  local inlines, block_type = caption_inlines(table)
  if not inlines then return nil end

  local text = pandoc.utils.stringify(inlines)
  local clean_text, attr = extract_caption_attributes(text)
  if not attr then return nil end

  -- Reparse the cleaned caption as Markdown so formatting in the caption
  -- remains meaningful. Attribute values themselves are plain strings.
  local parsed = pandoc.read(clean_text, "markdown")
  local clean_inlines = pandoc.List()
  if #parsed.blocks > 0 then
    local first = parsed.blocks[1]
    if first.t == "Plain" or first.t == "Para" then
      clean_inlines = first.content
    end
  end

  table.attr = attr
  if #clean_inlines == 0 then
    table.caption.long = pandoc.List()
  else
    table.caption.long = pandoc.List({ pandoc[block_type](clean_inlines) })
  end
  return table
end

return {
  { Table = PandocTableAttr }
}
