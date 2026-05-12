/**
 * Block all `bash` tool calls.
 *
 * The process-tome-comments workflow owns git/gh operations — the agent must
 * not branch, commit, push, or open PRs itself. Pi has no native --allowedTools
 * flag, so we block the `bash` tool via a tool_call hook. Read, Write, and
 * Edit (pi's defaults for file mutation) remain available.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event) => {
    if (event.toolName === "bash") {
      return {
        block: true,
        reason: "The bash tool is disabled in process-tome-comments. The workflow handles git and gh operations after your edits.",
      };
    }
    return undefined;
  });
}
