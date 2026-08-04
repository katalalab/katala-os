---
name: markdown-converter
description: Convert documents between formats — Markdown ↔ HTML, PDF, DOCX, plain text. Also cleans web-clipped markdown (removes navigation, ads, boilerplate) using defuddle or pandoc. Use when the operator needs a format conversion or a clean readable version of a document.
---

# markdown-converter — document format conversion

Converts documents using available local tools (pandoc, defuddle, python-markdown).

## When to use

- "このMarkdownをHTMLに変換して"
- "PDFをMarkdownに変換して"
- "このページのボイラープレートを取り除いてMarkdownにして"
- "DOCXをMarkdownに変換して"

Do **not** use for:
- Editing document content (use the appropriate editor)
- Translating language (use a translation tool)

## Tool selection

| From → To | Tool |
|-----------|------|
| HTML → MD | defuddle or pandoc |
| MD → HTML | pandoc or python-markdown |
| MD → PDF | pandoc + wkhtmltopdf or weasyprint |
| MD → DOCX | pandoc |
| DOCX → MD | pandoc |
| Web URL → clean MD | `/defuddle` skill or `curl | pandoc` |

## Common invocations

```bash
# Web page to clean Markdown
curl -s <url> | pandoc -f html -t markdown --no-highlight -o output.md

# Markdown to PDF (requires pandoc + wkhtmltopdf)
pandoc input.md -o output.pdf --pdf-engine=wkhtmltopdf

# Markdown to DOCX
pandoc input.md -o output.docx

# DOCX to Markdown
pandoc input.docx -o output.md --extract-media=./media

# Clean up web-clipped markdown with defuddle
# (use /defuddle skill for this)
```

## Hard-rule reminders

- Always check if source file exists before converting.
- Office files (DOCX, XLSX, PPTX) must be copied before editing per the Editing Policy.
- Confirm output path with operator if the target file already exists.
