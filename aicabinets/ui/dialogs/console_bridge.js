(function () {
  'use strict';

  var global = window;
  var namespace = 'AICabinetsConsoleBridge';
  if (global[namespace]) {
    return;
  }

  var documentElement = global.document && global.document.documentElement;
  var dialogId = null;
  if (documentElement && typeof documentElement.getAttribute === 'function') {
    dialogId = documentElement.getAttribute('data-dialog-id');
  }
  if (!dialogId) {
    dialogId = (global.location && global.location.href) || 'unknown';
  }

  var pendingEvents = [];
  var flushTimer = null;

  function nowISO() {
    try {
      return new Date().toISOString();
    } catch (error) {
      return null;
    }
  }

  function canDispatch() {
    return (
      global.sketchup &&
      typeof global.sketchup.__aicabinets_report_console_event === 'function'
    );
  }

  function ensureFlushTimer() {
    if (flushTimer !== null) {
      return;
    }

    flushTimer = global.setInterval(function () {
      if (canDispatch()) {
        global.clearInterval(flushTimer);
        flushTimer = null;
        flushQueue();
      }
    }, 50);
  }

  function toInteger(value) {
    if (typeof value === 'number' && isFinite(value)) {
      return Math.floor(value);
    }
    var parsed = Number(value);
    if (isFinite(parsed)) {
      return Math.floor(parsed);
    }
    return null;
  }

  function stringifyValue(value) {
    if (value == null) {
      return '';
    }

    if (typeof value === 'string') {
      return value;
    }

    if (value instanceof Error) {
      if (typeof value.stack === 'string' && value.stack.length) {
        return value.stack;
      }
      if (typeof value.message === 'string') {
        return value.message;
      }
      return value.toString();
    }

    try {
      return JSON.stringify(value);
    } catch (error) {
      try {
        return String(value);
      } catch (stringError) {
        return '[object Object]';
      }
    }
  }

  function serializeArguments(args) {
    if (!args || !args.length) {
      return [];
    }

    return Array.prototype.map.call(args, function (value) {
      if (value instanceof Error) {
        return {
          message: typeof value.message === 'string' ? value.message : String(value),
          stack: typeof value.stack === 'string' ? value.stack : null
        };
      }

      if (value == null) {
        return value;
      }

      if (typeof value === 'string') {
        return value;
      }

      try {
        return JSON.parse(JSON.stringify(value));
      } catch (error) {
        try {
          return String(value);
        } catch (stringError) {
          return Object.prototype.toString.call(value);
        }
      }
    });
  }

  function normalizeMessage(args) {
    if (!args || !args.length) {
      return '';
    }

    var parts = [];
    for (var index = 0; index < args.length; index += 1) {
      parts.push(stringifyValue(args[index]));
    }
    return parts.join(' ');
  }

  function buildEvent(level, message) {
    var event = {
      dialogId: dialogId || 'unknown',
      level: level,
      message: typeof message === 'string' ? message : stringifyValue(message),
      timestamp: nowISO()
    };
    return event;
  }

  function enqueueEvent(event) {
    pendingEvents.push(event);
    flushQueue();
  }

  function flushQueue() {
    if (!canDispatch()) {
      ensureFlushTimer();
      return;
    }

    ensureFlushTimer();

    while (pendingEvents.length) {
      var event = pendingEvents.shift();
      try {
        global.sketchup.__aicabinets_report_console_event(JSON.stringify(event));
      } catch (error) {
        pendingEvents.unshift(event);
        ensureFlushTimer();
        break;
      }
    }
  }

  function recordConsoleError(args) {
    var event = buildEvent('error', normalizeMessage(args));
    event.details = {
      arguments: serializeArguments(args)
    };

    if (args && args.length) {
      var first = args[0];
      if (first instanceof Error) {
        event.stack = typeof first.stack === 'string' ? first.stack : null;
      }
    }

    enqueueEvent(event);
  }

  function recordWindowError(message, source, lineno, colno, error) {
    var event = buildEvent('error', message);
    event.url = typeof source === 'string' ? source : null;
    var lineNumber = toInteger(lineno);
    if (lineNumber !== null) {
      event.line = lineNumber;
    }
    var columnNumber = toInteger(colno);
    if (columnNumber !== null) {
      event.column = columnNumber;
    }
    if (error instanceof Error) {
      event.stack = typeof error.stack === 'string' ? error.stack : null;
      if (!event.message && typeof error.message === 'string') {
        event.message = error.message;
      }
    } else if (typeof error === 'string' && !event.stack) {
      event.stack = error;
    }
    enqueueEvent(event);
  }

  function recordUnhandledRejection(reason) {
    var message = stringifyValue(reason);
    var event = buildEvent('error', message);

    if (reason instanceof Error) {
      event.stack = typeof reason.stack === 'string' ? reason.stack : null;
    }

    enqueueEvent(event);
  }

  var originalConsole = global.console || {};
  global.console = originalConsole;
  var originalError = originalConsole.error;

  if (originalConsole && typeof originalConsole.error === 'function') {
    originalConsole.error = function () {
      recordConsoleError(arguments);
      return originalError.apply(this, arguments);
    };
  } else {
    originalConsole.error = function () {
      recordConsoleError(arguments);
    };
  }

  var previousOnError = global.onerror;
  global.onerror = function () {
    recordWindowError.apply(null, arguments);
    if (typeof previousOnError === 'function') {
      try {
        return previousOnError.apply(this, arguments);
      } catch (error) {
        recordConsoleError([error]);
      }
    }
    return false;
  };

  global.addEventListener('unhandledrejection', function (event) {
    try {
      recordUnhandledRejection(event ? event.reason : undefined);
    } catch (error) {
      recordConsoleError([error]);
    }
  });

  global.addEventListener('DOMContentLoaded', flushQueue);
  global.addEventListener('load', flushQueue);

  ensureFlushTimer();

  global[namespace] = {
    flush: flushQueue,
    pendingEvents: function () {
      return pendingEvents.slice();
    }
  };
})();
