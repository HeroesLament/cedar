# Golden render tests need a real OpenGL 4.1 core context and a display, so
# they are excluded from the default run. They are the only layer that catches
# a shader which links cleanly and draws the wrong thing:
#
#     mix test --only gl
#
ExUnit.configure(exclude: [:gl])
ExUnit.start()
