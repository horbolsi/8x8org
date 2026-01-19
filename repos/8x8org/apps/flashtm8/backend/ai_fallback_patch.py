"""
FlashTM8 fallback helper:
- If your AI provider is OFF, you can still return results using workspace index context.
This file does NOT break anything by itself; it is safe.
"""
def fallback_answer(user_msg: str, ctx: list[dict] | None = None) -> str:
    ctx = ctx or []
    lines = []
    lines.append("⚡ FlashTM8 (Fallback Mode)\n")
    lines.append("AI provider is offline, but I can still help using indexed workspace results.\n")
    if not ctx:
        lines.append("No indexed matches found. Try using Search or click Index Workspace again.\n")
    else:
        lines.append("Top matching files/snippets:\n")
        for i, c in enumerate(ctx[:8], 1):
            path = c.get("path","(unknown)")
            score = c.get("score","?")
            snippet = (c.get("snippet","") or "").strip()
            lines.append(f"{i}) {path} (score={score})")
            if snippet:
                lines.append(snippet[:800])
            lines.append("")
    lines.append("✅ Tip: Ask things like: 'How do I run the dashboard and the bot?'")
    return "\n".join(lines)
