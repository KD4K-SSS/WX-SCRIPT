# KD4K AIM Macro Window

This is a native Windows Forms utility for NetLogger AIM. It provides programmable macro buttons, a message box, and a `Send to AIM` button.

## Build the executable on Windows

Install the .NET 10 SDK, then run from the repository root:

```powershell
dotnet publish Macro\MacroWindow.csproj -c Release -r win-x64 --self-contained true
```

The executable is written to:

```text
Macro\bin\Release\net10.0-windows\win-x64\publish\MacroWindow.exe
```

Start NetLogger AIM before using `Send to AIM`. The current bridge finds a top-level window whose title contains `AIM`, then looks for a standard edit control and a button whose text contains `Send`.

Macro definitions are saved per Windows user under `%APPDATA%\KD4K\macros.json`.
