const { safeOllamaEmbed } = require("./ollama_client");

(async () => {
  const v = await safeOllamaEmbed("hello embeddings test", "nomic-embed-text:latest");
  console.log("Embedding length:", v.length);
})();
