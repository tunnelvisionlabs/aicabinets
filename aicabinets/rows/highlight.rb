# frozen_string_literal: true

# Backwards-compatible entry point that exposes the row highlight module under
# the expected require path. Overlay-based highlight implementation lives in
# `aicabinets/rows/overlay`.

Sketchup.require('aicabinets/rows/overlay')

