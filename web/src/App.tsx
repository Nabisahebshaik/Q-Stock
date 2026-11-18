import { ComponentType, FormEvent, lazy, Suspense, useCallback, useEffect, useState } from "react";
import { Bot, Camera, LogOut, Moon, Sun, UserRound } from "lucide-react";
import { authConfig, logout, Market, me, SNAPSHOT, useFallback, useFeeds, useSnapshotMeta, useStatus, User } from "./lib/api";
import { useTheme } from "./lib/util";
import { Boundary, Skeleton } from "./components/ui";
import LoginScreen from "./components/terminal/LoginScreen";
import Assistant from "./components/terminal/Assistant";

// After a new deployment, a page opened earlier asks for code chunks whose hashed names no
// longer exist. Reload once to pick up the new build instead of failing (guarded against loops).
const lazyPage = <P extends object>(load: () => Promise<{ default: ComponentType<P> }>) => lazy(() => load().then(
  (m) => { try { sessionStorage.removeItem("qstock-chunk-reload"); } catch { /* storage unavailable */ } return m; },
  (err) => {
    let reloaded = false;
    try { reloaded = sessionStorage.getItem("qstock-chunk-reload") === "1"; sessionStorage.setItem("qstock-chunk-reload", "1"); } catch { /* storage unavailable */ }
    if (!reloaded) { window.location.reload(); return new Promise<never>(() => {}); }
    throw err;
  }));
const LivePage = lazyPage(() => import("./pages/LivePage"));
const ExplainPage = lazyPage(() => import("./pages/ExplainPage"));
const NewsPage = lazyPage(() => import("./pages/NewsPage"));
const DialPage = lazyPage(() => import("./pages/DialPage"));
const ResearchPage = lazyPage(() => import("./pages/ResearchPage"));
const PipelinePage = lazyPage(() => import("./pages/PipelinePage"));

// Function-key navigation, as on a market terminal. Each tab also has a typed command (GO).
const TABS = [
  { id: "live", key: "F1", label: "Live", cmd: ["GP", "LIVE", "CHART", "Q"] },
  { id: "explain", key: "F2", label: "Explain (XAI)", cmd: ["EXPL", "XAI", "WHY"] },
  { id: "news", key: "F3", label: "News", cmd: ["N", "NEWS", "CN"] },
  { id: "dial", key: "F4", label: "Quantum dial", cmd: ["DIAL", "QSW", "OMEGA"] },
  { id: "research", key: "F5", label: "Research", cmd: ["RES", "RESEARCH"] },
  { id: "pipeline", key: "F6", label: "Pipeline", cmd: ["PIPE", "PIPELINE"] },
] as const;
type Tab = (typeof TABS)[number]["id"];
const fromHash = (): Tab => { const h = window.location.hash.replace("#", "") as Tab; return TABS.some((t) => t.id === h) ? h : "live"; };
type Phase = "checking" | "login" | "setup" | "offline" | "in";

export default function App() {
  const [phase, setPhase] = useState<Phase>("checking");
  const [user, setUser] = useState<User | null>(null);
  const [authOn, setAuthOn] = useState(false);
  useEffect(() => {
    (async () => {
      const cfg = await authConfig();
      if (!cfg) { setPhase("offline"); return; }
      setAuthOn(cfg.enabled);
      if (!cfg.enabled) { setPhase("setup"); return; }
      const u = await me();
      if (u) { setUser(u); setPhase("in"); } else setPhase("login");
    })();
  }, []);
  if (phase === "checking") return <div className="grid min-h-full place-items-center text-accent">SIGNING ON…</div>;
  if (phase !== "in") return <LoginScreen mode={phase} onUser={(u) => { setUser(u); setPhase("in"); }} onGuest={() => setPhase("in")} />;
  return <Terminal user={user} canAsk={!SNAPSHOT && (!!user || (!authOn))} onLogout={async () => { await logout(); setUser(null); setPhase(authOn ? "login" : "setup"); }} />;
}

