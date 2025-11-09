# frozen_string_literal: true

require 'json'
require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/ui_pump'

Sketchup.require('aicabinets/ui/dialog_console_bridge')
Sketchup.require('aicabinets/ui/layout_preview/dialog')

class TC_LayoutPreviewA11y < TestUp::TestCase
  include TestUiPump

  DIALOG_PATH = File.expand_path('../../aicabinets/html/layout_preview/dialog.html', __dir__)
  DEFAULT_TIMEOUT = 4.0
  private_constant :DIALOG_PATH, :DEFAULT_TIMEOUT

  def setup
    skip('UI::HtmlDialog is unavailable in this SketchUp build.') unless defined?(UI::HtmlDialog)

    options = {
      dialog_title: 'Layout Preview Accessibility',
      width: 460,
      height: 340,
      resizable: false,
      style: ::UI::HtmlDialog::STYLE_UTILITY
    }

    @dialog = ::UI::HtmlDialog.new(options)
    AICabinets::UI::DialogConsoleBridge.register_dialog(@dialog)

    @form = RecordingForm.new
    @bridge = AICabinets::UI::LayoutPreview::SelectionSyncBridge.new(@dialog, form: @form)

    @pending_eval = nil
    @eval_queue = []
  end

  def teardown
    if defined?(AICabinets::UI::DialogConsoleBridge) && @dialog
      AICabinets::UI::DialogConsoleBridge.unregister_dialog(@dialog)
    end
    teardown_html_dialog(@dialog)
    @dialog = nil
    @bridge = nil
  end

  def test_keyboard_navigation_announces_and_selects_bays
    ensure_dialog_ready

    layout_model = {
      outer: { w_mm: 914, h_mm: 762 },
      bays: [
        { id: 'bay-left', role: 'bay', x_mm: 0, y_mm: 0, w_mm: 305, h_mm: 762 },
        { id: 'bay-center', role: 'bay', x_mm: 305, y_mm: 0, w_mm: 305, h_mm: 762 },
        { id: 'bay-right', role: 'bay', x_mm: 610, y_mm: 0, w_mm: 304, h_mm: 762 }
      ],
      fronts: []
    }

    assert(render_layout(layout_model), 'Expected LayoutPreviewDialog.renderLayout to succeed.')

    wrapper_attrs = await_eval(<<~JAVASCRIPT)
      (function () {
        var root = document.querySelector('.lp-root');
        if (!root) {
          return null;
        }
        return {
          role: root.getAttribute('role'),
          label: root.getAttribute('aria-label'),
          tabindex: root.getAttribute('tabindex')
        };
      })();
    JAVASCRIPT

    refute_nil(wrapper_attrs, 'Expected preview wrapper to exist.')
    assert_equal('img', wrapper_attrs[:role] || wrapper_attrs['role'])
    assert_equal('Cabinet front preview', wrapper_attrs[:label] || wrapper_attrs['label'])
    assert_equal('-1', wrapper_attrs[:tabindex] || wrapper_attrs['tabindex'])

    focus_state = focus_preview
    refute_nil(focus_state, 'Expected focus to land on the first bay.')
    assert_equal('bay-left', focus_state[:id] || focus_state['id'])
    assert_equal('bay', focus_state[:role] || focus_state['role'])
    assert_equal('0', focus_state[:tabindex] || focus_state['tabindex'])
    focused_flag = focus_state[:isFocused].nil? ? focus_state['isFocused'] : focus_state[:isFocused]
    assert(focused_flag, 'Expected focused bay to receive is-focused class.')
    aria_selected = focus_state[:ariaSelected] || focus_state['ariaSelected']
    assert_equal('false', aria_selected, 'Initial focus should not mark the bay as selected.')

    label_check = read_bay_a11y('bay-center')
    refute_nil(label_check, 'Expected bay-center metadata to be available.')
    label_text = label_check[:label] || label_check['label']
    assert_includes(label_text, 'Bay 2', 'Expected bay aria-label to include ordinal.')
    assert_includes(label_text, '305 by 762 millimeters', 'Expected aria-label to announce size in millimeters.')

    move_state = move_focus('ArrowRight')
    assert_equal('bay-center', move_state[:activeId] || move_state['activeId'])
    assert_single_roving_anchor(move_state)

    move_state = move_focus('ArrowRight')
    assert_equal('bay-right', move_state[:activeId] || move_state['activeId'])
    assert_single_roving_anchor(move_state)

    move_state = move_focus('ArrowRight')
    assert_equal('bay-right', move_state[:activeId] || move_state['activeId'], 'Focus should clamp at the last bay.')

    initial_select_count = @form.selected_ids.length
    select_state = trigger_select('Enter')
    assert_equal(initial_select_count + 1, @form.selected_ids.length, 'Expected keyboard select to invoke requestSelectBay.')
    assert_equal('bay-right', @form.selected_ids.last.to_s)
    selected_flag = select_state[:ariaSelected] || select_state['ariaSelected']
    assert_equal('true', selected_flag, 'Selected bay should expose aria-selected="true".')

    @bridge.set_active_bay('bay-left', scope: :single)

    scope_state = await_eval(<<~JAVASCRIPT)
      (function () {
        var root = document.querySelector('.lp-root');
        if (!root) {
          return null;
        }
        var focused = document.activeElement;
        var active = root.querySelector('[data-role="bay"].is-active');
        return {
          focusedId: focused ? focused.getAttribute('data-id') : null,
          focusedSelected: focused ? focused.getAttribute('aria-selected') : null,
          focusedHasClass: focused ? focused.classList.contains('is-focused') : false,
          activeId: active ? active.getAttribute('data-id') : null,
          scopeClass: root.classList.contains('scope-single')
        };
      })();
    JAVASCRIPT

    refute_nil(scope_state, 'Expected preview state after scope change.')
    assert_equal('bay-right', scope_state[:focusedId] || scope_state['focusedId'], 'Keyboard focus should remain on the last bay.')
    focused_selected = scope_state[:focusedSelected] || scope_state['focusedSelected']
    assert_equal('false', focused_selected, 'Focused bay should not stay selected after external update.')
    focused_has_class = scope_state[:focusedHasClass] || scope_state['focusedHasClass']
    assert(focused_has_class, 'Focused bay should retain focus styling after selection changes elsewhere.')
    assert_equal('bay-left', scope_state[:activeId] || scope_state['activeId'], 'Active bay should follow bridge updates.')
    scope_flag = scope_state[:scopeClass].nil? ? scope_state['scopeClass'] : scope_state[:scopeClass]
    assert(scope_flag, 'Expected single scope to add scope-single class.')

    # Switch to a layout with no bays to ensure focus falls back to the wrapper.
    empty_layout = { outer: { w_mm: 762, h_mm: 762 }, bays: [], fronts: [] }
    assert(render_layout(empty_layout), 'Expected empty layout to render.')

    empty_state = await_eval(<<~JAVASCRIPT)
      (function () {
        var root = document.querySelector('.lp-root');
        if (!root) {
          return null;
        }
        root.focus();
        var active = document.activeElement;
        return {
          rootTabindex: root.getAttribute('tabindex'),
          activeRole: active ? active.getAttribute('role') : null,
          activeIsRoot: active === root
        };
      })();
    JAVASCRIPT

    refute_nil(empty_state, 'Expected wrapper focus fallback to succeed.')
    assert_equal('0', empty_state[:rootTabindex] || empty_state['rootTabindex'])
    assert(empty_state[:activeIsRoot] || empty_state['activeIsRoot'], 'Wrapper should receive focus when no bays exist.')

    events = AICabinets::UI::DialogConsoleBridge.drain_events(@dialog)
    errors = events.select { |event| event[:level] == 'error' }
    assert_empty(errors, build_console_failure_message(errors))
  end

  private

  def ensure_dialog_ready
    return if @dialog_ready

    with_modal_pump(timeout: DEFAULT_TIMEOUT) do |_pump, close_pump|
      @dialog.add_action_callback('__aicabinets_report_console_event') do |_context, payload|
        AICabinets::UI::DialogConsoleBridge.record_event(@dialog, payload)
        if @pending_eval
          pending = @pending_eval
          @pending_eval = nil
          pending.call
        end
      end

      @dialog.add_action_callback('layout_preview_ready') do |_context, _payload|
        @dialog_ready = true
        close_pump.call
      end

      @dialog.add_action_callback('layout_preview_eval') do |_context, payload|
        store_eval_payload(payload)
        if @pending_eval
          pending = @pending_eval
          @pending_eval = nil
          pending.call
        end
      end

      @dialog.set_file(DIALOG_PATH)
      @dialog.show
    end

    flunk('Layout preview dialog did not report ready state.') unless @dialog_ready
  end

  def render_layout(model)
    ensure_dialog_ready

    model_json = JSON.generate(model)
    await_eval(<<~JAVASCRIPT)
      (function () {
        var api = window.AICabinets && window.AICabinets.UI && window.AICabinets.UI.LayoutPreviewDialog;
        if (!api || typeof api.renderLayout !== 'function') {
          return false;
        }
        return api.renderLayout(#{model_json});
      })();
    JAVASCRIPT
  end

  def focus_preview
    ensure_dialog_ready

    await_eval(<<~JAVASCRIPT)
      (function () {
        var root = document.querySelector('.lp-root');
        if (!root) {
          return null;
        }
        root.focus();
        var active = document.activeElement;
        if (!active) {
          return null;
        }
        return {
          id: active.getAttribute('data-id'),
          role: active.getAttribute('data-role'),
          tabindex: active.getAttribute('tabindex'),
          ariaSelected: active.getAttribute('aria-selected'),
          isFocused: active.classList.contains('is-focused')
        };
      })();
    JAVASCRIPT
  end

  def read_bay_a11y(bay_id)
    ensure_dialog_ready

    identifier_json = JSON.generate(bay_id.to_s)
    await_eval(<<~JAVASCRIPT)
      (function () {
        var selector = '[data-role="bay"][data-id="' + #{identifier_json} + '"]';
        var element = document.querySelector(selector);
        if (!element) {
          return null;
        }
        return {
          label: element.getAttribute('aria-label'),
          ariaSelected: element.getAttribute('aria-selected')
        };
      })();
    JAVASCRIPT
  end

  def move_focus(key)
    ensure_dialog_ready

    key_json = JSON.generate(key)
    await_eval(<<~JAVASCRIPT)
      (function () {
        var active = document.activeElement;
        if (!active) {
          return null;
        }
        var event = new KeyboardEvent('keydown', {
          key: #{key_json},
          code: #{key_json},
          bubbles: true
        });
        active.dispatchEvent(event);
        var next = document.activeElement;
        var bayNodes = Array.prototype.slice.call(document.querySelectorAll('[data-role="bay"]'));
        return {
          activeId: next ? next.getAttribute('data-id') : null,
          focusClass: next ? next.classList.contains('is-focused') : false,
          tabStops: bayNodes.map(function (node) {
            return { id: node.getAttribute('data-id'), tabindex: node.getAttribute('tabindex') };
          })
        };
      })();
    JAVASCRIPT
  end

  def trigger_select(key)
    ensure_dialog_ready

    key_json = JSON.generate(key)
    await_eval(<<~JAVASCRIPT)
      (function () {
        var active = document.activeElement;
        if (!active) {
          return null;
        }
        var event = new KeyboardEvent('keydown', {
          key: #{key_json},
          code: #{key_json},
          bubbles: true
        });
        active.dispatchEvent(event);
        return {
          id: active.getAttribute('data-id'),
          ariaSelected: active.getAttribute('aria-selected')
        };
      })();
    JAVASCRIPT
  end

  def assert_single_roving_anchor(state)
    tab_map = state[:tabStops] || state['tabStops'] || []
    zeros = tab_map.count { |entry| (entry[:tabindex] || entry['tabindex']) == '0' }
    assert_equal(1, zeros, 'Expected exactly one bay to expose tabindex="0".')
    focus_flag = state[:focusClass].nil? ? state['focusClass'] : state[:focusClass]
    assert(focus_flag, 'Focused bay should keep the focus styling class.')
  end

  def await_eval(expression)
    ensure_dialog_ready

    payload = nil
    with_modal_pump(timeout: DEFAULT_TIMEOUT) do |_pump, close_pump|
      @pending_eval = close_pump
      wrapped = <<~JAVASCRIPT
        (function () {
          var callback = window.sketchup && window.sketchup.layout_preview_eval;
          if (!callback) {
            return;
          }
          try {
            var value = (function () { return #{expression}; })();
            callback(JSON.stringify({ ok: true, value: value }));
          } catch (error) {
            var message = error && error.message ? error.message : String(error);
            callback(JSON.stringify({ ok: false, message: message }));
          }
        })();
      JAVASCRIPT
      @dialog.execute_script(wrapped)
    end

    payload = @eval_queue.shift
    flunk('HtmlDialog eval did not return a payload.') unless payload
    return payload[:value] if payload[:ok]

    flunk("HtmlDialog eval failed: #{payload[:message]}")
  ensure
    @pending_eval = nil
  end

  def store_eval_payload(payload)
    data =
      if payload.is_a?(String) && !payload.empty?
        begin
          JSON.parse(payload, symbolize_names: true)
        rescue JSON::ParserError
          { ok: false, message: payload.to_s }
        end
      elsif payload.is_a?(Hash)
        payload.transform_keys { |key| key.to_sym rescue key }
      else
        { ok: true, value: payload }
      end
    @eval_queue << data
  end

  def build_console_failure_message(events)
    return 'No console events captured.' if events.empty?

    lines = ['Unexpected console errors:']
    events.each do |event|
      lines << "- [#{event[:level]}] #{event[:message]} (#{event[:dialog_id]})"
    end
    lines.join("\n")
  end

  class RecordingForm
    attr_reader :selected_ids

    def initialize
      @selected_ids = []
    end

    def select_bay(bay_id)
      @selected_ids << bay_id
    end
  end
end
