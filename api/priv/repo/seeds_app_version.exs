# Script to seed a test app version for development
# Run with: mix run priv/repo/seeds_app_version.exs

alias TqfApi.Releases

# Create a stable version
{:ok, _stable} = Releases.create_app_version(%{
  version: "1.0.1",
  build_number: "1001",
  channel: "stable",
  release_notes: """
  ### What's New
  - Fixed crash on launch when Sparkle framework was missing
  - Added automatic update checking
  - Improved performance
  """,
  download_url: "https://thequickfox.ai/releases/TheQuickFox-1.0.1.zip",
  signature: "test-signature-stable",
  file_size: 15_000_000,
  minimum_os_version: "13.0",
  is_critical: false,
  published_at: DateTime.utc_now()
})

IO.puts("✅ Created stable version 1.0.1")

# Create a beta version
{:ok, _beta} = Releases.create_app_version(%{
  version: "1.1.0-beta.1",
  build_number: "1100",
  channel: "beta", 
  release_notes: """
  ### Beta Features
  - New UI improvements
  - Experimental features
  - Testing update system
  """,
  download_url: "https://thequickfox.ai/releases/TheQuickFox-1.1.0-beta.1.zip",
  signature: "test-signature-beta",
  file_size: 16_000_000,
  minimum_os_version: "13.0",
  is_critical: false,
  published_at: DateTime.utc_now()
})

IO.puts("✅ Created beta version 1.1.0-beta.1")