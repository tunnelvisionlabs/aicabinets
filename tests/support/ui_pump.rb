# frozen_string_literal: true

# Utilities to pump SketchUp's UI message loop during HtmlDialog tests.
module TestUiPump
  # Pumps SketchUp's UI message loop for the given duration (seconds).
  #
  # HtmlDialog callbacks only fire while the UI loop runs. A tiny modal
  # HtmlDialog spins a nested pump while it is open, so we display one
  # off-screen and let it close itself via `window.close()` after the
  # requested delay.
  #
  # @param duration [Numeric] number of seconds to keep the nested loop alive
  # @return [void]
  def process_ui_events(duration = 0.02)
    return if duration <= 0

    ms = (duration * 1000).to_i
    html = <<~HTML
      <!doctype html><meta charset="utf-8">
      <style>html,body{margin:0;padding:0;overflow:hidden}</style>
      <script>
        window.setTimeout(function(){ window.close(); }, #{ms});
      </script>
    HTML

    dlg = ::UI::HtmlDialog.new(
      dialog_title: 'AI Cabinets Test Pump',
      width: 1,
      height: 1,
      style: ::UI::HtmlDialog::STYLE_UTILITY
    )

    begin
      dlg.set_position(-10_000, -10_000)
    rescue StandardError
      # Positioning can fail on some platforms; ignore and proceed.
    end

    dlg.set_html(html)
    dlg.show_modal

    nil
  end

  # Repeatedly pumps UI events until the provided block returns truthy or the
  # timeout is reached.
  #
  # @param timeout [Numeric] overall timeout in seconds
  # @param slice [Numeric] slice duration passed to {#process_ui_events}
  # @yieldreturn [Boolean] true to stop waiting
  # @raise [RuntimeError] if the timeout expires before the block returns true
  def pump_until(timeout: 8.0, slice: 0.02)
    deadline = Time.now + timeout

    until yield
      raise "timeout after #{timeout}s in pump_until" if Time.now > deadline

      process_ui_events(slice)
    end
  end
end
