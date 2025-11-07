# frozen_string_literal: true

# Utilities to run a nested SketchUp UI message loop while waiting for
# HtmlDialog callbacks. The helper opens a tiny off-screen modal dialog and
# closes it either when the caller invokes the provided closer or when a
# timeout elapses inside the dialog itself.
module TestUiPump
  module_function

  # Runs a modal HtmlDialog pump for up to the specified timeout. The dialog
  # auto-closes itself after the timeout via `window.close()`. Callers receive a
  # block that yields the dialog instance and a `close_pump` lambda that closes
  # the dialog immediately (marking the result as :callback). The method returns
  # the symbol reason the pump closed (`:callback` or `:timeout`).
  #
  # @param timeout [Numeric] maximum seconds to keep the nested loop alive
  # @yieldparam dialog [UI::HtmlDialog]
  # @yieldparam close_pump [Proc]
  # @yieldreturn [void]
  # @return [Symbol] :callback if closed by the caller, otherwise :timeout
  def with_modal_pump(timeout: 8.0)
    raise ArgumentError, 'with_modal_pump requires a block.' unless block_given?

    duration = timeout.to_f
    raise ArgumentError, 'timeout must be positive.' if duration <= 0.0

    timeout_ms = [(duration * 1000).to_i, 1].max
    html = <<~HTML
      <!doctype html><meta charset="utf-8">
      <style>html,body{margin:0;padding:0;overflow:hidden}</style>
      <script>
        window.setTimeout(function () { window.close(); }, #{timeout_ms});
      </script>
    HTML

    dialog = ::UI::HtmlDialog.new(
      dialog_title: 'AI Cabinets Test Pump',
      width: 1,
      height: 1,
      style: ::UI::HtmlDialog::STYLE_UTILITY
    )

    begin
      dialog.set_position(-10_000, -10_000)
    rescue StandardError
      # Some environments reject the off-screen position; a 1x1 dialog is fine.
    end

    closed = false
    reason = :timeout

    dialog.set_on_closed do
      closed = true
    end

    close_pump = lambda do
      next if closed

      closed = true
      reason = :callback
      begin
        dialog.close
      rescue StandardError
        # Dialog may already be closing; ignore.
      end
    end

    dialog.set_html(html)

    begin
      yield(dialog, close_pump)
      dialog.show_modal unless closed
    ensure
      unless closed
        begin
          dialog.close
        rescue StandardError
          # The dialog might not have been shown yet; ignore close errors.
        ensure
          closed = true
        end
      end
    end

    reason
  end

  # Closes the provided HtmlDialog handle and runs a brief modal pump so the
  # Chromium Embedded Framework (CEF) process can shut down cleanly between
  # tests. The extra dialog prevents subsequent HtmlDialogs from inheriting
  # state from a not-yet-destroyed renderer.
  #
  # @param dialog [UI::HtmlDialog, nil]
  # @return [void]
  def teardown_html_dialog(dialog)
    begin
      dialog&.close
    rescue StandardError
      # HtmlDialog may already be closing; ignore close errors.
    end

    pump = ::UI::HtmlDialog.new(
      dialog_title: 'Pump',
      width: 1,
      height: 1,
      style: ::UI::HtmlDialog::STYLE_UTILITY
    )

    # tiny pump to let CEF process tear down cleanly before next test
    pump.set_html('<script>setTimeout(function(){ window.close(); }, 100);</script>')
    pump.show_modal
  end

  module_function :teardown_html_dialog
end
