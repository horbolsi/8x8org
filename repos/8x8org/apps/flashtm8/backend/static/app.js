async function post(url, body){
  const r = await fetch(url, {method:"POST", headers:{"Content-Type":"application/json"}, body: JSON.stringify(body||{})});
  return await r.json();
}
async function get(url){
  const r = await fetch(url);
  return await r.json();
}

const el = id => document.getElementById(id);

function addChat(cls, text){
  const d = document.createElement("div");
  d.className = cls;
  d.textContent = text;
  el("chatOut").appendChild(d);
  el("chatOut").scrollTop = el("chatOut").scrollHeight;
}

async function refreshConfig(){
  const res = await get("/api/config");
  if(!res.ok) return;
  const cfg = res.config || {};
  ["AI_PROVIDER","LOCAL_MODEL_PATH","OLLAMA_BASE_URL","EXEC_ENABLED","WRITE_ENABLED"].forEach(k=>{
    if(cfg[k] !== undefined) el(k).value = cfg[k];
  });
}

async function health(){
  const h = await get("/api/health");
  if(h.ok){
    el("status").textContent = `✅ Online • Provider: ${h.provider} • Indexed DB: ${h.indexed_exists}`;
  } else {
    el("status").textContent = "⚠️ Offline";
  }
}

el("btnIndex").onclick = async ()=>{
  el("searchOut").textContent = "Indexing...";
  const res = await post("/api/index",{});
  el("searchOut").textContent = JSON.stringify(res,null,2);
  await health();
};

el("btnSearch").onclick = async ()=>{
  const q = el("searchQ").value.trim();
  if(!q) return;
  el("searchOut").textContent = "Searching...";
  const res = await post("/api/search",{q});
  el("searchOut").textContent = JSON.stringify(res,null,2);
};

el("btnSend").onclick = async ()=>{
  const m = el("msg").value.trim();
  if(!m) return;
  el("msg").value = "";
  addChat("msgUser", "You: " + m);
  const res = await post("/api/chat",{message:m});
  if(res.ok){
    addChat("msgBot", "FlashTM8: " + res.reply);
    el("provider").textContent = "Provider used: " + (res.provider || "unknown");
  } else {
    addChat("msgBot", "FlashTM8: Error: " + (res.error || "unknown"));
    el("provider").textContent = "Provider used: " + (res.provider || "unknown");
  }
};

el("btnSave").onclick = async ()=>{
  const payload = {
    AI_PROVIDER: el("AI_PROVIDER").value.trim(),
    LOCAL_MODEL_PATH: el("LOCAL_MODEL_PATH").value.trim(),
    OLLAMA_BASE_URL: el("OLLAMA_BASE_URL").value.trim(),
    OPENAI_API_KEY: el("OPENAI_API_KEY").value.trim(),
    GEMINI_API_KEY: el("GEMINI_API_KEY").value.trim(),
    DEEPSEEK_API_KEY: el("DEEPSEEK_API_KEY").value.trim(),
    EXEC_ENABLED: el("EXEC_ENABLED").value.trim(),
    WRITE_ENABLED: el("WRITE_ENABLED").value.trim(),
  };
  const res = await post("/api/config", payload);
  el("saveMsg").textContent = res.ok ? "✅ Saved. Restart FlashTM8 for full apply." : ("❌ Failed: " + (res.error||""));
  await health();
};

(async ()=>{
  await health();
  await refreshConfig();
})();
