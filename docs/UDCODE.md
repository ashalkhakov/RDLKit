# RDL in UDCode

RDLKit ships a [UDCode](https://github.com/ashalkhakov/UDCodeKit) extension,
RDL, which lets you edit Report Definition Language reports (`.rdl`,
`.rdlc`) inside UDCode as part of a project. The designer is RDLDesigner's
(RDLKitUI), with the canvas, the outline, datasets, data sources and
parameters, the inspectors, the row and column groups, the insert palette,
the preview, and PDF and HTML export. RDLDesigner remains its own app, built
on the same library.

## Installing it

Each RDLKit release attaches a package for each platform:

| UDCode on | Package |
|---|---|
| macOS, Apple silicon | `rdl-<version>-darwin-arm64.udcx` |
| macOS, Intel | `rdl-<version>-darwin-x64.udcx` |
| Linux (the AppImage), x86_64 | `rdl-<version>-linux-x64.udcx` |
| Linux, aarch64 | `rdl-<version>-linux-arm64.udcx` |
| Windows | `rdl-<version>-win32-x64.udcx` |

Install it with **UDCode > Extensions… > Install from Package…**, or from a
shell with `UDCode --install-extension rdl-<version>-<platform>.udcx`, then
start UDCode again. A package states which UDCode versions it is for
(`engines.udcode` in its `package.json`: 0.22.2 and later 0.22 releases), and UDCode refuses
one built for another version or another platform.

## Using it

Opening a `.rdl` or `.rdlc` file from the project navigator shows the report
in a tab of its own. Without the extension, UDCode's XML mode opens these
files as text; with it, the designer does. The designer's parts spread over
UDCode's window the way an Xcode editor's do:

| Part | Where it goes in UDCode |
|---|---|
| The canvas, its rulers and zoom; the Dataset and Data source editors that replace it when chosen | The tab |
| Outline, and Datasets (with the data sources and parameters) | The tab's Document Outline, on the canvas's left (O, D) |
| The Report, Attributes and Style inspectors | The inspector pane's tabs, after **File** |
| Row and column groups | The bottom area, beside the debugger and the terminal (G) |
| The insert palette | The **Library**: View > Show Library (⇧⌘L); drag a field onto the canvas |
| The report's problems | The Issues navigator, under the document; choosing one selects its item |
| The designer's commands | The **Editor** menu: Report, Arrange, Canvas |

These parts are shown while the RDL tab is in front and go away when another
tab comes forward. Selecting an item brings the Attributes inspector forward,
unless Style, which shows the selection too, is in front. RDLDesigner
arranges the same parts in its own window.

Cut, Copy, Paste, Select All and Delete are UDCode's Edit menu's. Of the
designer's keyboard shortcuts, only those UDCode leaves free are kept:
Duplicate (⌘D) and Add Element… (⇧⌘A).

The report is stored as the document's text. Each change you make in the
designer is written back to that text, so the things UDCode does for text
files work here too:

- **Undo** and **Redo** are the document's own. Undoing restores the text
  and reads the report again, keeping the selected item selected where it
  still exists.
- **Saving** and the tab's unsaved dot are the document's.
- **Source control** shows what changed. Each change touches only the lines
  that differ. One exception is the first change to a file another tool
  wrote: RDLKit writes the whole report the way it writes RDL, which may lay
  out what it did not change differently.
- **View > Open as Text** (UDCode 0.18.1 and later) shows the RDL in a normal
  editor tab, with the XML mode's highlighting, beside the designer's. The two
  tabs are the same document: edits made in the text appear in the designer
  the next time it is shown, and the designer's in the text. The designer's
  own Source view is not shown in UDCode: the text tab is the source.

A file that is not a report (broken XML, say) opens with a message
explaining why, and offers to show it as text.

## How it is built

`UDCodeExtension/` contains the extension:

- **`RDLExtension`**, its principal class. It declares the `rdl` mode in
  `LanguageInfo.plist`, which borrows the XML mode's grammar; an installed
  extension's modes are registered after UDCode's own, so it takes `.rdl` and
  `.rdlc` from the XML mode. It provides the editor for documents of that
  mode and adds the designer's menus (`RDLEditorMenus.xib`) to UDCode's
  Editor menu.
- **`RDLEditorViewController`**, the tab, loaded from `RDLEditor.xib`: the
  Document Outline and the designer side by side. It holds an
  `RDLReportDesigner` in its hosted mode (`hosted = YES`), over an undo
  manager that records nothing, because the text's undo manager is the undo.
  The inspectors, the groups and the insert palette are view controllers of
  the designer's, which the tab hands to UDCode through `UDEditorPanes`. The
  report's problems (`RDLChecker`) become the document's diagnostics, placed
  at the line where their item's `Name` appears. The designer's change
  notices are written as one `applyEdits:` call once the change is done (one
  action is several of the designer's changes), which undoes as a single
  step. When the text changes from outside the designer, the tab reads it
  again: immediately if the tab is showing, otherwise after a short delay.
- **`RDLTextDiff`**, a Myers line diff (ORMKit's, which its ORM2 extension
  writes models with). It produces the runs of lines that differ, each
  starting and ending on a line boundary, so an edit never splits a CRLF.

It builds against UDCode's SDK, the `udcodekit` archives attached to each
UDCode release, pinned by `UDCODEKIT_VERSION` in `.github/pins.env`, and on
the same GNUstep stack as that UDCode release (`GNUSTEP_PATCHES_VERSION`). At
run time the extension uses UDCode's own copies of these, because two copies
of the same classes cannot be loaded into one process. On GNUstep the top
`GNUmakefile` builds it only where the SDK is installed. On a Mac,
`Makefile.apple` builds it only where `.deps` contains
`UDCodeKit.xcframework`.

`Scripts/udcx.sh <version> <directory>` packages it for the platform it runs
on:

- **The bundle carries what UDCode lacks.** On GNUstep, RDLKitUI is compiled
  into the bundle and its XIBs are among the bundle's resources
  (`RDLKitUI/files.make` lists them for both). It can't be a library inside
  the bundle there: Windows looks for the bundle's libraries only beside the
  bundle's DLL, and gnustep-base would look for a library's resources
  elsewhere. RDLKit's library goes next to the binary; on Linux it gets an
  `$ORIGIN` runpath. On a Mac, RDLKit and RDLKitUI are frameworks in the
  bundle's `Contents/Frameworks`.
- **What UDCode has is left out:** GNUstep, UDCodeKit and the system's
  libraries. The running UDCode's copies are used.
- **Licences:** RDLKit's own (LGPL 2.1, with its source at the release tag
  that package.json's `repository` points to), and DMTabBar's (MIT), which
  RDLKitUI's tab bars are.
- **On a Mac** it is signed with `$CODESIGN_IDENTITY`. UDCode's hardened
  runtime loads only code signed by its own team, and the release workflows
  sign the package as they sign the apps, then notarize it.

The release workflows run that script through `.github/release/udcode.conf`
(gnustep-release-actions' `scripts/udcode-extension.sh`) and attach each
package to the release.

The tests in `UDCodeExtension/Tests` (`RDLTests`, run by `make check` and by
`make -f Makefile.apple check`) drive the tab through UDCode's own document
and text model. They check that:

- a report opens without its text changing;
- a change is one edit of the lines it changed, which undo and redo bring
  back, the selected item staying selected;
- a text that is not a report says why, and becomes a report once one is
  written into it;
- the inspectors, the groups and the insert palette are UDCode's panes', and
  the designer asks for the Attributes inspector and the groups;
- the report's problems are the document's diagnostics, each at its item's
  line, choosing one selecting its item;
- the tab is in the responder chain after the Document Outline, and every
  Editor menu item is a designer command;
- the line diff turns one text into the other.
