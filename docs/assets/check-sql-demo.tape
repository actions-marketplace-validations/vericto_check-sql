# Demo GIF for the README / Marketplace listing: `vericto check --offline` on
# two small migrations. Only the typing is scripted; the output is whatever
# the real CLI prints.
#
# Re-record from the repository root, with the CLI release that action.yml
# pins by default (`# pinned-cli-version`) first on PATH as `vericto`:
#
#   vericto --version   # must print the pinned version
#   vhs docs/assets/check-sql-demo.tape
#
# Keep the GIF under about 1.5 MB, 800 px wide or less, 10-15 s long.

Output docs/assets/check-sql-demo.gif

Require vericto

Set Shell "bash"
Set FontSize 13
Set Width 800
Set Height 600
Set Padding 18
Set LineHeight 1.15
Set Framerate 10
Set TypingSpeed 35ms
Set CursorBlink false
Set WindowBar ""
Set Theme { "name": "Vericto", "background": "#0A0F1E", "foreground": "#F1F5F9", "cursor": "#00D4FF", "selection": "#1E293B", "black": "#0A0F1E", "red": "#F87171", "green": "#34D399", "yellow": "#FBBF24", "blue": "#60A5FA", "magenta": "#C084FC", "cyan": "#00D4FF", "white": "#F1F5F9", "brightBlack": "#64748B", "brightRed": "#FCA5A5", "brightGreen": "#6EE7B7", "brightYellow": "#FDE68A", "brightBlue": "#93C5FD", "brightMagenta": "#D8B4FE", "brightCyan": "#67E8F9", "brightWhite": "#FFFFFF" }

# Setup, not recorded: a scratch directory with two migrations.
Hide
Type `export PS1='$ ' && unset NO_COLOR && d=$(mktemp -d) && cd "$d" && mkdir migrations`
Enter
Type `printf -- '-- Clear expired sessions\nDELETE FROM sessions;\n' > migrations/0042_cleanup.sql`
Enter
Type `printf -- '-- Remove the old users table\nDROP TABLE legacy_users;\n' > migrations/0043_drop_legacy.sql`
Enter
Type "clear"
Enter
Sleep 300ms
Show

Type "grep -n '' migrations/*.sql"
Sleep 300ms
Enter
Sleep 1.8s

Type "vericto check --offline migrations/*.sql"
Sleep 400ms
Enter
Sleep 7s

# Cleanup, not recorded.
Hide
Type `cd / && rm -rf "$d"`
Enter
