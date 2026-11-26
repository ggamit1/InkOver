# InkOver · Screen annotation for macOS

InkOver is an open-source macOS menu bar app that lets you draw directly on your Mac screen during presentations, live coding demos, and lessons. Highlight code, point out parts of an interface, or sketch an idea on a separate drawing board.

## Download InkOver for macOS

[InkOver 0.1.0 (.dmg)](Distribution/InkOver-0.1.0.dmg) is a beta build for **macOS 14 Sonoma or later** on Apple silicon and Intel Macs. Choose **Download raw file** on the GitHub file page, open the disk image, and drag **InkOver** to **Applications**. This beta is ad hoc signed.

## Screen annotation tools

- **Draw over open apps** with a pen, highlighter, arrows, lines, shapes, and text. Use Pointer mode to interact with an app while your marks stay visible.
- **Sketch on a whiteboard or dark board** with horizontal and vertical page layouts.
- **Highlight your cursor** with an adjustable ring, even when annotation is off.
- **Start from the menu bar or a global keyboard shortcut** and position the floating toolbar along any edge of the display.

## Annotate

1. Move the pointer to the display you want to mark up. Press **Control–Option–Command–I** or choose **Start Annotation** from the InkOver menu bar icon.
2. Choose **Pen**, **Highlighter**, **Line**, **Arrow**, **Rectangle**, or **Oval**, then drag on the display. Set the ink color and width from the toolbar. Choose **Toolbar Position** in the InkOver menu for **Right**, **Left**, **Top**, or **Bottom**. Right is the default. Both sides use two columns, while Top and Bottom use one horizontal row. Drag the handle to reposition the toolbar, and scroll the tool strip on smaller displays. The toolbar follows macOS Reduce Motion settings.
3. For a text label, select **Text**, choose a size, and click where the label should appear. Type and press **Return** to place it or **Escape** to cancel typing.
4. Drag **Eraser** over marks to remove them. Use **Undo** (**⌘Z**), **Redo** (**⇧⌘Z**), or **Clear**. An eraser gesture or a clear operation can be undone as one step.
5. Select **Pointer** to use the underlying app while keeping your screen marks and toolbar visible. Select a drawing tool to continue annotating. From **Board**, Pointer returns to the screen canvas and saves the board for the current session.
6. Click **Hide** to hide just the toolbar, then choose **Show Toolbar** from the InkOver menu to bring it back. Click **Done** or use the global shortcut to end annotation. **Escape** also exits while using a drawing tool. Starting annotation again restores the marks for that display and canvas during the current session.

Use **Board** to switch between the screen and the drawing board. Open **Options** beside **Board** to choose a **Horizontal** or **Vertical** page and a **Dark** or **White** background. The board keeps its marks and editing history when its format changes. Toggle **Ring** from the toolbar or menu bar to highlight the pointer during normal use. Set its color and diameter in **Settings**. If macOS rejects the global shortcut, the menu shows the error and **Start Annotation** remains available.

InkOver stores preferences locally and keeps drawings in memory for the current session.

## Build and run

InkOver uses SwiftUI for its controls and AppKit and Core Graphics for its screen overlays. The toolbar uses native Liquid Glass on macOS 26 and later when built with the macOS 26 SDK or newer. Earlier versions use a frosted system material.

Open [InkOver.xcodeproj](InkOver.xcodeproj) in Xcode 16 or later, select the **InkOver** scheme, and press **⌘R**. The deployment target is macOS 14.0.

You can also use the Xcode Command Line Tools to build and run an ad hoc signed, sandboxed app:

```sh
./scripts/build.sh
open .build/InkOver.app
```

## Beta verification

The local build is for testing. Before distribution, use the [acceptance matrix in the build plan](plan.md#acceptance-test-matrix) to verify macOS 14, mixed-scale and repositioned monitors, a mid-stroke disconnect, Spaces, full-screen apps, and Stage Manager. In Zoom and Meet, compare what a remote viewer can see in entire-display and single-window sharing.

The Xcode project uses local signing. Configure an Apple Developer team, a registered bundle identifier, and distribution signing for a store archive.

## License

InkOver is licensed under the [GNU General Public License v3.0](https://github.com/ggamit1/InkOver/blob/main/LICENSE).
