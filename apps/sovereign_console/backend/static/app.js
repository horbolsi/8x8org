async function api(path, method="GET", body=null){
  const opt = {method, headers:{}};
  if(body){
    opt.headers["Content-Type"]="application/json";
    opt.body = JSON.stringify(body);
  }
  const r = await fetch(path, opt);
  const txt = await r.text();
  try{ return JSON.parse(txt); }
  catch(e){ return {ok:false,error:"Bad JSON response",raw:txt}; }
}

function addMsg(role, text){
  const box = document.getElementById("chatbox");
  const div = document.createElement("div");
  div.className = "msg " + (role==="user" ? "user" : "ai");
  div.textContent = text;
  box.appendChild(div);
  box.scrollTop = box.scrollHeight;
}

async function refreshHealth(){
  const h = await api("/api/health");
  const el = document.getElementById("status");
  if(h.ok){
    el.innerHTML = `✅ Online • Provider: <b>${h.provider}</b> • Exec=${h.exec_enabled} • Write=${h.write_enabled}`;
    document.getElementById("providerUsed").textContent = h.provider;
  }else{
    el.innerHTML = "❌ Offline";
  }
}

function tab(name){
  document.querySelectorAll(".tabbtn").forEach(b=>b.classList.remove("active"));
  document.querySelectorAll(".panel").forEach(p=>p.classList.remove("active"));
  document.querySelector(`[data-tab="${name}"]`).classList.add("active");
  document.getElementById("tab-"+name).classList.add("active");
}

document.querySelectorAll(".tabbtn").forEach(btn=>{
  btn.addEventListener("click", ()=>tab(btn.dataset.tab));
});

document.getElementById("sendChat").addEventListener("click", async ()=>{
  const input = document.getElementById("chatInput");
  const msg = input.value.trim();
  if(!msg) return;
  input.value="";
  addMsg("user", "You: " + msg);

  const res = await api("/api/chat","POST",{message:msg});
  if(res.ok){
    addMsg("ai", `FlashTM8 (${res.provider}): ${res.reply}`);
    document.getElementById("providerUsed").textContent = res.provider;
  }else{
    addMsg("ai", `Error: ${res.error || "Unknown"}\n${res.raw || ""}`);
  }
});

document.getElementById("runCmd").addEventListener("click", async ()=>{
  const cmd = document.getElementById("cmdInput").value.trim();
  if(!cmd) return;
  const res = await api("/api/exec","POST",{cmd});
  document.getElementById("cmdOut").textContent = JSON.stringify(res,null,2);
});

document.getElementById("readFile").addEventListener("click", async ()=>{
  const p = document.getElementById("filePath").value.trim();
  if(!p) return;
  const res = await api("/api/read?path="+encodeURIComponent(p));
  document.getElementById("fileOut").textContent = res.ok ? res.content : JSON.stringify(res,null,2);
});

document.getElementById("doSearch").addEventListener("click", async ()=>{
  const q = document.getElementById("searchQ").value.trim();
  const res = await api("/api/search?q="+encodeURIComponent(q));
  document.getElementById("searchOut").textContent = res.ok ? (res.results||[]).join("\n") : JSON.stringify(res,null,2);
});

document.getElementById("btnIndex").addEventListener("click", async ()=>{
  const res = await api("/api/index","POST",{});
  addMsg("ai", "Index result: " + JSON.stringify(res));
});

document.getElementById("refreshMetrics").addEventListener("click", async ()=>{
  const m = await api("/api/metrics");
  if(m.ok){
    document.getElementById("cpu").textContent = m.cpu_percent+"%";
    document.getElementById("mem").textContent = m.mem_percent+"%";
    document.getElementById("disk").textContent = m.disk_percent+"%";
    document.getElementById("free").textContent = m.disk_free_gb;
  }
});

document.getElementById("saveKeys").addEventListener("click", async ()=>{
  const payload = {
    AI_PROVIDER: document.getElementById("AI_PROVIDER").value,
    LLAMA_CPP_URL: document.getElementById("LLAMA_CPP_URL").value,
    OLLAMA_BASE_URL: document.getElementById("OLLAMA_BASE_URL").value,
    OPENAI_API_KEY: document.getElementById("OPENAI_API_KEY").value,
    GEMINI_API_KEY: document.getElementById("GEMINI_API_KEY").value,
    DEEPSEEK_API_KEY: document.getElementById("DEEPSEEK_API_KEY").value,
    EXEC_ENABLED: document.getElementById("EXEC_ENABLED").value,
    WRITE_ENABLED: document.getElementById("WRITE_ENABLED").value,
  };
  const res = await api("/api/save_keys","POST",payload);
  document.getElementById("saveMsg").textContent = res.ok ? "✅ Saved. Restart console for full reload." : "❌ Save failed.";
});

refreshHealth();
setInterval(refreshHealth, 6000);
