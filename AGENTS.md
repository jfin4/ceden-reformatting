<!-- author: John.Inman@waterboards.ca.gov with AI coding agent
model: deepseek/deepseek-v4-flash
date updated: 2026-09-09 -->

# Metadata Header Rule

Every file created or updated by the agent must have this header
prepended (or after shebang, if present):

```
<comment-chars> author: John.Inman@waterboards.ca.gov with AI coding agent
<comment-chars> model: <model>
<comment-chars> date updated: <YYYY-MM-DD>
```

- **model**: `PI_MODEL` env var, provider prefix stripped
  (e.g., `deepseek/deepseek-v4-flash`)
- **date**: current UTC date (updated whenever the file is
  modified)
- **comment chars**:
    - `#` for Python, R, shell, YAML, text, CSV
    - `--` for SQL
    - `<!-- -->` for markdown, HTML
- **on update**:
    - update `date updated:` in place
    - keep `author:` and `model:` as-is
    - prepend if missing
- **binary/JSON**: skip gracefully

# Tools

- **apt-get** – install missing Debian packages as needed. Run
  `sudo apt-get update` first if the package index is stale.

# Style Guides

In general, follow the applicable Google style guide per language:

- **Shell** — [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
    - 2-space indent
    - `[[ ]]` over `[ ]`
    - `readonly` constants
    - `snake_case` vars
    - `set -euo pipefail`
    - `trap ... EXIT` cleanup
    - no `function` keyword
    - pass `shellcheck` cleanly
- **Python** — [Google Python Style Guide](https://google.github.io/styleguide/pyguide.html)
- **R** — [tidyverse style guide](https://style.tidyverse.org/)
    - `data.table::fread`/`fwrite` for I/O
    - tidyverse (dplyr, tidyr, stringr) for manipulation
    - silent scripts (no `cat()`, `print()`, `message()`) unless instructed
    - `\(x)` compact lambdas, not `~ .x` shortcuts
    - `fs` for file system operations (`dir_create`,
      `file_exists`, `file_copy`, `path`, `path_file`)
    - `purrr` over base R loops: `map_*` for transformations,
      `walk`/`walk2` for side effects, `map_dfr` for row-binding
- **JS/TS** — [Google TypeScript Style Guide](https://google.github.io/styleguide/tsguide.html)
- **SQL** — Uppercase keywords
    - 2-space indent
- **CSS/HTML** — [Google HTML/CSS Style Guide](https://google.github.io/styleguide/htmlcssguide.html)
