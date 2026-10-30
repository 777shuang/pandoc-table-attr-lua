# pandoc-table-attr-lua

A [Pandoc](https://pandoc.org/) Lua filter that allows table attributes to be specified at the end of a table caption in Pandoc Markdown.

## Usage

Given this Markdown:

```markdown
Table: Table caption. {#id .class key=value}

FirstCol   SecondCol
---------  ----------
FirstCell  SecondCell
```

Run Pandoc with the filter:

```sh
pandoc input.md --lua-filter=pandoc_table_attr.lua -o output.html
```

The filter removes `{#id .class key=value}` from the caption and assigns the parsed identifier, classes, and key-value attributes to the table. The attributes can then be used by Pandoc writers.

Attributes must appear at the end of the caption. Identifiers, classes, and key-value pairs follow Pandoc's usual attribute syntax; quoted values may contain spaces.

## Limitations

- The filter currently handles captions represented by a single `Plain` or `Para` block.
- The caption is stringified and reparsed as Markdown after removing the attribute list. This preserves ordinary Markdown formatting, but may not preserve every unusual inline AST structure exactly.
- As with Pandoc's Markdown parser, formatting syntax inside an attribute value may be interpreted as inline formatting before the filter sees it. Escape such characters where necessary.
