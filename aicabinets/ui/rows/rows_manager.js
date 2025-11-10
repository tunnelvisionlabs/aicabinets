(() => {
  const state = {
    rows: [],
    members: [],
    activeRowId: null,
    highlightEnabled: false,
    selectedMemberPid: null,
    pendingRequest: 0,
  };

  const pending = new Map();

  function nextRequestId() {
    state.pendingRequest += 1;
    return `rows-${Date.now()}-${state.pendingRequest}`;
  }

  function callRpc(method, params = {}) {
    return new Promise((resolve, reject) => {
      const requestId = nextRequestId();
      pending.set(requestId, { resolve, reject });
      const payload = JSON.stringify({ id: requestId, method, params });

      try {
        if (window.sketchup && typeof window.sketchup.rows_rpc === 'function') {
          window.sketchup.rows_rpc(payload);
        } else {
          console.warn('rows_rpc bridge unavailable');
          pending.delete(requestId);
          reject(new Error('rows_rpc bridge unavailable'));
        }
      } catch (error) {
        pending.delete(requestId);
        reject(error);
      }
    });
  }

  function showError(message) {
    console.error('Rows Manager:', message);
    if (window.sketchup && typeof window.sketchup.show_notification === 'function') {
      window.sketchup.show_notification('AI Cabinets', message);
    } else {
      alert(message);
    }
  }

  function refreshAll() {
    callRpc('rows.list')
      .then((result) => {
        state.rows = Array.isArray(result.rows) ? result.rows : [];
        renderRowsList();
        if (state.activeRowId) {
          refreshRow(state.activeRowId);
        } else if (state.rows.length > 0) {
          selectRow(state.rows[0].row_id);
        } else {
          applyRowDetail(null);
        }
      })
      .catch((error) => {
        showError(error.message || 'Unable to load rows.');
      });
  }

  function refreshRow(rowId) {
    if (!rowId) {
      applyRowDetail(null);
      return;
    }

    callRpc('rows.get', { row_id: rowId })
      .then((detail) => {
        applyRowDetail(detail);
      })
      .catch((error) => {
        showError(error.message || 'Unable to load row details.');
      });
  }

  function createRowFromSelection() {
    callRpc('rows.create_from_selection')
      .then((detail) => {
        applyRowDetail(detail);
        refreshAll();
      })
      .catch((error) => {
        showError(error.message || 'Unable to create row from selection.');
      });
  }

  function addSelectionToRow() {
    if (!state.activeRowId) {
      showError('Select a row before adding cabinets.');
      return;
    }

    callRpc('rows.selection')
      .then((selection) => {
        const pids = Array.isArray(selection.pids) ? selection.pids : [];
        if (pids.length === 0) {
          showError('Select at least one cabinet to add to the row.');
          return;
        }
        return callRpc('rows.add_members', { row_id: state.activeRowId, pids });
      })
      .then((detail) => {
        if (detail) {
          applyRowDetail(detail);
          refreshAll();
        }
      })
      .catch((error) => {
        showError(error.message || 'Unable to add cabinets to the row.');
      });
  }

  function removeSelectionFromRow() {
    if (!state.activeRowId) {
      showError('Select a row before removing cabinets.');
      return;
    }

    callRpc('rows.selection')
      .then((selection) => {
        const pids = Array.isArray(selection.pids) ? selection.pids : [];
        if (pids.length === 0) {
          showError('Select at least one row member to remove.');
          return;
        }
        return callRpc('rows.remove_members', { row_id: state.activeRowId, pids });
      })
      .then((detail) => {
        if (detail) {
          applyRowDetail(detail);
          refreshAll();
        }
      })
      .catch((error) => {
        showError(error.message || 'Unable to remove cabinets from the row.');
      });
  }

  function toggleHighlight() {
    if (!state.activeRowId) {
      showError('Select a row before highlighting.');
      return;
    }

    const desired = !state.highlightEnabled;
    callRpc('rows.highlight', { row_id: state.activeRowId, on: desired })
      .then((response) => {
        if (response && response.ok) {
          setHighlightState(desired);
        }
      })
      .catch((error) => {
        showError(error.message || 'Unable to toggle highlight.');
      });
  }

  function applyRowDetail(detail) {
    const row = detail && detail.row;
    if (!row) {
      state.activeRowId = null;
      state.members = [];
      state.selectedMemberPid = null;
      state.highlightEnabled = false;
      updateSummary(null);
      renderMembersList();
      updateHighlightButton();
      return;
    }

    state.activeRowId = row.row_id;
    state.members = Array.isArray(row.members) ? row.members.slice() : [];
    state.selectedMemberPid = null;

    updateSummary(row);
    renderMembersList();
    updateHighlightButton();
  }

  function updateSummary(row) {
    document.getElementById('row-id').textContent = row ? row.row_id : '—';
    document.getElementById('row-members-count').textContent = row ? (row.members ? row.members.length : 0) : 0;
    const revealInput = document.getElementById('row-reveal');
    const revealFormatted = document.getElementById('row-reveal-formatted');
    if (row) {
      revealInput.value = row.row_reveal_mm != null ? row.row_reveal_mm : '';
      revealFormatted.textContent = row.row_reveal_formatted || '';
      document.getElementById('row-lock-length').checked = !!row.lock_total_length;
    } else {
      revealInput.value = '';
      revealFormatted.textContent = '';
      document.getElementById('row-lock-length').checked = false;
    }
  }

  function renderRowsList() {
    const list = document.getElementById('rows-list');
    list.innerHTML = '';

    state.rows.forEach((row) => {
      const item = document.createElement('li');
      item.dataset.rowId = row.row_id;
      item.className = row.row_id === state.activeRowId ? 'active' : '';
      item.innerHTML = `
        <span class="title">${escapeHtml(row.name || row.row_id)}</span>
        <span class="meta">${row.member_count} members · ${escapeHtml(row.row_reveal_formatted || `${row.row_reveal_mm || 0} mm`)}</span>
      `;
      item.addEventListener('click', () => selectRow(row.row_id));
      list.appendChild(item);
    });
  }

  function renderMembersList() {
    const list = document.getElementById('members-list');
    list.innerHTML = '';

    state.members.forEach((member) => {
      const item = document.createElement('li');
      item.dataset.pid = member.pid;
      item.className = member.pid === state.selectedMemberPid ? 'active' : '';
      item.innerHTML = `
        <span>${escapeHtml(member.label || `Cabinet #${member.row_pos}`)}</span>
        <span class="meta">#${member.row_pos}</span>
      `;
      item.addEventListener('click', () => {
        state.selectedMemberPid = member.pid;
        renderMembersList();
      });
      list.appendChild(item);
    });
  }

  function selectRow(rowId) {
    if (!rowId) {
      applyRowDetail(null);
      return;
    }

    state.activeRowId = rowId;
    renderRowsList();
    refreshRow(rowId);
  }

  function moveSelectedMember(direction) {
    if (!state.activeRowId || state.members.length === 0) {
      return;
    }

    const index = state.members.findIndex((member) => member.pid === state.selectedMemberPid);
    if (index === -1) {
      return;
    }

    const newIndex = index + direction;
    if (newIndex < 0 || newIndex >= state.members.length) {
      return;
    }

    const swapped = state.members.slice();
    const [moved] = swapped.splice(index, 1);
    swapped.splice(newIndex, 0, moved);
    const order = swapped.map((member) => member.pid);

    callRpc('rows.reorder', { row_id: state.activeRowId, order })
      .then((detail) => {
        applyRowDetail(detail);
        state.selectedMemberPid = moved.pid;
        renderMembersList();
        refreshAll();
      })
      .catch((error) => {
        showError(error.message || 'Unable to reorder row members.');
      });
  }

  function applyRevealUpdate() {
    if (!state.activeRowId) {
      showError('Select a row before editing reveal.');
      return;
    }

    const revealInput = document.getElementById('row-reveal');
    const reveal = revealInput.value;
    callRpc('rows.update', { row_id: state.activeRowId, row_reveal_mm: reveal })
      .then((detail) => {
        applyRowDetail(detail);
        refreshAll();
      })
      .catch((error) => {
        showError(error.message || 'Unable to update row reveal.');
      });
  }

  function applyLockToggle() {
    if (!state.activeRowId) {
      return;
    }
    const lock = document.getElementById('row-lock-length').checked;
    callRpc('rows.update', { row_id: state.activeRowId, lock_total_length: lock })
      .then((detail) => {
        applyRowDetail(detail);
      })
      .catch((error) => {
        showError(error.message || 'Unable to update lock setting.');
      });
  }

  function updateHighlightButton() {
    const button = document.getElementById('toggle-highlight');
    button.textContent = state.highlightEnabled ? 'Disable Highlight' : 'Enable Highlight';
    button.disabled = !state.activeRowId;
  }

  function setHighlightState(enabled) {
    state.highlightEnabled = !!enabled;
    updateHighlightButton();
  }

  function escapeHtml(value) {
    return (value || '').toString().replace(/[&<>"']/g, (char) => {
      switch (char) {
        case '&':
          return '&amp;';
        case '<':
          return '&lt;';
        case '>':
          return '&gt;';
        case '"':
          return '&quot;';
        case "'":
          return '&#39;';
        default:
          return char;
      }
    });
  }

  function handleResponse(message) {
    try {
      const payload = typeof message === 'string' ? JSON.parse(message) : message;
      if (!payload || !payload.id) {
        return;
      }

      const entry = pending.get(payload.id);
      if (!entry) {
        return;
      }
      pending.delete(payload.id);

      if (payload.error) {
        entry.reject(payload.error);
      } else {
        entry.resolve(payload.result);
      }
    } catch (error) {
      console.error('Rows Manager response error', error);
    }
  }

  function bindEvents() {
    document.getElementById('create-row').addEventListener('click', createRowFromSelection);
    document.getElementById('add-selection').addEventListener('click', addSelectionToRow);
    document.getElementById('remove-selection').addEventListener('click', removeSelectionFromRow);
    document.getElementById('toggle-highlight').addEventListener('click', toggleHighlight);
    document.getElementById('apply-reveal').addEventListener('click', applyRevealUpdate);
    document.getElementById('row-lock-length').addEventListener('change', applyLockToggle);
    document.getElementById('move-up').addEventListener('click', () => moveSelectedMember(-1));
    document.getElementById('move-down').addEventListener('click', () => moveSelectedMember(1));
  }

  document.addEventListener('DOMContentLoaded', () => {
    bindEvents();
    refreshAll();
  });

  window.AICabinetsRows = {
    refreshAll,
    refreshRow,
    setHighlight: setHighlightState,
    receive: handleResponse,
  };
})();
