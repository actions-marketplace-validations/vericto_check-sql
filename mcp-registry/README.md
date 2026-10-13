# MCP Registry entry

`server.json` is the entry published to the official MCP Registry
(<https://registry.modelcontextprotocol.io>) as `com.vericto/sql-firewall`: the
remote Vericto MCP server at `https://mcp.vericto.com/mcp` (streamable HTTP,
`X-API-Key` header). It is kept here so anyone can see exactly what is listed.

Publishing uses DNS namespace verification for `vericto.com` (a `v=MCPv1` TXT
record at the apex) and `mcp-publisher`:

```bash
mcp-publisher login dns --domain vericto.com --private-key "<hex private key>"
mcp-publisher validate && mcp-publisher publish
```

Bump `version` for every change, because the registry rejects a version that is
already published.
