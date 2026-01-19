const { safeOllamaChatText } = require("./ollama_client");

(async () => {
  // JSON mode = best for exact machine output
  const raw = await safeOllamaChatText(
    'Return JSON only: {"reply":"OK ✅"}',
    "phi3:mini",
    { format: "json", temperature: 0 }
  );

  // raw should itself be JSON text if model obeyed
  // If it returns a JSON string, parse it:
  try {
    const obj = JSON.parse(raw);
    console.log(obj.reply);
  } catch {
    // fallback print
    console.log(raw);
  }
})();
