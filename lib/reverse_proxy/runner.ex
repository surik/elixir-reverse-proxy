defmodule ReverseProxy.Runner do
  @type upstream :: [String.t] | {Atom.t, Keyword.t}

  @spec retreive(Plug.Conn.t, upstream) :: Plug.Conn.t
  def retreive(conn, upstream)
  def retreive(conn, {plug, opts}) when plug |> is_atom do
    options = plug.init(opts)
    plug.call(conn, options)
  end
  def retreive(conn, servers) do
    server = upstream_select(servers)
    {method, url, body, headers} = prepare_request(server, conn)

    HTTPoison.request(method, url, body, headers, timeout: 5_000)
      |> process_response(conn)
  end

  defp prepare_request(server, conn) do
    conn = conn |> Plug.Conn.put_req_header("x-forwarded-for", conn.remote_ip |> ip_to_string)
    method = conn.method |> String.downcase |> String.to_atom
    url = "#{conn.scheme}://#{server}#{conn.request_path}?#{conn.query_string}"
    headers = conn.req_headers
    {:ok, body, _conn} = Plug.Conn.read_body(conn)

    {method, url, body, headers}
  end

  defp process_response({:error, _}, conn) do
    conn |> Plug.Conn.send_resp(502, "Bad Gateway")
  end
  defp process_response({:ok, response}, conn) do
    conn
      |> put_resp_headers(response.headers)
      |> Plug.Conn.send_resp(response.status_code, response.body)
  end

  defp put_resp_headers(conn, []), do: conn
  defp put_resp_headers(conn, [{header, value}|rest]) do
    case header |> String.downcase do
      # TODO: quick fix for chunked-encoded responses.
      # the real fix is to deliver the content from the
      # reverse proxy as it is.
      "transfer-encoding" -> conn

      # TODO: quick fix: do not deliver "connection: close" to
      # our receiver just because "we" want to close the connection
      # to the reverse-proxy.
      "connection"        -> conn
      header              -> conn |> Plug.Conn.put_resp_header(header, value)
    end
      |> put_resp_headers(rest)
  end

  defp ip_to_string({a,b,c,d}), do: "#{a}.#{b}.#{c}.#{d}"

  defp upstream_select(servers) do
    servers |> hd
  end
end
