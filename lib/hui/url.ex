defmodule Hui.URL do
  @moduledoc """
  Struct and utilities for working with Solr URLs and parameters.

  Use the module `t:Hui.URL.t/0` struct to specify
  Solr core or collection URLs with request handlers.

  ### Hui URL endpoints

  ```
    # binary
    url = "http://localhost:8983/solr/collection"
    Hui.search(url, q: "loch")

    # key referring to config setting
    url = :library
    Hui.search(url, q: "edinburgh", rows: 10)

    # Hui.URL struct
    url = %Hui.URL{url: "http://localhost:8983/solr/collection", handler: "suggest"}
    Hui.search(url, suggest: true, "suggest.dictionary": "mySuggester", "suggest.q": "el")

  ```

  `t:Hui.URL.t/0` struct also enables HTTP headers and [HTTPoison options](https://hexdocs.pm/httpoison/HTTPoison.html#request/5)
  to be specified in keyword lists. HTTPoison options provide further controls for a request, e.g. `timeout`, `recv_timeout`,
  `max_redirect`, `params` etc.

  ```
    # setting up a header and a 10s receiving connection timeout
    url = %Hui.URL{url: "..", headers: [{"accept", "application/json"}], options: [recv_timeout: 10000]}
    Hui.search(url, q: "solr rocks")
  ```
  """

  defstruct [:url, handler: "select", headers: [], options: []]
  @type headers :: HTTPoison.Base.headers
  @type options :: Keyword.t

  @typedoc """
  Struct for a Solr endpoint with a request handler and any associated HTTP headers and options.

  ## Example

  ```
    %Hui.URL{handler: "suggest", url: "http://localhost:8983/solr/collection"}
  ```

  - `url`: typical endpoint including the core or collection name. This may also be a load balancer
  endpoint fronting several Solr upstreams.
  - `handler`: name of a Solr request handler that processes requests.
  - `headers`: HTTP headers.
  - `options`: [HTTPoison options](https://hexdocs.pm/httpoison/HTTPoison.html#request/5).

  """
  @type t :: %__MODULE__{url: nil | binary, handler: nil | binary, headers: nil | headers, options: nil | options}

  @typedoc """
  Solr parameters as keyword list or structs.
  """
  @type url_params :: Keyword.t | Hui.Q.t | Hui.D.t | Hui.F.t | Hui.F.Range.t | Hui.F.Interval.t

  @doc """
  Returns a configured default Solr endpoint as `t:Hui.URL.t/0` struct.

  ```
      Hui.URL.default_url!
      %Hui.URL{handler: "select", url: "http://localhost:8983/solr/gettingstarted", headers: [{"accept", "application/json"}], options: [recv_timeout: 10000]}
  ```
  The default endpoint can be specified in application configuration as below:

  ```
    config :hui, :default,
      url: "http://localhost:8983/solr/gettingstarted",
      handler: "select", # optional
      headers: [{"accept", "application/json"}],
      options: [recv_timeout: 10000]
  ```

  """
  @spec default_url! :: t | nil
  def default_url! do
    {status, default_url} = configured_url(:default)
    case status do
      :ok -> default_url
      :error -> nil
    end
  end

  @doc """
  Retrieve url configuration as `t:Hui.URL.t/0` struct.

  ## Example

      iex> Hui.URL.configured_url(:suggester)
      {:ok, %Hui.URL{handler: "suggest", url: "http://localhost:8983/solr/collection"}}

  The above retrieves the following endpoint configuration e.g. from `config.exs`:

  ```
    config :hui, :suggester,
      url: "http://localhost:8983/solr/collection",
      handler: "suggest"
  ```

  """
  @spec configured_url(atom) :: {:ok, t} | {:error, binary} | nil
  def configured_url(config_key) do
    url = Application.get_env(:hui, config_key)[:url]
    handler = Application.get_env(:hui, config_key)[:handler]
    headers = if Application.get_env(:hui, config_key)[:headers], do: Application.get_env(:hui, config_key)[:headers], else: []
    options = if Application.get_env(:hui, config_key)[:options], do: Application.get_env(:hui, config_key)[:options], else: []
    case {url,handler} do
      {nil, _} -> {:error, %Hui.Error{reason: :nxdomain}}
      {_, nil} -> {:ok, %Hui.URL{url: url, headers: headers, options: options}}
      {_, _} -> {:ok, %Hui.URL{url: url, handler: handler, headers: headers, options: options}}
    end
  end

  @doc false
  @spec encode_query(url_params) :: binary
  @deprecated "Please use Hui.Encoder instead"
  # coveralls-ignore-start
  def encode_query(%Hui.H3{} = url_params), do: encode_query(url_params |> Map.to_list |> Enum.sort)
  def encode_query(%Hui.F.Range{} = url_params), do: encode_query(url_params |> Map.to_list, "facet.range", url_params.range, url_params.per_field)
  def encode_query(%Hui.F.Interval{} = url_params), do: encode_query(url_params |> Map.to_list, "facet.interval", url_params.interval, url_params.per_field)
  def encode_query(url_params) when is_map(url_params), do: encode_query(url_params |> Map.to_list)

  def encode_query([{:__struct__, Hui.Q} | tail]), do: tail |> encode_query
  def encode_query([{:__struct__, Hui.F} | tail]), do: Enum.map(tail, &prefix/1) |> encode_query
  def encode_query([{:__struct__, Hui.H} | tail]), do: Enum.map(tail, &prefix(&1, "hl")) |> encode_query
  def encode_query([{:__struct__, Hui.H1} | tail]), do: Enum.map(tail, &prefix(&1, "hl")) |> encode_query
  def encode_query([{:__struct__, Hui.H2} | tail]), do: Enum.map(tail, &prefix(&1, "hl")) |> encode_query
  def encode_query([{:__struct__, Hui.H3} | tail]), do: Enum.map(tail, &prefix(&1, "hl")) |> encode_query
  def encode_query([{:__struct__, Hui.S} | tail]), do: Enum.map(tail, &prefix(&1, "suggest")) |> encode_query
  def encode_query([{:__struct__, Hui.Sp} | tail]), do: Enum.map(tail, &prefix(&1, "spellcheck")) |> encode_query
  def encode_query([{:__struct__, Hui.M} | tail]), do: Enum.map(tail, &prefix(&1, "mlt")) |> encode_query

  def encode_query(enumerable) when is_list(enumerable), do: Enum.reject(enumerable, &invalid_param?/1) |> Enum.map_join("&", &encode/1)
  def encode_query(_), do: ""

  def encode_query([{:__struct__, _struct} | tail], prefix, field, per_field), do: Enum.map(tail, &prefix(&1, prefix, field, per_field)) |> encode_query
  # coveralls-ignore-stop

  @doc "Returns the string representation (URL path) of the given `t:Hui.URL.t/0` struct."
  @spec to_string(t) :: binary
  defdelegate to_string(uri), to: String.Chars.Hui.URL

  # coveralls-ignore-start
  defp encode({k,v}) when is_list(v), do: Enum.reject(v, &invalid_param?/1) |> Enum.map_join("&", &encode({k,&1}))
  defp encode({k,v}) when is_binary(v), do: "#{k}=#{URI.encode_www_form(v)}"

  # when value is a also struct, e.g. %Hui.F.Range/Interval{}
  defp encode({_k,v}) when is_map(v), do: encode_query(v)

  defp encode({k,v}), do: "#{k}=#{v}"
  defp encode([]), do: ""
  defp encode(v), do: v

  # kv pairs with empty, nil or [] values
  defp invalid_param?(""), do: true
  defp invalid_param?(nil), do: true
  defp invalid_param?([]), do: true
  defp invalid_param?(x) when is_tuple(x), do: is_nil(elem(x,1)) or elem(x,1) == "" or elem(x, 1) == [] or elem(x,0) == :__struct__
  defp invalid_param?(_x), do: false

  # render kv pairs according to Solr prefix /per field syntax
  # e.g. `field: "year"` to `"facet.field": "year"`, `f.[field].facet.gap`
  defp prefix({k,v}) when k == :facet, do: {k,v}
  defp prefix({k,v}, prefix \\ "facet", field \\ "", per_field \\ false) do
    case {k,prefix} do
      {:facet, _} -> {:facet, v}
      {:hl, _} -> {:hl, v}
      {:suggest, _} -> {:suggest, v}
      {:spellcheck, _} -> {:spellcheck, v}
      {:mlt, _} -> {:mlt, v}
      {:range, "facet.range"} -> {:"facet.range", v} # render the same way despite per field setting
      {:method, "facet.range"} -> {:"facet.range.method", v} # ditto
      {:interval, "facet.interval"} -> {:"facet.interval", v} # ditto
      {:per_field, _} -> {k, nil} # do not render this field
      {:per_field_method, _} -> if per_field, do: {:"f.#{field}.#{prefix}.method", v}, else: {k, nil}
      {_, _} -> if per_field, do: {:"f.#{field}.#{prefix}.#{k}", v}, else: {:"#{prefix}.#{k}", v}
    end
  end
  # coveralls-ignore-stop

end

# implement `to_string` for %Hui.URL{} in Elixir generally via the String.Chars protocol
defimpl String.Chars, for: Hui.URL do
  def to_string(%Hui.URL{url: url, handler: handler}), do: [url, "/", handler] |> IO.iodata_to_binary
end
