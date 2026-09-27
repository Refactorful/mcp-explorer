# Reference copy — drop into Oxygen's `src/mcpexplorer.jl`.
#
# This repository is the explorer only and ships no Julia project, so this file
# is not compiled here. It mirrors the Swagger/Redoc pattern: read the vendored
# JS/CSS and call a global mount function from an inline script.

const MCP_EXPLORER_VERSION = "mcpexplorer"

"""
    mcpexplorerhtml(endpoint::String; execenabled::Union{Nothing,Bool}=nothing) :: HTTP.Response

Return an HTML page that mounts the MCP explorer against `endpoint`.

`execenabled` optionally turns tool execution on/off for this mount. When
omitted the viewer's build-time default applies.
"""
function mcpexplorerhtml(endpoint::String; execenabled::Union{Nothing,Bool}=nothing) :: HTTP.Response

    # load static content files
    viewerjs = readstaticfile("$MCP_EXPLORER_VERSION/mcpexplorer.js")
    viewerstyles = readstaticfile("$MCP_EXPLORER_VERSION/mcpexplorer.css")

    # Only emit `execEnabled` when the caller supplied it, so the viewer can fall
    # back to its build-time default (on in dev, off in production) otherwise.
    execoption = isnothing(execenabled) ? "" : ", execEnabled: $(execenabled)"

    html("""
        <!DOCTYPE html>
        <html lang="en">

        <head>
            <title>MCP Explorer</title>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <meta name="description" content="MCP Explorer" />
            <style>$viewerstyles</style>
        </head>

        <body>
            <div id="mcp-explorer"></div>
            <script>$viewerjs</script>
            <script>
                window.McpExplorer({ endpoint: "$endpoint", domId: "mcp-explorer"$execoption });
            </script>
        </body>

        </html>
    """)
end

# In `setupdocs` (`src/core.jl`), mounted only when the MCP endpoint is mounted:
#
#   register_internal(
#       ctx,
#       router,
#       "GET",
#       "$docspath/mcp",
#       () -> mcpexplorerhtml(join_url_path(ctx.service.prefix[], mcp_path)),
#   )
#
# Pass `execenabled=false` to turn execution off for the page:
#
#   () -> mcpexplorerhtml(join_url_path(ctx.service.prefix[], mcp_path); execenabled=false),
