# InkOver

InkOver is a native macOS menu bar app for drawing over a live code walkthrough, lesson, or presentation. It uses SwiftUI for the controls and AppKit and Core Graphics for the overlays. It stores preferences locally and keeps drawings in memory for the current session.

## Build and run

Open [InkOver.xcodeproj](InkOver.xcodeproj) in Xcode 16 or later, select the **InkOver** scheme, and press **⌘R**. The deployment target is macOS 14.0.

With the Xcode Command Line Tools, build an ad hoc signed, sandboxed app for this Mac:

```sh
./scripts/build.sh
open .build/InkOver.app
```

## Annotate

The floating toolbar uses native Liquid Glass on macOS 26 and later when built with the macOS 26 SDK or newer. It uses a frosted system material on earlier versions.

1. Move the pointer to the display you want to mark up. Press **Control–Option–Command–I** or choose **Start Annotation** from the InkOver menu bar icon.
2. Choose **Pen**, **Highlighter**, **Line**, **Arrow**, **Rectangle**, or **Oval**, then drag on the display. Set the ink color and width from the toolbar. Choose **Toolbar Position** in the InkOver menu for **Right**, **Left**, **Top**, or **Bottom**. Right is the default. Both sides use two columns, while Top and Bottom use one horizontal row. Drag the handle to reposition the toolbar, and scroll the tool strip on smaller displays. The toolbar follows macOS Reduce Motion settings.
3. For a text label, select **Text**, choose a size, and click where the label should appear. Type and press **Return** to place it or **Escape** to cancel typing.
4. Drag **Eraser** over marks to remove them. Use **Undo** (**⌘Z**), **Redo** (**⇧⌘Z**), or **Clear**. An eraser gesture or a clear operation can be undone as one step.
5. Select **Pointer** to use the underlying app while keeping your screen marks and toolbar visible. Select a drawing tool to continue annotating. From **Board**, Pointer returns to the screen canvas and saves the board for the current session.
6. Click **Hide** to hide just the toolbar, then choose **Show Toolbar** from the InkOver menu to bring it back. Click **Done** or use the global shortcut to end annotation. **Escape** also exits while using a drawing tool. Starting annotation again restores the marks for that display and canvas during the current session.

Use **Board** to switch between the screen and the drawing board. Open **Options** beside **Board** to choose a **Horizontal** or **Vertical** page and a **Dark** or **White** background. The board keeps its marks and editing history when its format changes. Toggle **Ring** from the toolbar or menu bar to highlight the pointer during normal use. Set its color and diameter in **Settings**. If macOS rejects the global shortcut, the menu shows the error and **Start Annotation** remains available.

## Beta verification

The local build is for testing. Before distribution, use the [acceptance matrix in the build plan](plan.md#acceptance-test-matrix) to verify macOS 14, mixed-scale and repositioned monitors, a mid-stroke disconnect, Spaces, full-screen apps, and Stage Manager. In Zoom and Meet, compare what a remote viewer can see in entire-display and single-window sharing.

The Xcode project uses local signing. Configure an Apple Developer team, a registered bundle identifier, and distribution signing for a store archive.
