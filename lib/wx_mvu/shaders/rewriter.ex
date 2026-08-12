defmodule WxMVU.Shaders.Rewriter do
  @moduledoc """
  Rewrites naga-generated identifiers in GLSL to declared, stable names.

  naga names everything from its own internal counters. A uniform block comes
  out as `type_6_block_0Fragment`, samplers as `_group_0_binding_1_fs`, and
  struct fields as `member`, `member_1`, `member_2`. The block name is the key
  passed to `glGetUniformBlockIndex` and the sampler names are the keys passed
  to `glGetUniformLocation`, so committing them as-is couples the runtime to a
  naga type counter that shifts whenever a struct is added or naga is bumped.

  This module runs at build time, between naga and the committed artifact, and
  replaces those identifiers with names taken from a declaration. Nothing
  downstream ever sees a generated name.

  ## What it expects

  The shape naga produces for a rust-gpu uniform struct: an inner struct with
  the actual fields, wrapped in an outer struct, referenced by a block.

      struct type_5 { float member; float member_1; float member_2; };
      struct type_6 { type_5 member; };
      layout(std140) uniform type_6_block_0Fragment { type_6 _group_0_binding_0_fs; };

  becomes

      struct UniformsData { float row_offset; float domain_min; float domain_max; };
      struct UniformsBlock { UniformsData data; };
      layout(std140) uniform Uniforms { UniformsBlock u; };

  ## Why not a blind find-and-replace

  `member` and `member_1` also appear as fields of naga's `VertexOutput`
  struct, which must not be touched. Field renames are therefore scoped to the
  body of the specific struct and to the specific access chain, never applied
  globally.
  """

  @type spec :: %{
          required(:block) => %{name: String.t(), fields: [String.t() | atom()]},
          optional(:samplers) => %{non_neg_integer() => String.t()}
        }

  @block_pattern ~r/layout\(std140\)\s+uniform\s+(?<block>\w+)\s*\{\s*(?<outer>\w+)\s+(?<instance>\w+);\s*\}/
  @sampler_pattern ~r/uniform\s+sampler2D\s+(?<name>_group_(?<set>\d+)_binding_(?<binding>\d+)_\w+)\s*;/

  @doc """
  Derives the identifier mapping for a fragment shader.

  Returns `{:ok, mapping}` or `{:error, reason}`. The mapping is a plain map of
  generated name to declared name, plus the structural details needed to rewrite
  field accesses.
  """
  @spec derive(String.t(), spec()) :: {:ok, map()} | {:error, String.t()}
  def derive(glsl, spec) do
    with {:ok, block} <- find_block(glsl),
         {:ok, inner_type, wrapper_field} <- find_wrapper(glsl, block.outer),
         {:ok, fields} <- find_fields(glsl, inner_type),
         :ok <- check_arity(fields, spec.block.fields),
         {:ok, samplers} <- match_samplers(glsl, Map.get(spec, :samplers, %{})) do
      name = spec.block.name

      {:ok,
       %{
         block: {block.block, name},
         outer_type: {block.outer, name <> "Block"},
         inner_type: {inner_type, name <> "Data"},
         instance: {block.instance, "u"},
         wrapper_field: {wrapper_field, "data"},
         fields: Enum.zip(fields, Enum.map(spec.block.fields, &to_string/1)),
         samplers: samplers
       }}
    end
  end

  @doc """
  Applies a derived mapping to a GLSL source file.

  Safe to call on a shader that contains only some of the mapped identifiers -
  the vertex stage carries the struct declarations but no uniforms, so it gets
  the type renames and nothing else.
  """
  @spec apply_mapping(String.t(), map()) :: String.t()
  def apply_mapping(glsl, mapping) do
    glsl
    |> rename_tokens([
      mapping.block,
      mapping.outer_type,
      mapping.inner_type,
      mapping.instance
      | mapping.samplers
    ])
    |> rename_struct_fields(elem(mapping.outer_type, 1), [mapping.wrapper_field])
    |> rename_struct_fields(elem(mapping.inner_type, 1), mapping.fields)
    |> rename_accesses(
      elem(mapping.instance, 1),
      elem(mapping.wrapper_field, 0),
      elem(mapping.wrapper_field, 1),
      mapping.fields
    )
  end

  @doc """
  Rewrites both stages of a shader.

  Each stage is derived independently, because naga names a uniform block per
  stage: the same block is `..._block_0Fragment` in one file and
  `..._block_0Vertex` in the other, with instance variables suffixed `_fs` and
  `_vs`. Deriving once and applying to both would leave the vertex stage
  declaring a differently-named block, and GLSL links blocks by name - so the
  two stages would not share one block, and only one of them would receive the
  uniform data.

  A stage that does not reference the block at all still carries the struct
  declarations, so it falls back to the other stage's mapping for those.
  """
  @spec rewrite_pair(String.t(), String.t(), spec()) ::
          {:ok, %{vert: String.t(), frag: String.t()}, map()} | {:error, String.t()}
  def rewrite_pair(vert, frag, spec) do
    with {:ok, frag_mapping} <- derive(frag, spec) do
      vert_out =
        case derive(vert, spec) do
          {:ok, vert_mapping} -> apply_mapping(vert, vert_mapping)
          {:error, _no_block_in_this_stage} -> apply_mapping(vert, frag_mapping)
        end

      {:ok, %{vert: vert_out, frag: apply_mapping(frag, frag_mapping)}, frag_mapping}
    end
  end

  # ==========================================================================
  # Parsing
  # ==========================================================================

  defp find_block(glsl) do
    case Regex.named_captures(@block_pattern, glsl) do
      nil ->
        {:error, "no std140 uniform block found; naga's output shape may have changed"}

      %{"block" => block, "outer" => outer, "instance" => instance} ->
        {:ok, %{block: block, outer: outer, instance: instance}}
    end
  end

  defp find_wrapper(glsl, outer_type) do
    case struct_body(glsl, outer_type) do
      nil ->
        {:error, "could not find struct #{outer_type}"}

      body ->
        case Regex.run(~r/(\w+)\s+(\w+)\s*;/, body, capture: :all_but_first) do
          [inner_type, field] -> {:ok, inner_type, field}
          _ -> {:error, "struct #{outer_type} did not wrap a single struct as expected"}
        end
    end
  end

  defp find_fields(glsl, inner_type) do
    case struct_body(glsl, inner_type) do
      nil ->
        {:error, "could not find struct #{inner_type}"}

      body ->
        fields =
          ~r/\w+\s+(\w+)\s*;/
          |> Regex.scan(body, capture: :all_but_first)
          |> List.flatten()

        if fields == [],
          do: {:error, "struct #{inner_type} has no fields"},
          else: {:ok, fields}
    end
  end

  defp check_arity(found, declared) do
    if length(found) == length(declared) do
      :ok
    else
      {:error,
       "uniform block has #{length(found)} fields in the generated GLSL " <>
         "(#{Enum.join(found, ", ")}) but #{length(declared)} were declared " <>
         "(#{Enum.map_join(declared, ", ", &to_string/1)}). The shader and its " <>
         "declaration have diverged."}
    end
  end

  defp match_samplers(glsl, declared) do
    found =
      @sampler_pattern
      |> Regex.scan(glsl, capture: :all_names)
      |> Enum.map(fn captures ->
        # capture: :all_names returns groups sorted by name: binding, name, set
        [binding, name, _set] = captures
        {String.to_integer(binding), name}
      end)

    missing = Enum.reject(found, fn {binding, _} -> Map.has_key?(declared, binding) end)

    if missing == [] do
      {:ok, Enum.map(found, fn {binding, name} -> {name, Map.fetch!(declared, binding)} end)}
    else
      {:error,
       "generated GLSL has samplers at bindings " <>
         "#{missing |> Enum.map_join(", ", fn {b, _} -> b end)} with no declared name. " <>
         "Note that GLSL 410 merges each texture/sampler pair, so only the " <>
         "texture's binding survives."}
    end
  end

  defp struct_body(glsl, name) do
    case Regex.run(~r/struct\s+#{Regex.escape(name)}\s*\{(.*?)\}/s, glsl, capture: :all_but_first) do
      [body] -> body
      _ -> nil
    end
  end

  # ==========================================================================
  # Rewriting
  # ==========================================================================

  defp rename_tokens(glsl, pairs) do
    Enum.reduce(pairs, glsl, fn {old, new}, acc ->
      Regex.replace(~r/\b#{Regex.escape(old)}\b/, acc, new)
    end)
  end

  # Scoped to one struct's body, so identically-named fields elsewhere - notably
  # naga's VertexOutput, which also has `member` and `member_1` - are untouched.
  defp rename_struct_fields(glsl, struct_name, pairs) do
    pattern = ~r/(struct\s+#{Regex.escape(struct_name)}\s*\{)(.*?)(\})/s

    Regex.replace(pattern, glsl, fn _full, head, body, tail ->
      head <> rename_tokens(body, pairs) <> tail
    end)
  end

  defp rename_accesses(glsl, instance, wrapper_old, wrapper_new, fields) do
    Enum.reduce(fields, glsl, fn {old_field, new_field}, acc ->
      pattern =
        ~r/\b#{Regex.escape(instance)}\.#{Regex.escape(wrapper_old)}\.#{Regex.escape(old_field)}\b/

      Regex.replace(pattern, acc, "#{instance}.#{wrapper_new}.#{new_field}")
    end)
  end
end
