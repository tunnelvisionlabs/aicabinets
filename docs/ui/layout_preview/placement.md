# Layout preview placement in HtmlDialogs

## Insert Base Cabinet dialog

The Insert Base Cabinet dialog renders the inline layout preview inside the
`<section data-role="layout-preview-pane">` region that was added to
`aicabinets/ui/dialogs/insert_base_cabinet.html`. The container stays hidden
until the preview feature flag enables it; when active the dialog body receives
the `has-layout-preview` class so the pane can expand alongside the form.

Preview wiring is hosted by
`AICabinets::UI::LayoutPreview::DialogHost` (`aicabinets/ui/layout_preview/dialog_host.rb`).
The host keeps a single HtmlDialog action callback (`requestSelectBay`) in
sync with the form’s bay selection. The host lazily loads the preview manager
exposed at `window.AICabinets.UI.InsertBaseCabinet.layoutPreview` and forwards
Ruby updates through the renderer’s `update`, `setActiveBay`, and `selectBay`
methods.

## Feature flag

The preview is controlled by `AICabinets::Features.layout_preview?` (declared in
`aicabinets/features.rb`). When the flag returns `false` the dialog skips loading
preview assets entirely and the preview pane stays hidden. Toggling the flag off
at runtime calls `DialogHost#destroy`, which in turn removes the preview pane’s
active styles and releases the renderer handle.

## Selection scope

Ruby propagates both layout model changes and active-bay scope to the preview.
`sync_layout_preview_selection` in
`aicabinets/ui/dialogs/insert_base_cabinet_dialog.rb` calls
`LayoutPreview::DialogHost#set_active_bay`, which updates the renderer without
triggering a feedback loop. When the form requests a bay selection change, the
host calls back into `handle_layout_preview_select`, ensuring the HtmlDialog and
form controller stay synchronized.
