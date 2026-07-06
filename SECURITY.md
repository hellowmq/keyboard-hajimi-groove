# Security

Keyboard Hajimi Groove runs locally and requests macOS accessibility/input monitoring permissions to observe shortcut events.

Please report security issues privately rather than opening a public issue if they involve:

- unexpected keyboard event capture beyond configured shortcuts
- unsafe handling of local audio file paths
- arbitrary command execution in the segment editing server

The local segment editor binds to `127.0.0.1` by default and should not be exposed to a public network.
