(function () {
  'use strict';

  function invokeSketchUp(action, payload) {
    if (window.sketchup && typeof window.sketchup[action] === 'function') {
      window.sketchup[action](payload);
    }
  }

  function handleButtonClick(event) {
    var target = event.target;
    if (!(target instanceof HTMLButtonElement)) {
      return;
    }

    var action = target.getAttribute('data-action');
    if (!action) {
      return;
    }

    invokeSketchUp(action);
  }

  document.addEventListener('click', handleButtonClick);
})();
