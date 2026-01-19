const { safeOllamaChatText } = require("./ollama_client");

(async () => {
  // This should always work
  const text = await safeOllamaChatText("Say ONLY: OK ✅", "phi3:mini", {
    system: "Reply with exactly: OK ✅ (no extra text).",
    forceOK: true,
    temperature: 0,
  });

  console.log(text);
})();
