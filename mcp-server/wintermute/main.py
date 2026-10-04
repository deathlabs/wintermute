# Standard library imports.
from os import environ

# Third party imports.
from fastmcp import FastMCP
from fastmcp.server.providers.skills import SkillsDirectoryProvider
from starlette.requests import Request
from starlette.responses import JSONResponse

SKILLS_DIRECTORY = "skills"


def main() -> None:
    """Start the MCP server."""

    # Check if the FASTMCP_PORT environment variable is set.
    if "FASTMCP_PORT" not in environ:
        raise RuntimeError("The FASTMCP_PORT environment variable is not set.")

    # Get the FASTMCP_PORT environment variable.
    fastmcp_port = int(environ["FASTMCP_PORT"])

    # Init an MCP server.
    mcp = FastMCP(name="wintermute")

    # Register skills with the MCP server.
    mcp.add_provider(
        SkillsDirectoryProvider(
            roots=SKILLS_DIRECTORY,
        )
    )

    @mcp.custom_route("/api/v1/health", methods=["GET"])
    async def health(request: Request) -> JSONResponse:
        """Respond to health checks.

        Returns:
            A JSON-based response that indicates the service is running.
        """
        return JSONResponse(content={"status": "ok"})

    # Start the MCP server.
    mcp.run(
        transport="streamable-http",
        host="0.0.0.0",
        port=fastmcp_port,
    )


if __name__ == "__main__":
    main()
