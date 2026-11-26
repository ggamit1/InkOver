# macOS Screen Annotation App — Build Plan

## Product goal

Build a native Mac menu bar utility for live code walkthroughs, online teaching, and presentations. During a demo, the presenter can activate drawing with a shortcut, mark up what is on the screen, and press Escape to resume interacting with the underlying app. Use an original name, icon, toolbar layout, and visual style.

The reference product, [Presentify](https://presentifyapp.com/), combines annotation, a whiteboard, cursor highlighting, and spotlight and zoom. Start with annotation and a simple cursor ring. Treat whiteboard, spotlight, magnification, and a dedicated iPad companion as follow-up releases.

## MVP scope

| Capability | Expected behavior |
|---|---|
| Menu bar | Start or stop annotation, toggle the cursor ring, open settings, and quit. Show the current drawing state. |
| Drawing tools | Offer freehand pen, arrow, and rectangle. Use a visible colour selection and line-width control. |
| Editing | Undo the latest completed mark and clear the active display. Exiting drawing mode hides the marks. Re-entering in the same session restores them. |
| Keyboard | Use a default global shortcut to toggle drawing. Escape exits drawing during ordinary use. Keep the menu bar toggle available if shortcut registration fails. |
| Cursor ring | Follow the pointer while normal clicks still reach the underlying app. |
| Displays | Start drawing on the display containing the pointer. Handle different display scales and reset safely if the active display disconnects. |
| Settings | Persist colour, line width, and ring preferences locally. Keep drawings in memory for the session. |

The app has no account or backend. Use macOS 14 as a provisional deployment target, then confirm it against the Apple APIs and hardware you intend to support. Target a Mac App Store beta first, with timing dependent on compatibility findings and review.

## Technology and project layout

Use **Swift and Xcode**. SwiftUI provides the menu bar and settings. AppKit owns the overlay windows and handles input. Use Core Graphics in an `NSView` for drawing. For a React developer, SwiftUI's state-driven rendering is a familiar starting point. Spend the first learning sessions on AppKit window behavior, event handling, and coordinate conversion.

| Suggested file | Responsibility |
|---|---|
| `AnnotationApp.swift` | App entry point, SwiftUI menu bar, and settings scene. |
| `AnnotationSession.swift` | Observable mode, selected tool, pending gesture, and commands for undo and clear. |
| `OverlayWindowController.swift` | Create and dispose overlay windows, manage event routing, and respond to display changes. Keep window operations on the main actor. |
| `DrawingCanvasView.swift` | Convert mouse events to canvas coordinates and render marks and live previews. |
| `DrawingMark.swift` | Store the stroke points or shape geometry and a snapshot of its styling. |
| `CursorRingController.swift` | Move a separate click-through ring overlay and stop updates when disabled. |
| `ShortcutController.swift` | Register and release the shortcut and surface registration failures. |
| `AppPreferences.swift` | Provide validated defaults and store user preferences. |

Begin with a single app target and add files as their responsibilities emerge.

## Overlay and drawing behavior

1. **Activate.** Resolve the display under the pointer and place a transparent, borderless AppKit window over it. Keep the toolbar reachable and tools visually distinguishable. Verify window ordering and focus on the minimum supported macOS version.
2. **Start a gesture.** Record a canvas-local start point and snapshot the active tool and style. Append pointer samples for a pen stroke. Update the preview endpoint for an arrow or rectangle.
3. **Commit.** Finalize one mark on mouse-up. Undo removes one completed mark. Ignore degenerate shapes and cancel pending gestures if the overlay closes or the display changes.
4. **Exit.** Hide the drawing overlay and restore ordinary input. Keep the cursor ring independent so it can remain enabled. Always make the ring window click-through.
5. **Adjust to display changes.** Re-read screen geometry when displays are reconfigured. Convert pointer positions to each window's local coordinates. Test Retina and non-Retina scaling and monitors placed to the left or above the MacBook display.
6. **Control redraws.** Redraw while a drawing gesture changes and when the session state changes. Start cursor updates only while the ring is active. Profile a long drawing session before optimizing.

Keep presentation-space behavior in the overlay controller. Validate full-screen apps, Spaces, and Stage Manager independently. Document the modes tested on each supported macOS version. See Apple's [window collection behavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct) and [mouse event pass-through](https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents).

## Four-week beta schedule

The schedule assumes one developer and includes time to learn Swift and AppKit. Use the first week to test the highest-risk behavior before investing in the drawing toolbar.

### Week 1 — Prove the overlay

- [ ] Create the Xcode project, menu bar item, and plain settings screen.
- [ ] Enable App Sandbox early for the planned App Store release.
- [ ] Draw one freehand mark over VS Code and return control to the editor when annotation exits.
- [ ] Prototype Escape and a system-wide shortcut in the sandboxed build. Validate behavior with another app focused and record the permission prompts, if any.
- [ ] Test on a full-screen app and watch a live display share from a second device.

**Exit criteria:** Activate annotation above VS Code, draw a red line, press Escape, then click and type in the editor. Confirm the remote viewer sees the line using the intended display-sharing mode. If full-screen or shortcut behavior fails, resolve it now or explicitly narrow the beta's supported modes.

### Week 2 — Build the drawing workflow

- [ ] Implement pen, arrows, and rectangles with a live preview.
- [ ] Add a compact toolbar with accessible labels and visible selection states.
- [ ] Add undo, clear, colour, and line width. Restore the selected preferences after relaunch.
- [ ] Check that changing the current colour does not recolour existing marks and that Escape during a drag discards the preview.

**Exit criteria:** Complete a short code walkthrough with all three tools and recover normal input using either the keyboard or menu bar.

### Week 3 — Add the cursor ring and test displays

- [ ] Implement a click-through cursor ring with adjustable colour and size.
- [ ] Resolve the active display on activation and test mixed display scales and arrangements.
- [ ] Handle external display disconnects and app quit while drawing.
- [ ] Use Instruments to compare idle CPU with the overlay off and assess responsiveness during a longer annotation session.

**Exit criteria:** The ring follows the cursor across monitors, drawing lines up with the pointer, and disconnecting a monitor cannot leave an invisible window intercepting clicks.

### Week 4 — Validate and prepare distribution

- [ ] Test Zoom and Google Meet from the viewer's side. Record results separately for entire-display and single-window sharing.
- [ ] Test OBS display capture if it is a launch target. Check normal windows, full-screen and Spaces on the supported macOS versions.
- [ ] Prepare an original icon, screenshots, a short demo, and a help page covering shortcuts and supported sharing modes.
- [ ] Sign and archive the sandboxed app. Test a release build on another Mac and prepare the App Store Connect listing, privacy disclosures, and review notes.
- [ ] Use a TestFlight beta if available for your setup. Fix input-blocking or display-share problems before submitting.

**Exit criteria:** A tester can install the beta, annotate a screen share, and recover normal input without developer help. Publish only after signing, distribution checks, and store review are complete.

## Acceptance test matrix

| Scenario | Expected result |
|---|---|
| Escape while drawing | Pending mark is discarded and the underlying app receives clicks again. |
| Undo after three marks | Only the third completed mark disappears. |
| Shortcut conflict | Menu bar controls remain usable and the app exposes the registration failure. |
| Right-click, scroll, and drag with ring enabled | The underlying app handles the action normally. |
| Display changes mid-stroke | Pending drawing is cancelled and pointer input returns to the user. |
| Share one window versus entire display | Record what a remote viewer actually sees and use these results in the support documentation. |
| Relaunch | Preferences are restored and the canvas starts empty. |
| Quit while active | Overlay windows and pointer tracking are released. |

## Follow-up releases

1. **Whiteboard and expanded tools.** Reuse the mark model and canvas on a solid background. Add text, highlighter, and optional timed erasing. Define how timed expiry interacts with undo and clearing.
2. **Spotlight.** Create a click-through dimming overlay with a transparent region around the pointer. Validate external displays and meeting capture separately.
3. **Magnification.** Prototype ScreenCaptureKit with a cursor-following lens. Use a clear permission explanation, handle declined access gracefully, and exclude the lens window from captured content to prevent visual feedback. Test performance during a video call.
4. **iPad writing.** If Apple Pencil is important to your workflow, test the actual Sidecar or tablet setup during week one. Validate drag events, alignment, and screen-share visibility. Build a separate iPad companion only if you need direct wireless drawing onto the Mac. Scope pairing, coordinate mapping, and reconnect behavior as a separate milestone.

## References

- [Presentify feature overview](https://presentifyapp.com/)
- [Apple SwiftUI MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
- [Apple App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)
