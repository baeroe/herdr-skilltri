# skilltri as a popup over the shell (ctrl+b p in the demo config, alt+shift+m in the README).
Output ".vhs/popup.gif"
Source "docs/tapes/config.tape"

Hide
Type '"$HERDR_DEMO" herdr' Enter
Sleep 4s
Type "clear; ls" Enter
Sleep 1s
Ctrl+B
Type "p"
Sleep 3s
Down 4
Sleep 1.5s
Show
Sleep 300ms
Screenshot "docs/screenshots/popup.png"
Sleep 500ms
