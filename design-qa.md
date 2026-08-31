# Landing Feature Media QA

- Source visual truth: `/var/folders/3k/jwczflxn5rxgp_85m56r2sq80000gn/T/codex-clipboard-fc24f66e-4c84-44a6-82ac-8b2daf4ccf7e.png`
- Implementation screenshot: `/tmp/codexusage-features-desktop.png`
- Combined comparison: `/tmp/codexusage-features-comparison.png`
- Desktop viewport: 1440 x 900 CSS px at device scale 1
- Source pixels: 1354 x 628
- Implementation pixels: 1440 x 900
- State: dark landing page, `#features` anchored in view

## Full-view comparison

The existing two-column feature structure, typography, icons, borders, copy, and dark palette remain unchanged. The requested media now sits beneath its corresponding description: the rolling-window chart on the left and the macOS reset notification on the right.

## Focused-region comparison

The focused comparison pairs the supplied feature-section reference with the rendered 680 px-wide implementation region. The dashboard source and the user-supplied `Reset alerts are ready.` notification source are both reused directly. The notification foreground is shown in full without stretching; a softened copy of the same background fills the equal-height frame behind it.

## Findings

- No actionable P0, P1, or P2 differences remain for the requested placement.
- Typography: existing font family, weights, sizes, wrapping, and hierarchy are preserved.
- Spacing: each crop follows its own feature copy; desktop stays two-column and mobile stacks the two feature items.
- Colors: existing background, line, muted text, and violet accent tokens are unchanged.
- Image quality: source-resolution images remain sharp. The left crop isolates the chart, and the right frame preserves the complete supplied image, including its right edge, over a softened background extension.
- Copy: the right feature description is tightened to four desktop lines so both copy blocks and media frames share the same vertical grid.

## Comparison history

1. Initial implementation aligned both media frames to the grid-row bottom, leaving excessive space above the shorter notification crop.
2. Removed the automatic top margin so each image follows its description directly.
3. Re-captured desktop and mobile layouts; both crops remain inside their columns with no visible clipping error.
4. Reduced the chart to 84% of its column, reduced the notification frame to 88%, and widened the notification crop to retain more blue background around the banner.
5. Removed the redundant `Codex Usage` line from the notification artwork and moved the remaining title and body upward as a centered two-line group.
6. Replaced that interim notification with the user's supplied `Reset alerts are ready.` image and matched the right frame to the chart at 84% width and a 1.3 aspect ratio.
7. Shortened the right feature description to four desktop lines and restored automatic media alignment; both paragraphs now measure 97.19 px and both media frames share identical top and bottom coordinates.
8. Removed the forced 1.3 notification crop after comparing against the original 848 x 538 image. Both frames retain the same 84% width and top coordinate; the notification now uses its natural 1.576 ratio with no right-edge loss.
9. Restored the shared 1.3 frame while keeping the full 848 x 538 notification foreground visible with `object-fit: contain`; the extra height is filled by a softened copy behind it, so neither foreground content nor the right edge is cropped.

## Responsive evidence

- Mobile viewport: 390 x 844 CSS px at device scale 1.
- Both media frames render from x=22 to x=312.6 at exactly 290.6 x 223.6 CSS px and stack in source order.
- The chart and notification focal areas remain visible at mobile width.

## Interaction and runtime evidence

- `See features` navigates to `#features`.
- `Get the app` navigates to `#get`.
- Browser console errors: none.

## Final result

final result: passed
