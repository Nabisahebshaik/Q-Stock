import { ComponentType, lazy, Suspense, useEffect, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Atom, Camera, LineChart, Moon, Network, Sun, Workflow } from "lucide-react";
import { Market, SNAPSHOT, useFallback, useSnapshotMeta, useStatus } from "./lib/api";
import { useTheme } from "./lib/util";
import { Boundary, Skeleton } from "./components/ui";

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
const DialPage = lazyPage(() => import("./pages/DialPage"));
const ResearchPage = lazyPage(() => import("./pages/ResearchPage"));
const PipelinePage = lazyPage(() => import("./pages/PipelinePage"));

const TABS = [
  { id: "live", label: "Live market", icon: LineChart },
  { id: "dial", label: "Quantum dial", icon: Atom },
  { id: "research", label: "Research", icon: Network },
  { id: "pipeline", label: "Pipeline", icon: Workflow },
] as const;
type Tab = (typeof TABS)[number]["id"];
const fromHash = (): Tab => { const h = window.location.hash.replace("#", "") as Tab; return TABS.some((t) => t.id === h) ? h : "live"; };

export default function App() {
  const [tab, setTab] = useState<Tab>(fromHash);
  const [theme, setTheme] = useTheme();
  const [market, setMarket] = useState<Market>(() => {
    const q = new URLSearchParams(window.location.search).get("market");
    return q === "NASDAQ" || q === "NSE" ? q : "NSE";
  });
  const status = useStatus();
  const meta = useSnapshotMeta();
  const fallback = useFallback();
  useEffect(() => { const f = () => setTab(fromHash()); window.addEventListener("hashchange", f); return () => window.removeEventListener("hashchange", f); }, []);
  const go = (t: Tab) => { window.location.hash = t; setTab(t); };
  const dark = theme === "dark";

  return (
    <div className="min-h-full">
      <header className="sticky top-0 z-40 border-b border-line/60 bg-bg/70 backdrop-blur-xl">
        <div className="mx-auto flex max-w-[1600px] items-center gap-4 px-4 py-3 md:px-6">
          <a href="#live" onClick={() => go("live")} className="flex items-center gap-2.5">
            <div className="relative grid h-9 w-9 place-items-center rounded-xl bg-gradient-to-br from-accent to-quantum shadow-[0_0_24px_rgb(var(--accent)/0.45)]">
              <Atom size={18} className="text-white" />
            </div>
            <div className="leading-tight">
              <div className="text-[15px] font-semibold tracking-tight">Q-Stock</div>
              <div className="hidden text-[11px] text-muted sm:block">quantum-walk market graphs</div>
            </div>
          </a>
          <nav className="ml-2 flex flex-1 gap-1 overflow-x-auto">
            {TABS.map((t) => (
              <button key={t.id} onClick={() => go(t.id)} aria-current={tab === t.id ? "page" : undefined}
                      className={`relative flex shrink-0 items-center gap-2 rounded-xl px-3 py-2 text-sm transition ${tab === t.id ? "text-ink" : "text-muted hover:text-ink"}`}>
                {tab === t.id && <motion.span layoutId="navpill" className="absolute inset-0 rounded-xl bg-raised ring-1 ring-line" transition={{ type: "spring", stiffness: 400, damping: 32 }} />}
                <t.icon size={15} className="relative" /><span className="relative">{t.label}</span>
              </button>
            ))}
          </nav>
          <div className="hidden items-center gap-2 lg:flex">
            {SNAPSHOT && <span className="chip border-warn/50 text-warn"><Camera size={12} /> Snapshot · {meta.data?.snapshot_iso ?? "…"}</span>}
            {fallback && <span className="chip border-warn/50 text-warn"><Camera size={12} /> Snapshot (API waking)</span>}
            {!SNAPSHOT && !fallback && status.data?.map((s) => (
              <span key={s.market} className="chip" title={s.tz}>
                <span className={`h-1.5 w-1.5 rounded-full ${s.open ? "animate-pulseDot bg-up" : "bg-muted"}`} />{s.market} {s.local_time.split(" ").slice(1).join(" ")}
              </span>
            ))}
          </div>
          <button className="btn !px-2.5" aria-label="toggle theme" onClick={() => setTheme(dark ? "light" : "dark")}>
            {dark ? <Sun size={16} /> : <Moon size={16} />}
          </button>
        </div>
      </header>
      {fallback && (
        <div className="border-b border-warn/30 bg-warn/10 px-4 py-2 text-center text-xs text-ink/80">
          The live R API is waking up or unreachable, so this page shows the saved snapshot from <b>{meta.data?.snapshot_iso ?? "…"}</b>.
          It retries every minute and switches to live data automatically (a sleeping free-tier server takes about a minute to start).
        </div>
      )}
      {SNAPSHOT && (
        <div className="border-b border-warn/30 bg-warn/10 px-4 py-2 text-center text-xs text-ink/80">
          Static snapshot of the R pipeline taken <b>{meta.data?.snapshot_iso ?? "…"}</b>. Prices and graphs do not update here.
          Live mode runs with the R API: <code className="rounded bg-raised px-1">Rscript api/run_api.R</code>.
        </div>
      )}
      <main className="mx-auto max-w-[1600px] px-4 py-6 md:px-6">
        <AnimatePresence mode="wait">
          <motion.div key={tab} initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -8 }} transition={{ duration: 0.25 }}>
            <Boundary label="page"><Suspense fallback={<Skeleton h={600} />}>
              {tab === "live" && <LivePage market={market} setMarket={setMarket} dark={dark} />}
              {tab === "dial" && <DialPage dark={dark} />}
              {tab === "research" && <ResearchPage dark={dark} />}
              {tab === "pipeline" && <PipelinePage />}
            </Suspense></Boundary>
          </motion.div>
        </AnimatePresence>
      </main>
    </div>
  );
}
