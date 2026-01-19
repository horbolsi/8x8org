import React, { useEffect, useMemo, useState } from "react";
import { apiGet, apiPost } from "./api";

type User = { id: string; username: string; role: "admin"|"user" };

type TreeNode = {
  name: string;
  path: string;
  type: "dir"|"file";
  size: number;
  mtime: string;
  children?: TreeNode[];
};

function flattenFiles(node: TreeNode, out: TreeNode[] = []) {
  out.push(node);
  (node.children || []).forEach(c => flattenFiles(c, out));
  return out;
}

export default function App() {
  const [user, setUser] = useState<User|null>(null);
  const [bootMode, setBootMode] = useState(false);
  const [status, setStatus] = useState("loading...");
  const [tree, setTree] = useState<TreeNode|null>(null);
  const [selectedPath, setSelectedPath] = useState<string>("");
  const [fileContent, setFileContent] = useState<string>("");
  const [saveMsg, setSaveMsg] = useState<string>("");

  const [chatPrompt, setChatPrompt] = useState("");
  const [chatLog, setChatLog] = useState<string[]>([]);
  const [task, setTask] = useState<"general"|"fast"|"coder"|"reasoning">("general");
  const [model, setModel] = useState<string>("AUTO");

  const [termCmd, setTermCmd] = useState("rg");
  const [termArgs, setTermArgs] = useState("TODO .");
  const [termOut, setTermOut] = useState("");

  const allFiles = useMemo(() => tree ? flattenFiles(tree, []).filter(n => n.type === "file").slice(0, 2000) : [], [tree]);

  async function refreshMe() {
    try {
      const j = await apiGet("/api/auth/me");
      setUser(j.user);
      setBootMode(false);
    } catch {
      setUser(null);
      // if no users exist yet, backend will allow bootstrap
      setBootMode(true);
    }
  }

  async function refreshHealth() {
    try {
      const j = await apiGet("/api/health");
      setStatus(`✅ online on port ${j.port}`);
    } catch (e:any) {
      setStatus(`❌ backend offline: ${e.message}`);
    }
  }

  async function refreshTree() {
    const j = await apiGet("/api/fs/tree?path=.&depth=6");
    setTree(j.root);
  }

  async function openFile(p: string) {
    setSelectedPath(p);
    const j = await apiGet(`/api/fs/read?path=${encodeURIComponent(p)}`);
    setFileContent(j.content);
    setSaveMsg("");
  }

  async function saveFile() {
    if (!selectedPath) return;
    setSaveMsg("saving...");
    try {
      await apiPost("/api/fs/write", { path: selectedPath, content: fileContent });
      setSaveMsg("✅ saved");
    } catch (e:any) {
      setSaveMsg("❌ " + e.message);
    }
  }

  async function runTerminal() {
    setTermOut("running...");
    try {
      const args = termArgs.trim() ? termArgs.trim().split(/\s+/) : [];
      const j = await apiPost("/api/terminal/run", { cmd: termCmd, args });
      setTermOut((j.stdout || "") + (j.stderr ? "\n" + j.stderr : ""));
    } catch (e:any) {
      setTermOut("ERROR: " + e.message);
    }
  }

  async function sendChat() {
    if (!chatPrompt.trim()) return;
    const prompt = chatPrompt.trim();
    setChatPrompt("");

    setChatLog(prev => [...prev, `You: ${prompt}`, "AI: ..."]);

    try {
      const j = await apiPost("/api/ai/chat", {
        model,
        task,
        messages: [
          { role: "system", content: "You are Sovereign Console v2 assistant. Be concise, safe, and practical." },
          { role: "user", content: prompt }
        ]
      });

      let raw = j.raw || "";
      // raw is JSON string from ollama; try parse
      let answer = raw;
      try {
        const parsed = JSON.parse(raw);
        answer = parsed?.message?.content || parsed?.response || raw;
      } catch {}

      setChatLog(prev => {
        const copy = [...prev];
        copy[copy.length - 1] = `AI: ${answer}`;
        return copy;
      });
    } catch (e:any) {
      setChatLog(prev => {
        const copy = [...prev];
        copy[copy.length - 1] = `AI: ERROR: ${e.message}`;
        return copy;
      });
    }
  }

  async function login(username: string, password: string) {
    const j = await apiPost("/api/auth/login", { username, password });
    setUser(j.user);
    await refreshTree();
  }

  async function bootstrapAdmin(username: string, password: string) {
    await apiPost("/api/auth/bootstrap-admin", { username, password });
    await login(username, password);
  }

  async function logout() {
    await apiPost("/api/auth/logout", {});
    setUser(null);
  }

  useEffect(() => {
    (async () => {
      await refreshHealth();
      await refreshMe();
    })();
    const t = setInterval(refreshHealth, 5000);
    return () => clearInterval(t);
  }, []);

  useEffect(() => {
    if (user) refreshTree().catch(() => {});
  }, [user]);

  // UI login/boot forms
  const [u, setU] = useState("admin");
  const [p, setP] = useState("admin123");
  const [authMsg, setAuthMsg] = useState("");

  return (
    <div className="split">
      {/* LEFT: Workspace */}
      <div className="pane card">
        <div className="row" style={{ justifyContent: "space-between" }}>
          <div>
            <div style={{ fontWeight: 800, fontSize: 16 }}>Sovereign Console v2</div>
            <div className="muted" style={{ fontSize: 12 }}>{status}</div>
          </div>
          {user && (
            <button className="btn2" onClick={logout}>Logout</button>
          )}
        </div>

        {!user && (
          <div style={{ marginTop: 12 }} className="grid">
            <div className="card" style={{ padding: 12 }}>
              <div style={{ fontWeight: 700 }}>Authentication</div>
              <div className="muted" style={{ fontSize: 12, marginBottom: 8 }}>
                {bootMode ? "First run detected: create Admin account." : "Login to continue."}
              </div>
              <input className="input" placeholder="username" value={u} onChange={e=>setU(e.target.value)} />
              <input className="input" placeholder="password" type="password" value={p} onChange={e=>setP(e.target.value)} />
              <div className="row">
                {bootMode ? (
                  <button className="btn" onClick={async()=> {
                    setAuthMsg("working...");
                    try { await bootstrapAdmin(u,p); setAuthMsg("✅ admin created"); }
                    catch(e:any){ setAuthMsg("❌ " + e.message); }
                  }}>Bootstrap Admin</button>
                ) : (
                  <button className="btn" onClick={async()=> {
                    setAuthMsg("working...");
                    try { await login(u,p); setAuthMsg("✅ logged in"); }
                    catch(e:any){ setAuthMsg("❌ " + e.message); }
                  }}>Login</button>
                )}
                <button className="btn2" onClick={refreshMe}>Refresh</button>
              </div>
              <div className="muted" style={{ fontSize: 12 }}>{authMsg}</div>
              <div className="muted" style={{ fontSize: 12, marginTop: 6 }}>
                Default cookie-based session. Change JWT_SECRET in backend .env later.
              </div>
            </div>
          </div>
        )}

        {user && (
          <div style={{ marginTop: 10 }}>
            <div className="muted" style={{ fontSize: 12 }}>
              Logged in as <b>{user.username}</b> ({user.role})
            </div>

            <div className="row" style={{ marginTop: 10 }}>
              <button className="btn2" onClick={refreshTree}>Reload Tree</button>
              <button className="btn2" onClick={()=>openFile("README.md").catch(()=>{})}>Open README</button>
            </div>

            <div style={{ marginTop: 12 }}>
              <div style={{ fontWeight: 700, marginBottom: 6 }}>Workspace</div>
              <div className="muted" style={{ fontSize: 12 }}>Tap a file to open</div>
              <div style={{ marginTop: 8 }}>
                {allFiles.slice(0, 250).map((f) => (
                  <div key={f.path} className="fileItem" onClick={()=>openFile(f.path)}>
                    <span className="muted">{f.path}</span>
                  </div>
                ))}
                {allFiles.length > 250 && (
                  <div className="muted" style={{ fontSize: 12, marginTop: 6 }}>
                    Showing first 250 files (UI limiter)
                  </div>
                )}
              </div>
            </div>
          </div>
        )}
      </div>

      {/* CENTER: Editor + Terminal */}
      <div className="pane card">
        {user ? (
          <>
            <div className="row" style={{ justifyContent: "space-between" }}>
              <div>
                <div style={{ fontWeight: 700 }}>Editor</div>
                <div className="muted" style={{ fontSize: 12 }}>
                  {selectedPath ? selectedPath : "Select a file from the left"}
                </div>
              </div>
              <div className="row">
                <button className="btn" onClick={saveFile} disabled={user.role !== "admin" || !selectedPath}>
                  Save
                </button>
                <div className="muted" style={{ fontSize: 12 }}>{saveMsg}</div>
              </div>
            </div>

            <div style={{ marginTop: 10 }}>
              <textarea
                value={fileContent}
                onChange={(e)=>setFileContent(e.target.value)}
                placeholder={user.role === "admin" ? "Open a file to edit..." : "Read-only mode (user role)"}
                readOnly={user.role !== "admin"}
              />
            </div>

            <div style={{ marginTop: 12 }} className="card" >
              <div style={{ padding: 12 }}>
                <div style={{ fontWeight: 700 }}>Terminal (Admin Only)</div>
                <div className="muted" style={{ fontSize: 12 }}>
                  Allowlist mode. No destructive commands by default.
                </div>
                <div className="row" style={{ marginTop: 8 }}>
                  <input className="input" style={{ width: 120 }} value={termCmd} onChange={e=>setTermCmd(e.target.value)} />
                  <input className="input" placeholder='args e.g. "TODO ."' value={termArgs} onChange={e=>setTermArgs(e.target.value)} />
                  <button className="btn2" onClick={runTerminal} disabled={user.role !== "admin"}>Run</button>
                </div>
                <pre style={{ marginTop: 10, fontSize: 12 }} className="muted">{termOut}</pre>
                {user.role !== "admin" && (
                  <div className="danger" style={{ fontSize: 12 }}>
                    Terminal is disabled for non-admin users.
                  </div>
                )}
              </div>
            </div>
          </>
        ) : (
          <div className="muted">Login first.</div>
        )}
      </div>

      {/* RIGHT: AI Chat */}
      <div className="pane card">
        <div style={{ fontWeight: 800 }}>AI Assistant</div>
        <div className="muted" style={{ fontSize: 12 }}>
          Uses your local Ollama via backend. Task-based AUTO model routing supported.
        </div>

        {user ? (
          <>
            <div className="row" style={{ marginTop: 8 }}>
              <select className="input" value={task} onChange={e=>setTask(e.target.value as any)}>
                <option value="general">general</option>
                <option value="fast">fast</option>
                <option value="coder">coder</option>
                <option value="reasoning">reasoning</option>
              </select>
              <input className="input" value={model} onChange={e=>setModel(e.target.value)} placeholder="AUTO or model name" />
            </div>

            <div className="card" style={{ marginTop: 10, padding: 10, height: "60vh", overflow: "auto" }}>
              {chatLog.length === 0 && (
                <div className="muted" style={{ fontSize: 12 }}>
                  Example: “scan my repo and suggest the best architecture to unify the dashboard.”
                </div>
              )}
              {chatLog.map((line, i) => (
                <div key={i} style={{ marginBottom: 8 }}>
                  <div style={{ fontSize: 12 }}>{line}</div>
                </div>
              ))}
            </div>

            <div style={{ marginTop: 10 }} className="row">
              <input
                className="input"
                value={chatPrompt}
                onChange={e=>setChatPrompt(e.target.value)}
                placeholder="Ask the assistant..."
                onKeyDown={(e)=>{ if (e.key === "Enter") sendChat(); }}
              />
              <button className="btn2" onClick={sendChat}>Send</button>
            </div>

            <div className="muted" style={{ fontSize: 12, marginTop: 8 }}>
              Next upgrade: repo-context chat + multi-file patch jobs with approval/run/rollback.
            </div>
          </>
        ) : (
          <div className="muted" style={{ marginTop: 12 }}>
            Login first to use AI.
          </div>
        )}
      </div>
    </div>
  );
}
