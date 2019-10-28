alias Hui.Query
alias Hui.Encode

defprotocol Hui.Encoder do
  @moduledoc """
  A protocol that underpins Solr query encoding.
  """

  @type options :: keyword

  @type querying_struct :: Query.Standard.t | Query.Common.t | Query.DisMax.t
  @type faceting_struct :: Query.Facet.t | Query.FacetRange.t | Query.FacetInterval.t
  @type highlighting_struct :: Query.Highlight.t

  @type solr_struct :: querying_struct | faceting_struct | highlighting_struct
  @type query :: map | solr_struct

  @doc """
  Transform `query` into IO data.

  The argument `opts` can be used to control encoding, e.g. specifying output formats.
  """
  @spec encode(query, options) :: iodata
  def encode(query, opts \\ [])

end

defimpl Hui.Encoder, for: [Query.Standard, Query.Common, Query.DisMax] do
  def encode(query, _opts), do: Encode.encode( query|> Map.to_list ) |> IO.iodata_to_binary
end

# TODO: refactor implementation w.r.t. more generic `encode` functions by making use of `options` for passing prefixes and separators
defimpl Hui.Encoder, for: [Query.Facet, Query.FacetRange, Query.FacetInterval] do
  def encode(query, _opts), do: Encode.encode(query) |> IO.iodata_to_binary
end

defimpl Hui.Encoder, for: [Query.Highlight, Query.HighlighterUnified, Query.HighlighterOriginal, Query.HighlighterFastVector] do
  def encode(query, _opts) do
    field = if Map.has_key?(query, :field), do: query.field, else: ""
    Encode.encode(query, {"hl", field, query.per_field}) |> IO.iodata_to_binary
  end
end

defimpl Hui.Encoder, for: Query.MoreLikeThis do
  def encode(query, _opts) do
    Encode.encode(query, {"mlt", "", false}) |> IO.iodata_to_binary
  end
end

defimpl Hui.Encoder, for: Query.Suggest do
  def encode(query, _opts) do
    Encode.encode(query, {"suggest", "", false}) |> IO.iodata_to_binary
  end
end

defimpl Hui.Encoder, for: Query.SpellCheck do
  def encode(query, _opts) do
    Encode.encode(query, {"spellcheck", "", false}) |> IO.iodata_to_binary
  end
end

defimpl Hui.Encoder, for: Map do
  def encode(query, _opts), do: URI.encode_query(query)
end

defimpl Hui.Encoder, for: List do
  # encode a list of map or structs
  def encode([x|y], _opts) when is_map(x) do
    [x|y] |> Enum.map_join("&", &Hui.Encoder.encode(&1))
  end

  # encode params in arbitrary keyword list
  def encode([x|y], _opts) when is_tuple(x) do
    URI.encode_query([x|y])
  end

  def encode([], _opts), do: ""
end