const el=id=>document.getElementById(id);
async function post(url, body){
  const r=await fetch(url,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body||{})});
  return await r.json();
}
async function get(url){const r=await fetch(url);return await r.json();}

function chat(cls, txt){
  const d=document.createElement("div");
  d.className=cls;
  d.textContent=txt;
  el("chatlog").appendChild(d);
  el("chatlog").scrollTop=el("chatlog").scrollHeight;
}

async function refreshHealth(){
  const h=await get("/api/health");
  if(h.ok){
    el("health").textContent=`✅ Online • Provider: ${h.provider} • EXEC=${h.exec} • WRITE=${h.write}`;
  }else{
    el("health").textContent="⚠️ Offline";
  }
}

async function refreshConfig(){
  const r=await get("/api/config");
  if(!r.ok) return;
  const c=r.config||{};
  ["AI_PROVIDER","LOCAL_MODEL_PATH","OLLAMA_BASE_URL","EXEC_ENABLED","WRITE_ENABLED"].forEach(k=>{
    if(c[k]!==undefined) el(k).value=c[k];
  });
}

el("btnIndex").onclick=async()=>{
  el("out").textContent="Indexing workspace...";
  const r=await post("/api/index",{});
  el("out").textContent=JSON.stringify(r,null,2);
  await refreshHealth();
};

el("btnSearch").onclick=async()=>{
  const q=el("q").value.trim();
  if(!q) return;
  el("out").textContent="Searching...";
  const r=await post("/api/search",{q});
  el("out").textContent=JSON.stringify(r,null,2);
};

el("btnSend").onclick=async()=>{
  const m=el("msg").value.trim();
  if(!m) return;
  el("msg").value="";
  chat("msgU","You: "+m);
  const r=await post("/api/chat",{message:m});
  if(r.ok){
    chat("msgB","FlashTM8: "+r.reply);
    el("provider").textContent="Provider used: "+(r.provider||"unknown");
  }else{
    chat("msgB","FlashTM8: Error: "+(r.error||"unknown"));
    el("provider").textContent="Provider used: "+(r.provider||"unknown");
  }
};

el("btnSave").onclick=async()=>{
  const payload={
    AI_PROVIDER: el("AI_PROVIDER").value.trim(),
    LOCAL_MODEL_PATH: el("LOCAL_MODEL_PATH").value.trim(),
    OLLAMA_BASE_URL: el("OLLAMA_BASE_URL").value.trim(),
    OPENAI_API_KEY: el("OPENAI_API_KEY").value.trim(),
    GEMINI_API_KEY: el("GEMINI_API_KEY").value.trim(),
    DEEPSEEK_API_KEY: el("DEEPSEEK_API_KEY").value.trim(),
    XAI_API_KEY: el("XAI_API_KEY").value.trim(),
    EXEC_ENABLED: el("EXEC_ENABLED").value.trim(),
    WRITE_ENABLED: el("WRITE_ENABLED").value.trim(),
  };
  const r=await post("/api/config",payload);
  el("saveMsg").textContent=r.ok?"✅ Saved. Restart recommended.":"❌ Save failed";
  await refreshHealth();
};

(async()=>{
  await refreshHealth();
  await refreshConfig();
  chat("msgB","FlashTM8 Ultimate: Welcome ⚡");
  chat("msgB","1) Click Index Workspace");
  chat("msgB","2) Ask me about your repo");
  chat("msgB","3) I self-heal providers automatically");
})();