function Terminal({ user, canAsk, onLogout }: { user: User | null; canAsk: boolean; onLogout: () => void }) {
  const [tab, setTab] = useState<Tab>(fromHash);
  const [theme, setTheme] = useTheme();
  const [market, setMarket] = useState<Market>(() => {
    const q = new URLSearchParams(window.location.search).get("market");
    return q === "NASDAQ" || q === "NSE" ? q : "NSE";
  });
  const [sel, setSel] = useState<Record<Market, string>>({ NSE: "RELIANCE.NS", NASDAQ: "NVDA" });
  const [cmd, setCmd] = useState("");
  const [msg, setMsg] = useState<string | null>(null);
  const [askOpen, setAskOpen] = useState(false);
  const [seed, setSeed] = useState<{ q: string; n: number } | null>(null);
  const [clock, setClock] = useState(() => new Date());
  const status = useStatus();
  const meta = useSnapshotMeta();
  const feeds = useFeeds();
  const fallback = useFallback();
  const dark = theme === "dark";
  const ticker = sel[market];
  const setTicker = (t: string) => setSel((s) => ({ ...s, [market]: t }));
  const go = useCallback((t: Tab) => { window.location.hash = t; setTab(t); }, []);
  const askNow = (q: string) => { setAskOpen(true); setSeed({ q, n: Date.now() }); };

  useEffect(() => { const f = () => setTab(fromHash()); window.addEventListener("hashchange", f); return () => window.removeEventListener("hashchange", f); }, []);
  useEffect(() => { const i = setInterval(() => setClock(new Date()), 1000); return () => clearInterval(i); }, []);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = TABS.find((x) => x.key === e.key);
      if (t) { e.preventDefault(); go(t.id); return; }
      if (e.key === "F8") { e.preventDefault(); setAskOpen((o) => !o); return; }
      if (e.key === "Escape") setAskOpen(false);
      if (e.key === "/" && !(e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement)) { e.preventDefault(); document.getElementById("cmdline")?.focus(); }
    };
    window.addEventListener("keydown", onKey); return () => window.removeEventListener("keydown", onKey);
  }, [go]);

  // Command line: "<TICKER> [FUNCTION]" or "<FUNCTION>", e.g. "RELIANCE EXPL", "NVDA N", "DIAL", "ASK why is TCS volatile?"
  const run = (e: FormEvent) => {
    e.preventDefault();
    const raw = cmd.trim(); setCmd(""); if (!raw) return;
    const up = raw.toUpperCase();
    if (up.startsWith("ASK ") || raw.endsWith("?")) { askNow(up.startsWith("ASK ") ? raw.slice(4) : raw); setMsg(null); return; }
    if (up === "HELP" || up === "?") { setMsg("<TICKER> [GP|EXPL|N]  ·  DIAL  RES  PIPE  ·  ASK <question>  ·  F1–F6 pages, F8 assistant, / focuses this line"); return; }
    const words = up.split(/\s+/);
    let found: { m: Market; t: string } | null = null;
    for (const s of status.data ?? []) for (const t of s.tickers) if (words.includes(t.label) || words.includes(t.ticker)) found = { m: s.market, t: t.ticker };
    const fn = TABS.find((t) => words.some((w) => (t.cmd as readonly string[]).includes(w)));
    if (!found && !fn) { setMsg(`UNKNOWN COMMAND: ${up} — type HELP`); return; }
    if (found) { setMarket(found.m); setSel((s) => ({ ...s, [found!.m]: found!.t })); }
    go(fn ? fn.id : ["live", "explain", "news"].includes(tab) ? tab : "live");
    setMsg(null);
  };

  const fmtClock = (tz: string) => clock.toLocaleTimeString("en-GB", { timeZone: tz, hour12: false });
  return (
    <div className="flex min-h-full flex-col pb-7">
      <header className="sticky top-0 z-40 border-b border-line bg-bg">
        <div className="flex items-center gap-2 px-2 py-1.5">
          <a href="#live" onClick={() => go("live")} className="shrink-0 bg-accent px-2 py-1 text-[13px] font-bold tracking-widest text-black">Q-STOCK</a>
          <form onSubmit={run} className="relative min-w-0 flex-1">
            <input id="cmdline" className="term-input pr-14" value={cmd} onChange={(e) => setCmd(e.target.value)} spellCheck={false} autoComplete="off"
                   placeholder="Type a command:  RELIANCE EXPL · NVDA N · DIAL · ASK why is TCS volatile?   ( / to focus, HELP )" aria-label="command line" />
            <button className="absolute right-1 top-1/2 -translate-y-1/2 bg-up px-1.5 text-[11px] font-bold text-black" aria-label="run command">GO</button>
          </form>
          <div className="hidden items-center gap-1.5 xl:flex">
            {(status.data ?? []).map((s) => (
              <span key={s.market} className="chip !text-ink" title={s.tz}>
                <span className={`h-1.5 w-1.5 rounded-full ${s.open ? "animate-pulseDot bg-up" : "bg-down"}`} />{s.market} {fmtClock(s.tz)}
              </span>
            ))}
          </div>
          {SNAPSHOT && <span className="chip border-warn/60 text-warn"><Camera size={12} /> snapshot {meta.data?.snapshot_iso ?? "…"}</span>}
          {fallback && <span className="chip border-warn/60 text-warn"><Camera size={12} /> snapshot · API waking</span>}
          <span className="chip !text-ink" title={user ? `signed in until ${new Date((user.expires_at ?? 0) * 1000).toLocaleString()}` : "read-only guest"}>
            <UserRound size={12} className="text-accent" />{user ? `${user.display_name} · ${user.role}` : "guest"}
          </span>
          <button className="btn !px-2 !py-1" aria-label="toggle theme" onClick={() => setTheme(dark ? "light" : "dark")}>{dark ? <Sun size={14} /> : <Moon size={14} />}</button>
          <button className="btn !px-2 !py-1" aria-label={user ? "sign out" : "sign in"} title={user ? "sign out" : "sign in"} onClick={onLogout}><LogOut size={14} /></button>
        </div>
        <nav className="flex items-center gap-1 overflow-x-auto border-t border-line bg-surface px-2 py-1">
          {TABS.map((t) => (
            <button key={t.id} onClick={() => go(t.id)} aria-current={tab === t.id ? "page" : undefined} className={`fkey ${tab === t.id ? "fkey-on" : ""}`}>
              <kbd>{t.key}</kbd>{t.label}
            </button>
          ))}
          <button onClick={() => setAskOpen((o) => !o)} className={`fkey ${askOpen ? "fkey-on" : ""}`}><kbd>F8</kbd><Bot size={12} /> Ask</button>
          <span className="ml-auto hidden shrink-0 text-[11px] text-muted md:block">{market} · <span className="text-accent">{ticker.replace(/\.NS$/, "")}</span></span>
        </nav>
        {msg && <div className="border-t border-line bg-black px-3 py-1 text-[11.5px] text-warn">{msg}</div>}
      </header>

      {fallback && (
        <div className="border-b border-warn/40 bg-warn/10 px-4 py-1.5 text-center text-[11.5px] text-ink/90">
          The live R API is waking up or unreachable, so this page shows the saved snapshot from <b>{meta.data?.snapshot_iso ?? "…"}</b>. It retries every minute.
        </div>
      )}
      {SNAPSHOT && (
        <div className="border-b border-warn/40 bg-warn/10 px-4 py-1.5 text-center text-[11.5px] text-ink/90">
          Static snapshot of the R pipeline taken <b>{meta.data?.snapshot_iso ?? "…"}</b>. Prices, news and graphs do not update here. Live mode: <code>Rscript api/run_api.R</code>.
        </div>
      )}

      <main className="mx-auto w-full max-w-[1700px] flex-1 px-2 py-3 md:px-3">
        <Boundary label="page"><Suspense fallback={<Skeleton h={600} />}>
          {tab === "live" && <LivePage market={market} setMarket={setMarket} dark={dark} sel={sel} setSel={setSel} />}
          {tab === "explain" && <ExplainPage market={market} setMarket={setMarket} ticker={ticker} setTicker={setTicker} onAsk={askNow} />}
          {tab === "news" && <NewsPage market={market} setMarket={setMarket} ticker={ticker} setTicker={setTicker} />}
          {tab === "dial" && <DialPage dark={dark} />}
          {tab === "research" && <ResearchPage dark={dark} />}
          {tab === "pipeline" && <PipelinePage />}
        </Suspense></Boundary>
      </main>

      <footer className="fixed inset-x-0 bottom-0 z-40 flex h-7 items-center gap-3 overflow-x-auto border-t border-line bg-surface px-2 text-[10.5px] uppercase tracking-wider text-muted">
        <span className="bg-accent px-1.5 font-bold text-black">Q-STOCK</span>
        <span>prices NSE: <span className="text-ink">{feeds.data?.prices?.NSE ?? "…"}</span></span>
        <span>NASDAQ: <span className="text-ink">{feeds.data?.prices?.NASDAQ ?? "…"}</span></span>
        <span>news: <span className="text-ink">{feeds.data?.news ?? "…"}</span></span>
        <span className="hidden md:inline">quantum walks simulated classically in R · research data frozen, live data view-only</span>
        <span className="ml-auto shrink-0 text-ink">{clock.toLocaleString("en-GB", { hour12: false })}</span>
      </footer>

      <Assistant open={askOpen} onClose={() => setAskOpen(false)} market={market} canAsk={canAsk} userName={user?.display_name ?? null} seed={seed} />
    </div>
  );
}
