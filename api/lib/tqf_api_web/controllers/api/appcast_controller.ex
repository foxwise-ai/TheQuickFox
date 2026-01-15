defmodule TqfApiWeb.Api.AppcastController do
  use TqfApiWeb, :controller
  alias TqfApi.Releases
  alias TqfApi.Accounts

  @doc """
  Returns the appcast XML for Sparkle updates.
  - Authenticated users with beta flag get beta versions
  - Everyone else gets stable versions
  """
  def index(conn, _params) do
    version = get_appropriate_version(conn)
    
    xml_content = render_appcast_xml(version)
    
    conn
    |> put_resp_content_type("application/rss+xml")
    |> send_resp(200, xml_content)
  end

  defp get_appropriate_version(conn) do
    # Try to get user from auth token
    case get_user_from_token(conn) do
      {:ok, %{is_beta_tester: true}} ->
        # Beta tester - get latest beta version, fall back to stable if no beta
        Releases.get_latest_beta_version() || Releases.get_latest_stable_version()
      _ ->
        # Not authenticated or not a beta tester - get stable version
        Releases.get_latest_stable_version()
    end
  end

  defp get_user_from_token(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, device} <- Accounts.get_device_by_auth_token(token),
         {:ok, user} <- Accounts.get_user(device.user_id) do
      {:ok, user}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp render_appcast_xml(nil) do
    # No version available - return empty feed
    """
    <?xml version="1.0" standalone="yes"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
      <channel>
        <title>TheQuickFox</title>
        <language>en</language>
      </channel>
    </rss>
    """
  end

  defp render_appcast_xml(version) do
    release_notes_html = markdown_to_html(version.release_notes || "")
    
    """
    <?xml version="1.0" standalone="yes"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
      <channel>
        <title>TheQuickFox</title>
        <language>en</language>
        <item>
          <title>Version #{version.version}</title>
          #{if version.release_notes_url do
            ~s(<sparkle:releaseNotesLink>#{version.release_notes_url}</sparkle:releaseNotesLink>)
          else
            ~s(<description><![CDATA[#{release_notes_html}]]></description>)
          end}
          <pubDate>#{format_rfc2822_date(version.published_at)}</pubDate>
          <sparkle:minimumSystemVersion>#{version.minimum_os_version}</sparkle:minimumSystemVersion>
          #{if version.is_critical, do: ~s(<sparkle:criticalUpdate />), else: ""}
          <enclosure 
            url="#{version.download_url}"
            sparkle:version="#{version.version}"
            sparkle:shortVersionString="#{version.version}"
            sparkle:edSignature="#{version.signature}"
            length="#{version.file_size}"
            type="application/octet-stream" />
        </item>
      </channel>
    </rss>
    """
  end
  
  defp markdown_to_html(markdown) do
    case Earmark.as_html(markdown) do
      {:ok, html, _} -> html
      {:error, _, _} -> markdown
    end
  end

  defp format_rfc2822_date(nil), do: ""
  defp format_rfc2822_date(datetime) do
    # Format datetime as RFC 2822 for RSS
    # Example: Mon, 24 Sep 2024 12:00:00 +0000
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%a, %d %b %Y %H:%M:%S +0000")
  end
end