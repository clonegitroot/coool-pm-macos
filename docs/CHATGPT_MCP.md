# ChatGPT connection and name privacy

Coool PM's MCP uses aliases for **every** connection, including local Codex/Claude clients. There is no switch to return real names.

- Projects: `Project <UUID>`; clients: `Client <UUID>`.
- Real project titles, client names, project/client numbers and client acronyms are omitted.
- Custom phases and calculation entries become `Phase 1`, `Entry 1`, etc. These labels can contain names, so they never leave through MCP responses.
- Addresses, contacts, PO numbers, documents and other free-text fields are not returned.
- UUIDs, relationships, workflow status and lock/archive flags remain available. Financial values require **Share financial totals** in Coool PM and the `--allow-financials` startup flag. Draft edits require **Allow draft edits** and `--allow-write`. Turning off either switch applies to subsequent requests in existing sessions.
- Write tools accept names and descriptions provided by the caller, save them locally, and return aliases. They do not echo those names back.
- Errors use controlled messages; raw database errors are not forwarded.

This is pseudonymisation, not a promise of complete anonymity: financial values and relationships may still be identifying. Text you type into ChatGPT is already sent to ChatGPT. This feature filters data returned by Coool PM, not your prompts or another client's own logs. It does not alter existing chat history or the local library.

## Account access first

Check [OpenAI's current account requirements](https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt) and [Secure MCP Tunnel guide](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels). Full custom MCP access is currently documented for Business and Enterprise/Edu; personal Plus is not listed. Do not buy another plan solely on the assumption this connection is available: verify the **Add custom MCP server** and tunnel permissions in your intended account first.

A tunnel can run the existing stdio MCP directly. No public HTTP bridge or inbound firewall port is required. The Mac and unlocked app must remain available.

## Set up an eligible account

1. Install the updated privacy-enabled app in `/Applications`. Quit older app/MCP processes and reconnect clients after updating. Older binaries do not provide this protection.
2. Enable Integrations and MCP in Coool PM Settings. Enable the corresponding Settings switch for each optional permission you want to grant. Keep the app unlocked.
3. Install the official `tunnel-client` using the download link in [Platform tunnel settings](https://platform.openai.com/settings/organization/tunnels) or the latest release at [openai/tunnel-client](https://github.com/openai/tunnel-client/releases/latest). Run `tunnel-client help quickstart`.
4. In Platform tunnel settings, create or reuse a tunnel associated with the intended ChatGPT workspace. Obtain the required runtime key locally (Tunnels Read + Use). Creation also requires Tunnels Read + Manage. Never put keys into this repository or chat.
5. In a local zsh terminal, enter the runtime key without displaying it:

   ```zsh
   read -rs 'CONTROL_PLANE_API_KEY?Runtime key (hidden): '; print
   export CONTROL_PLANE_API_KEY
   ```

6. Start the included launcher, replacing the example ID with the complete tunnel ID:

   ```zsh
   Scripts/connect-chatgpt.sh tunnel_0123456789abcdef0123456789abcdef
   ```

   Read-only and no financial access is the default. Add `--allow-write` for draft creation/editing and `--allow-financials` for amounts. The launcher checks that the installed server advertises name privacy before it starts a tunnel. It refuses older builds. No API key is written by the launcher; keep tunnel-client's own logging at its normal level and do not enable payload tracing.

7. Keep the foreground process running. In ChatGPT web, choose **Plugins → + → Add custom MCP server → Connection: Tunnel**, select the associated tunnel and review the tools. Account/workspace controls apply.
8. First ask it to list projects. Results must contain only `Project <UUID>` aliases, not actual titles. Select an alias/ID to work with a record. Then test draft creation only with fictional data.

Stop with Control-C and unset the credential with `unset CONTROL_PLANE_API_KEY`. Turning MCP off in Coool PM blocks subsequent library requests, including already initialized sessions.

## Verification status

Protocol and encrypted-library tests exercise alias responses for lists, project details (including financials), creation and calculation edits, alongside read/write restrictions. The launch script syntax and refusal of older binaries can be tested without starting a tunnel. A real ChatGPT connection is complete only after an eligible account's tunnel reports ready and a ChatGPT tool call succeeds. No account credential or tunnel is bundled with the app.
