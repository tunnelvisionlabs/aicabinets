# frozen_string_literal: true

require 'json'
require 'testup/testcase'

require_relative 'suite_helper'
require_relative '../support/ui_pump'

Sketchup.require('aicabinets/ui/dialog_console_bridge')
Sketchup.require('aicabinets/ui/layout_preview/dialog')

class TC_LayoutPreviewPartitionsAndShelves < TestUp::TestCase
  include TestUiPump

  DIALOG_PATH = File.expand_path('../../aicabinets/html/layout_preview/dialog.html', __dir__)
  DEFAULT_TIMEOUT = 4.0
  private_constant :DIALOG_PATH, :DEFAULT_TIMEOUT

  def setup
    skip('UI::HtmlDialog is unavailable in this SketchUp build.') unless defined?(UI::HtmlDialog)

    options = {
      dialog_title: 'Layout Preview Partitions and Shelves',
      width: 420,
      height: 320,
      resizable: false,
      style: ::UI::HtmlDialog::STYLE_UTILITY
    }

    @dialog = ::UI::HtmlDialog.new(options)
    AICabinets::UI::DialogConsoleBridge.register_dialog(@dialog)
    @pending_eval = nil
    @eval_queue = []
  end

  def teardown
    if defined?(AICabinets::UI::DialogConsoleBridge) && @dialog
      AICabinets::UI::DialogConsoleBridge.unregister_dialog(@dialog)
    end
    teardown_html_dialog(@dialog)
    @dialog = nil
  end

  def test_partitions_shelves_and_door_styles_render
    ensure_dialog_ready
    AICabinets::UI::DialogConsoleBridge.drain_events(@dialog)

    vertical_model = {
      outer: { w_mm: 900, h_mm: 900 },
      bays: [
        { id: 'bay-1', role: 'bay', x_mm: 0, y_mm: 0, w_mm: 300, h_mm: 900 },
        { id: 'bay-2', role: 'bay', x_mm: 300, y_mm: 0, w_mm: 300, h_mm: 900 },
        { id: 'bay-3', role: 'bay', x_mm: 600, y_mm: 0, w_mm: 300, h_mm: 900 }
      ],
      partitions: { orientation: 'vertical', positions_mm: [300, 600] },
      shelves: [
        { bay_id: 'bay-1', y_mm: 300 },
        { bay_id: 'bay-1', y_mm: 600 },
        { bay_id: 'bay-2', y_mm: 450 }
      ],
      fronts: [
        { id: 'front-left', role: 'door', style: 'doors_left', x_mm: 0, y_mm: 0, w_mm: 300, h_mm: 900 },
        { id: 'front-right', role: 'door', style: 'doors_double', x_mm: 600, y_mm: 0, w_mm: 300, h_mm: 900 }
      ]
    }

    assert(render_layout(vertical_model), 'Expected LayoutPreviewDialog.renderLayout to succeed.')

    state = await_eval(dom_state_script)
    refute_nil(state, 'Expected DOM state to be captured.')
    assert_equal([300.0, 600.0], normalize_numeric_array(state[:vertical] || state['vertical']))
    assert_equal(0, (state[:horizontalCount] || state['horizontalCount']).to_i)

    shelf_map = state[:shelves] || state['shelves']
    assert_kind_of(Array, shelf_map)
    bay1_shelves = shelf_map.find { |entry| entry[:bayId] == 'bay-1' || entry['bayId'] == 'bay-1' }
    bay2_shelves = shelf_map.find { |entry| entry[:bayId] == 'bay-2' || entry['bayId'] == 'bay-2' }
    refute_nil(bay1_shelves, 'Expected bay-1 shelves to be reported.')
    refute_nil(bay2_shelves, 'Expected bay-2 shelves to be reported.')
    assert_equal([300.0, 600.0], normalize_numeric_array(bay1_shelves[:yPositions] || bay1_shelves['yPositions']))
    assert_equal([450.0], normalize_numeric_array(bay2_shelves[:yPositions] || bay2_shelves['yPositions']))

    door_styles = state[:doors] || state['doors']
    assert_equal(2, door_styles.length, 'Expected two door overlays.')
    left_door = door_styles.find { |entry| (entry[:style] || entry['style']) == 'doors_left' }
    double_door = door_styles.find { |entry| (entry[:style] || entry['style']) == 'doors_double' }
    refute_nil(left_door, 'Expected left-hinge door to be reported.')
    refute_nil(double_door, 'Expected double door to be reported.')
    assert_equal(1, (left_door[:hingeCount] || left_door['hingeCount']).to_i)
    assert_equal(0, (left_door[:gapCount] || left_door['gapCount']).to_i)
    assert_equal(0, (double_door[:hingeCount] || double_door['hingeCount']).to_i)
    assert_equal(1, (double_door[:gapCount] || double_door['gapCount']).to_i)

    horizontal_model = vertical_model.merge(partitions: { orientation: 'horizontal', positions_mm: [200, 500] })
    assert(render_layout(horizontal_model), 'Expected LayoutPreviewDialog.renderLayout to succeed for horizontal update.')

    horizontal_state = await_eval(dom_state_script)
    refute_nil(horizontal_state, 'Expected DOM state for horizontal partitions.')
    assert_equal(0, (horizontal_state[:verticalCount] || horizontal_state['verticalCount']).to_i)
    assert_equal([200.0, 500.0], normalize_numeric_array(horizontal_state[:horizontal] || horizontal_state['horizontal']))

    events = AICabinets::UI::DialogConsoleBridge.drain_events(@dialog)
    errors = events.select { |event| event[:level] == 'error' }
    assert_empty(errors, build_console_failure_message(errors))
  end

  def test_front_layout_updates_without_partitions
    ensure_dialog_ready
    AICabinets::UI::DialogConsoleBridge.drain_events(@dialog)

    base_model = {
      outer: { w_mm: 820, h_mm: 720 },
      bays: [],
      partitions: { orientation: 'vertical', positions_mm: [] },
      shelves: [
        { bay_id: 'cabinet', y_mm: 240 },
        { bay_id: 'cabinet', y_mm: 480 }
      ],
      fronts: [
        { id: 'front-door', role: 'door', style: 'doors_left', x_mm: 0, y_mm: 0, w_mm: 820, h_mm: 720 }
      ]
    }

    assert(render_layout(base_model), 'Expected LayoutPreviewDialog.renderLayout to succeed for base model.')

    initial_state = await_eval(dom_state_script)
    refute_nil(initial_state, 'Expected DOM state snapshot for base model.')
    initial_doors = Array(initial_state[:doors] || initial_state['doors'])
    assert_equal(1, initial_doors.length, 'Expected one door overlay for base model.')
    assert_equal('doors_left', initial_doors.first[:style] || initial_doors.first['style'])

    initial_shelves = Array(initial_state[:shelves] || initial_state['shelves'])
    assert_equal(1, initial_shelves.length, 'Expected cabinet shelves group to render.')
    cabinet_shelves = initial_shelves.first
    assert_equal('cabinet', cabinet_shelves[:bayId] || cabinet_shelves['bayId'])
    assert_equal(
      [240.0, 480.0],
      normalize_numeric_array(cabinet_shelves[:yPositions] || cabinet_shelves['yPositions'])
    )

    open_model = base_model.merge(fronts: [])
    assert(render_layout(open_model), 'Expected LayoutPreviewDialog.renderLayout to succeed for open model update.')

    open_state = await_eval(dom_state_script)
    refute_nil(open_state, 'Expected DOM state snapshot after removing door.')
    open_doors = Array(open_state[:doors] || open_state['doors'])
    assert_equal(0, open_doors.length, 'Expected no door overlays after switching to open front.')

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

  def dom_state_script
    <<~JAVASCRIPT
      (function () {
        var root = document.querySelector('.lp-root');
        if (!root) {
          return null;
        }
        function parseLines(nodeList, attr) {
          var result = [];
          for (var i = 0; i < nodeList.length; i += 1) {
            var value = Number(nodeList[i].getAttribute(attr));
            if (Number.isFinite(value)) {
              result.push(value);
            }
          }
          return result;
        }
        var partitionsV = root.querySelectorAll('[data-layer="partitions-v"] line');
        var partitionsH = root.querySelectorAll('[data-layer="partitions-h"] line');
        var shelfGroups = root.querySelectorAll('[data-layer="shelves"] [data-role="bay-shelves"]');
        var shelves = [];
        for (var index = 0; index < shelfGroups.length; index += 1) {
          var group = shelfGroups[index];
          var bayId = group.getAttribute('data-bay-id');
          shelves.push({
            bayId: bayId,
            yPositions: parseLines(group.querySelectorAll('line'), 'y1')
          });
        }
        var doorNodes = root.querySelectorAll('.lp-fronts [data-front="door"]');
        var doors = [];
        for (var j = 0; j < doorNodes.length; j += 1) {
          var node = doorNodes[j];
          doors.push({
            id: node.getAttribute('data-id'),
            style: node.getAttribute('data-style'),
            hingeCount: node.querySelectorAll('.lp-door-hinge').length,
            gapCount: node.querySelectorAll('.lp-door-gap').length
          });
        }
        return {
          vertical: parseLines(partitionsV, 'x1'),
          verticalCount: partitionsV.length,
          horizontal: parseLines(partitionsH, 'y1'),
          horizontalCount: partitionsH.length,
          shelves: shelves,
          doors: doors
        };
      })();
    JAVASCRIPT
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

  def normalize_numeric_array(values)
    Array(values).map { |value| value.to_f.round(3) }
  end
end
