# A chess board you can push pieces around on.
#
#     mix run examples/chess.exs
#
# There are no rules here and no opponent: click a piece, click a square, the
# piece goes there. What it demonstrates is that a complete interactive
# graphical application can be written as a pure function from a model to a
# declaration, with no GLSL, no buffers, and no rendering code at all.
#
# The whole board is one visual:
#
#   * `:image` for the squares — an 8x8 texture, one byte per square, through a
#     four-stop colormap. The selection is *in* that texture rather than being
#     a separate highlight layer, because "this square is selected" is a
#     property of the square.
#   * `:text` twice for the pieces, once per colour, using the Unicode chess
#     glyphs from the bundled DejaVu atlas.
#
# Every one of those layers is declared from the model. Clicking does not draw
# anything; it updates a map, and `view/1` runs again.

# wx_mvu narrates every intent and wx event at debug level. At 30 fps with the
# mouse moving that buries anything worth reading.
Logger.configure(level: :info)

defmodule ChessDemo do
  @moduledoc false

  use WxMVU.Scene

  alias WxMVU.Font

  # The board fits itself to whatever the canvas turns out to be, rather than
  # assuming the size it asked for. A sizer is entitled to give a widget a
  # different size than it requested, and on a HiDPI display the physical
  # surface is larger again - so the only honest source for "how big is the
  # board" is the surface telling us.
  @initial 640

  # Byte values in the square texture. Four rather than two so that a selected
  # light square and a selected dark square stay distinguishable.
  @light 0
  @dark 85
  @light_selected 170
  @dark_selected 255

  @squares [
    {0.0, {236, 217, 185}},
    {1 / 3, {174, 137, 104}},
    {2 / 3, {246, 234, 130}},
    {1.0, {206, 190, 90}}
  ]

  @glyphs %{
    {:white, :king} => "♔",
    {:white, :queen} => "♕",
    {:white, :rook} => "♖",
    {:white, :bishop} => "♗",
    {:white, :knight} => "♘",
    {:white, :pawn} => "♙",
    {:black, :king} => "♚",
    {:black, :queen} => "♛",
    {:black, :rook} => "♜",
    {:black, :bishop} => "♝",
    {:black, :knight} => "♞",
    {:black, :pawn} => "♟"
  }

  @back [:rook, :knight, :bishop, :queen, :king, :bishop, :knight, :rook]

  # ==========================================================================
  # Model
  # ==========================================================================

  def init(_opts) do
    %{
      # {file, rank} => {colour, piece}. Rank 0 is the top of the screen,
      # which is black's back rank.
      board: starting_position(),
      selected: nil,
      moves: 0,
      # Updated by the visual's :resize event. Squares are square even when the
      # canvas is not, so the board is the largest square that fits, centred.
      surface: {@initial, @initial},
      status: "Click a piece, then click where it should go.",
      # Loaded once. Layout needs the metrics to centre a glyph in its square,
      # and a font is immutable, so it belongs in the model like any other
      # value the view is a function of.
      font: Font.load(:dejavu_sans)
    }
  end

  defp starting_position do
    back_rank = fn rank, colour ->
      @back
      |> Enum.with_index()
      |> Map.new(fn {piece, file} -> {{file, rank}, {colour, piece}} end)
    end

    pawns = fn rank, colour ->
      Map.new(0..7, fn file -> {{file, rank}, {colour, :pawn}} end)
    end

    %{}
    |> Map.merge(back_rank.(0, :black))
    |> Map.merge(pawns.(1, :black))
    |> Map.merge(pawns.(6, :white))
    |> Map.merge(back_rank.(7, :white))
  end

  # ==========================================================================
  # Input
  # ==========================================================================

  # The only event this application has. Note what it does not do: it draws
  # nothing, touches no GL state, and does not know the board is a texture.
  def handle_event({:ui_event, :board, :resize, %{logical_size: size}}, model) do
    %{model | surface: size}
  end

  def handle_event({:ui_event, :board, :mouse, %{type: :down, u: u, v: v}}, model) do
    case square_at(model, u, v) do
      nil ->
        %{model | selected: nil, status: "Off the board."}

      square ->
        select(model, square)
    end
  end

  def handle_event({:ui_event, :reset_btn, :click}, model) do
    %{model | board: starting_position(), selected: nil, moves: 0, status: "Reset."}
  end

  def handle_event({:ui_event, :clear_btn, :click}, model) do
    %{model | board: %{}, selected: nil, status: "Board cleared. Reset to put them back."}
  end

  def handle_event(_event, model), do: model

  defp select(model, square) do
    case {model.selected, Map.get(model.board, square)} do
      {nil, nil} ->
        %{model | status: "Empty square. Click a piece first."}

      {nil, {colour, piece}} ->
        %{model | selected: square, status: "#{name(colour, piece)} — click a destination."}

      {^square, _} ->
        %{model | selected: nil, status: "Deselected."}

      {from, _} ->
        move(model, from, square)
    end
  end

  # Surface fraction to board square. The board is the whole canvas, so this is
  # just which eighth of it was clicked.
  defp square_at(_model, u, v) do
    file = trunc(u * 8)
    rank = trunc(v * 8)

    if file in 0..7 and rank in 0..7, do: {file, rank}, else: nil
  end

  # One cell, in logical points.
  #
  # The board covers the entire canvas rather than a centred square inside it,
  # because the squares layer is a fullscreen quad and always will. Letterbox
  # the pieces into a square while the image stretches to a 680x640 canvas and
  # they drift off their squares by a file's width by the h-file - which is
  # exactly what happened here. Correctness comes from following the surface;
  # keeping the surface square is the window's job, below.
  defp cell(%{surface: {width, height}}), do: {width / 8, height / 8}

  defp piece_size(model) do
    {cell_width, cell_height} = cell(model)
    min(cell_width, cell_height) * 0.78
  end

  defp move(model, from, to) do
    {colour, piece} = Map.fetch!(model.board, from)
    captured = Map.get(model.board, to)

    board =
      model.board
      |> Map.delete(from)
      |> Map.put(to, {colour, piece})

    status =
      case captured do
        nil ->
          "#{name(colour, piece)} to #{algebraic(to)}."

        {other, taken} ->
          "#{name(colour, piece)} takes #{name(other, taken)} on #{algebraic(to)}."
      end

    %{model | board: board, selected: nil, moves: model.moves + 1, status: status}
  end

  # ==========================================================================
  # View
  # ==========================================================================

  def view(model) do
    [
      # Width, not width + margin: the canvas is expanded to the panel's full
      # width whatever the sizer is told, so the window's width *is* the
      # board's width. Everything still works if that stops being true - the
      # layout follows the surface - it just stops being square.
      {:ensure_window, :main, title: "wx_mvu — chess", size: {@initial, @initial + 130}},
      {:ensure_panel, :root, :main, []},
      {:ensure_widget, :status, :static_text, :root, label: model.status},
      {:set, :status, label: model.status},
      {:ensure_widget, :count, :static_text, :root, label: "moves: #{model.moves}"},
      {:set, :count, label: "moves: #{model.moves}"},
      {:ensure_widget, :reset_btn, :button, :root, label: "Reset"},
      {:ensure_widget, :clear_btn, :button, :root, label: "Clear"},
      {
        :ensure_visual,
        :board,
        :layers,
        :root,
        # view/1 runs in the scene process, so this is where mouse events go.
        size: {@initial, @initial},
        fps: 30,
        notify: self(),
        layers: [
          squares:
            {
              :image,
              # A square is a thing, not a sample of a continuum. Interpolating
              # between two of them would produce a colour that means nothing
              # and a board with soft edges.
              grid: {8, 8},
              domain: {0.0, 1.0},
              colormap: @squares,
              format: :r8,
              filter: :nearest,
              data: squares(model)
            },
          white:
            {:text,
             runs: runs(model, :white), size: piece_size(model), color: {1.0, 1.0, 1.0, 1.0}},
          black:
            {:text,
             runs: runs(model, :black), size: piece_size(model), color: {0.1, 0.1, 0.12, 1.0}}
        ]
      },
      {:layout, :root,
       {:vbox, [padding: 12],
        [
          {:hbox, [], [:status]},
          {:spacer, 4},
          {:hbox, [], [:count, {:spacer, 16}, :reset_btn, {:spacer, 8}, :clear_btn]},
          {:spacer, 8},
          # Not :expand. The board must stay square, and a sizer that stretches
          # it to the panel would make the squares 85x83 while the pieces are
          # placed on a square grid.
          {:board, proportion: 0, flag: []}
        ]}},
      {:refresh, :main}
    ]
  end

  # One byte per square - and **bottom row first**.
  #
  # A texture's first row is the bottom one as far as OpenGL is concerned, so
  # a field written top-down renders vertically mirrored. The pieces are
  # positioned in screen coordinates and the squares are sampled in texture
  # coordinates; nothing warns you that the two disagree, because each half
  # looks entirely correct on its own. The symptom is clicking a1 and watching
  # a8 light up.
  defp squares(model) do
    for rank <- 7..0//-1, file <- 0..7, into: <<>> do
      selected? = model.selected == {file, rank}
      light? = rem(file + rank, 2) == 0

      case {light?, selected?} do
        {true, false} -> <<@light>>
        {false, false} -> <<@dark>>
        {true, true} -> <<@light_selected>>
        {false, true} -> <<@dark_selected>>
      end
    end
  end

  # Every piece of one colour, as one text layer: a glyph and the pixel
  # position to draw it at. Centred by measuring, because the chess glyphs are
  # not all the same width and a knight drifting left of its square is the
  # kind of thing you notice without being able to say why.
  defp runs(model, colour) do
    {cell_width, cell_height} = cell(model)
    size = piece_size(model)

    for {{file, rank}, {piece_colour, piece}} <- model.board, piece_colour == colour do
      glyph = Map.fetch!(@glyphs, {colour, piece})
      {width, height} = Font.measure(model.font, glyph, size: size)

      x = file * cell_width + (cell_width - width) / 2
      y = rank * cell_height + (cell_height - height) / 2

      {{x, y}, glyph}
    end
  end

  # ==========================================================================

  defp name(colour, piece) do
    "#{colour} #{piece}"
  end

  defp algebraic({file, rank}) do
    <<?a + file>> <> Integer.to_string(8 - rank)
  end
end

WxMVU.start_scene(ChessDemo)

# `mix run` would exit immediately otherwise, taking the window with it.
unless IEx.started?() do
  Process.sleep(:infinity)
end
