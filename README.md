# Features

## The library adds the following new features:
  * An FPS limiter, disabled by default
  * Ability to add and enable/disable event callbacks
  * Short-circuiting subsequent callbacks, by returning true from them, e.g. to capture input to UI
  * Maintains one copy of the module only, preventing errors should multiple libraries include their own copy

## The library adds the following new events:
  * **dispatch(event, ...)** - A dispatch event, to which all events are sent
  * **pre_update(dt)** - An event that runs before love.update()
  * **post_update(dt)** - An event that runs after love.update()
  * **postprocess(draw_dt)** - A second draw event, called after draw, can be used to draw overlay, profiling info, etc.
 
## The library provides the following functions:
  * **modrun.setup()** - Sets modrun up, replacing the original love.run
  * **modrun.registerEventType(event, fail_if_exists)** - Registers a new event, issues a warning, or optionally an error, if the event already exists
  * **modrun.addCallback(event, callback, self_obj, on_error)** - Registers a new callback for an event, optionally includes an error handler, and an object to be passed as "self"
  * **modrun.removeCallback(event, callback)** - Removes a previously registered callback
  * **modrun.enableCallback(event, callback)** - Enables a callback
  * **modrun.disableCallback(event, callback)** - Disables a callback, preventing it from being processed
  * **modrun.setFramerateLimit(fps)** - Set maximum FPS to the given value. Pass 0 or false to disable the limit. Only applies if vsync is disabled
  * **modrun.push(event, ...)** - Push an event to the queue. Essentially same as **love.event.push()**

For detailed documentation, check source