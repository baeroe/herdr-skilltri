# skilltri in a split next to a shell in ~/dev/acme-shop (ctrl+b m in the demo config, alt+m in the README).
# The Preview tab starts in the folder of the shell pane.
Output ".vhs/split.gif"
Source "docs/tapes/config.tape"

Hide
Type '"$HERDR_DEMO" herdr' Enter
Sleep 4s
Type "clear; git status -sb; ls" Enter
Sleep 1s
Ctrl+B
Type "m"
Sleep 3s
Type "3"
Sleep 1.5s
Show
Sleep 300ms
Screenshot "docs/screenshots/split.png"
Sleep 500ms
