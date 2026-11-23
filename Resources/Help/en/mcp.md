# Connecting external AI through MCP

MCP is an optional local connection for Claude, Codex and other compatible clients. It is separate from the built-in local model and starts off.

1. Enable integrations in **Settings → Features** if they are hidden by your profile.
2. Open **Settings → Library**, enable MCP and choose whether the configuration may include financial data or draft creation.
3. Copy the generated configuration into the MCP client. The executable is **CooolPM-MCP** inside the app bundle; use the absolute path supplied by Settings.
4. With launch authentication enabled, keep Coool PM open and unlocked while the client uses the library.

Read tools can list clients and projects. Financial access adds rates, costs and reports. Write access can create clients, draft projects and calculation lines. Approved or archived calculations stay protected. Financial access and draft edits each require the matching Settings switch and startup flag. Turning a switch off revokes that permission for subsequent requests in existing sessions. Turn MCP off to stop all subsequent tool requests.

The external client decides whether to send returned data to its AI provider. Review that client's configuration before enabling sensitive access. Coool PM's local AI does not require MCP to be enabled.

[Read the data-sharing details](help://privacy) or [configure the local assistant](help://local-ai).

## Name privacy and ChatGPT

All MCP responses use stable aliases such as **Project <UUID>** and **Client <UUID>**. Real names and project/client numbers are withheld. Custom phase and entry labels become **Phase 1**, **Entry 1**, etc., because they may contain identifying text. IDs, links, statuses and explicitly permitted amounts remain visible. Text you type into an external AI is outside this filter; aliases do not guarantee complete anonymity.

Regular ChatGPT requires an eligible custom MCP account and a Secure MCP Tunnel (which can run the stdio helper directly). A local configuration alone does not connect it. See `docs/CHATGPT_MCP.md` in the source repository for setup and current account limitations. Older app/MCP processes must be restarted after installing the privacy-enabled build.
