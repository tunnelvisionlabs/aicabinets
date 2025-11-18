# frozen_string_literal: true

# Minimal sample used with `npm run sketchup:run`.
# Emits console message so the wrapper logging can be validated.
puts '[SampleSketchUpRun] Script started.'

if defined?(Sketchup)
  model = Sketchup.active_model
  puts "[SampleSketchUpRun] Active model title: #{model ? model.title : 'none'}"
else
  puts '[SampleSketchUpRun] SketchUp API unavailable.'
end

puts '[SampleSketchUpRun] Script complete.'
