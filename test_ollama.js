async function safeOllamaChat(userText, wantedModel = "phi3:mini") {
  // 1) Get installed models
  const tagsRes = await fetch("http://127.0.0.1:11434/api/tags");
  const tags = await tagsRes.json();
  const installed = (tags.models || []).map(m => m.name);

  // 2) Choose model safely
  const model =
    installed.includes(wantedModel) ? wantedModel :
    installed.includes("llama3.2:1b") ? "llama3.2:1b" :
    installed[0];

  // 3) Request payload
  const payload = {
    model,
    messages: [{ role: "user", content: userText }],
    stream: false
  };

  // 4) Retry on 500
  for (let attempt = 1; attempt <= 3; attempt++) {
    const r = await fetch("http://127.0.0.1:11434/api/chat", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });

    if (r.ok) return await r.json();

    if (r.status !== 500) {
      const txt = await r.text();
      throw new Error(`Ollama chat failed (${r.status}): ${txt}`);
    }
  }

  throw new Error("Ollama chat failed after retries (500).");
}

(async () => {
  const res = await safeOllamaChat("hello from file test");
  console.log(JSON.stringify(res, null, 2));
})();
