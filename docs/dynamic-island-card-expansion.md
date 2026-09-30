# Dynamic Island card expansion

## Interaction

Page cards gently enlarge under the pointer. **Settings → Dynamic Island → Behavior → Enlarge cards on hover** controls this independently of the island’s own hover opening. It starts enabled; Reduce Motion suppresses enlargement.

An explicit expand button opens a larger bubble above the surrounding cards. Lists use `+N` when they omit records. Preview cards use an expand icon. The bubble grows from its source using the island’s spring motion and Liquid Glass setting, with a readable dark fallback. It stays inside the visible page and scrolls when needed.

Close, Escape and the dimmed backdrop close the reader. Existing paste, copy, open, dismiss, slider and drag actions retain their meanings. Only one reader opens at a time; its content follows current data, and it closes when its source disappears or the page changes.

## Assessment

| Feature | Decision |
| --- | --- |
| AI Agents | Expand Now, Models, Projects and omitted provider limit windows. Spending, Trend, Activity and Resets already expose their intended summaries/actions. |
| Notifications | Full selectable message reader; closing it does not dismiss the notification. |
| Clipboard | Separate read-only preview for full text, images and file paths; card click still pastes/copies. |
| Tools results | Readers for cleaned URLs, OCR output and all failure details in completed batches. Homebrew descriptions wrap in the existing scrolling detail view. |
| System | Metric cards already open complete detail views. |
| Controls and Mixer | Preserve sliders, actions, device menus and the complete app rail. |
| Music | Preserve its player, app action, metadata help, lyrics and queue views. |
| Calendar | Preserve the scrolling agenda and existing event navigation. |
| Files / Shelf | Existing batch expansion and file previews already expose content; preserve selection and dragging. |
| Captures | Existing Restore/Open exposes complete capture content. |
| Downloads | Every item already scrolls; retain existing progress and file actions. |
| Scratchpad | Already a complete scrolling editor and formatting preview. |
| Timer and Camera | Existing responsive controls and device menus expose their content. |
| Explore, quick access and compact activities | Keep destination/action clicks and existing paging. |
| Mirrors and lock screen | Preserve passive presentation and intentional privacy limits. |

## Verification

Check overflow selection, bounded popup geometry, hover preference/Reduce Motion, settings backup, and Escape before Tools navigation. Build the app and run the focused Agents and Dynamic Island suites. Inspect glass and fallback readers at narrow and short page sizes, including text selection and source removal.
