# Reference copy — drop into Oxygen's `src/mcpviewer.jl`.
#
# This repository is the viewer only and ships no Julia project, so this file
# is not compiled here. It mirrors the Swagger/Redoc pattern: read the vendored
# JS/CSS and call a global mount function from an inline script.

const MCP_VIEWER_VERSION = "mcpviewer"

"""
    mcpviewerhtml(endpoint::String) :: HTTP.Response

Return an HTML page that mounts the MCP viewer against `endpoint`.
"""
function mcpviewerhtml(endpoint::String) :: HTTP.Response

    # load static content files
    viewerjs = readstaticfile("$MCP_VIEWER_VERSION/mcpviewer.js")
    viewerstyles = readstaticfile("$MCP_VIEWER_VERSION/mcpviewer.css")

    html("""
        <!DOCTYPE html>
        <html lang="en">

        <head>
            <title>MCP Viewer</title>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <meta name="description" content="MCP Viewer" />
            <style>$viewerstyles</style>
        </head>

        <body>
            <div id="mcp-viewer"></div>
            <script>$viewerjs</script>
            <script>
                window.McpViewer({ endpoint: "$endpoint", domId: "mcp-viewer" });
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
#       () -> mcpviewerhtml(join_url_path(ctx.service.prefix[], mcp_path)),
#   )
