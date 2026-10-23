import { useMemo, useState } from "react";
import { motion } from "framer-motion";
import { Activity, AlertTriangle, ArrowDownUp, Database, Radio } from "lucide-react";
import { Market, Quote, useShowingSnapshot, useCandles, useForecast, useGraph, useLive } from "../lib/api";
import { ago, changeColor, compact, cssHex, pct, price, useReducedMotion, useThemeTick } from "../lib/util";
import { AnimatedNumber, Boundary, Card, Delta, Kpi, OmegaDial, Segmented, Skeleton, Sparkline } from "../components/ui";
import QuantumGraph3D, { GNode } from "../components/QuantumGraph3D";
import CandleChart from "../components/CandleChart";

type SortKey = "label" | "last" | "change" | "rv" | "spill" | "qself" | "fc";

export default function LivePage({ market, setMarket, dark }: { market: Market; setMarket: (m: Market) => void; dark: boolean }) {
  const SNAPSHOT = useShowingSnapshot();
  const [omega, setOmega] = useState(0.25);
  const [look, setLook] = useState(120);
  const [sel, setSel] = useState<Record<Market, string>>({ NSE: "RELIANCE.NS", NASDAQ: "NVDA" });
  const [sort, setSort] = useState<{ k: SortKey; desc: boolean }>({ k: "rv", desc: true });
  const live = useLive(market);
  const graph = useGraph(market, omega, look);
  const fc = useForecast(market);
  const ticker = sel[market];
  const candles = useCandles(market, ticker);
  const reduced = useReducedMotion();
  useThemeTick();
  const col = { up: cssHex("up"), down: cssHex("down"), muted: cssHex("muted"), accent: cssHex("accent"), line: cssHex("line") };
  const flat = dark ? "#5b6478" : "#b8bfcc";

  const L = live.data;
  const quotes = L?.quotes ?? [];
  const q = quotes.find((x) => x.ticker === ticker);
  const fmap = useMemo(() => Object.fromEntries((fc.data?.forecasts ?? []).map((f) => [f.ticker, f])), [fc.data]);
  const G = graph.data?.nodes ? graph.data : null;
  const gi = G ? G.nodes!.id.indexOf(ticker) : -1;

  const nodes: GNode[] = useMemo(() => {
    if (!G?.nodes) return [];
    const n = G.nodes, rvMax = Math.max(...(n.rv ?? [1]));
    const sp = n.q_volspill ?? [], spMin = Math.min(...sp), spMax = Math.max(...sp);
    return n.id.map((id, i) => ({
      id, label: n.label[i], color: changeColor(n.change?.[i], col.up, col.down, flat),
      size: 0.22 + 0.42 * ((n.rv?.[i] ?? 0) / rvMax), glow: spMax > spMin ? (sp[i] - spMin) / (spMax - spMin) : 0.5,
      tooltip: [`change ${pct(n.change?.[i], 2, true)}`, `intraday vol ${pct(n.rv?.[i], 1)}`, `QSW spillover ${pct(n.q_volspill?.[i], 1)}`,
                `return prob. ${n.q_self?.[i]?.toFixed(3)}`, `entropy ${n.q_ent?.[i]?.toFixed(2)}`],
    }));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [G, dark, col.up, col.down]);
  const edges = useMemo(() => (G ? G.edges.source.map((s, i) => ({ source: s, target: G.edges.target[i], weight: Math.max(0, G.edges.rho[i]) })) : []), [G]);

  const adv = quotes.filter((x) => (x.change ?? 0) > 0).length, dec = quotes.filter((x) => (x.change ?? 0) < 0).length;
  const rows = useMemo(() => {
    const r = quotes.map((x) => {
      const i = G?.nodes ? G.nodes.id.indexOf(x.ticker) : -1;
      return { ...x, spill: i >= 0 ? G!.nodes!.q_volspill?.[i] ?? null : null, qself: i >= 0 ? G!.nodes!.q_self?.[i] ?? null : null, fc: fmap[x.ticker]?.vol5_ann ?? null };
    });
    const v = (o: (typeof r)[number]) => (sort.k === "label" ? o.label : (o[sort.k] as number | null) ?? -Infinity);
    return r.sort((a, b) => { const A = v(a), B = v(b); return (A < B ? -1 : A > B ? 1 : 0) * (sort.desc ? -1 : 1); });
  }, [quotes, G, fmap, sort]);

  if (live.isError && !L) return <ErrorState msg={String(live.error)} />;

  return (
    <div className="space-y-5">
      {/* control bar */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap items-center gap-3">
          <Segmented value={market} onChange={setMarket} options={[{ value: "NSE", label: "NSE · India" }, { value: "NASDAQ", label: "NASDAQ · US" }]} />
          {L && (
            <span className={`chip ${L.open ? "border-up/40 text-up" : ""}`}>
              <span className={`h-2 w-2 rounded-full ${L.open ? "animate-pulseDot bg-up" : "bg-muted"}`} />
              {SNAPSHOT ? "At snapshot: " : ""}{L.open ? "Market open" : "Market closed"} · {L.local_time}
            </span>
          )}
          {L?.newest_bar_age != null && <span className="chip"><Radio size={12} /> newest bar {ago(L.newest_bar_age)} old{SNAPSHOT ? " at snapshot" : ""}</span>}
          {L?.stale && <span className="chip border-warn/50 text-warn"><AlertTriangle size={12} /> showing last good data</span>}
          {(L?.errors?.length ?? 0) > 0 && <span className="chip border-down/50 text-down">{L!.errors.length} fetch errors</span>}
          {L?.open && (L.newest_bar_age ?? 0) > 900 && <span className="chip border-warn/50 text-warn">open by clock, no recent bars (holiday?)</span>}
        </div>
        <span className="text-xs text-muted">{L ? `session ${L.session_day} · ${SNAPSHOT ? "static snapshot" : "refreshes every 60 s"}` : "connecting…"}</span>
      </div>

      <TickerTape quotes={quotes} spark={L?.spark} market={market} onPick={(t) => setSel({ ...sel, [market]: t })} col={col} reduced={reduced} />

      {/* KPIs */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-5">
        <Kpi label={q ? `${q.label} last` : "Last price"} sub={q ? q.name : undefined}>
          <AnimatedNumber value={q?.last} format={(x) => price(x, market)} />
        </Kpi>
        <Kpi label="Change vs previous close"><Delta x={q?.change} /></Kpi>
        <Kpi label="Intraday volatility" sub="annualised, 1-min returns (incl. microstructure noise)">
          <AnimatedNumber value={q?.rv} format={(x) => pct(x, 1)} />
        </Kpi>
        <Kpi label="Graph-HAR 5-day vol forecast" accent
             sub={fmap[ticker] ? `completed sessions to ${fmap[ticker].as_of}` : fc.isLoading ? "loading…" : "daily data unavailable"}>
          <AnimatedNumber value={fmap[ticker]?.vol5_ann} format={(x) => pct(x, 1)} />
        </Kpi>
        <Kpi label="Market breadth" sub={`${quotes.length} stocks`}>
          <span className="text-up">{adv}</span><span className="mx-1 text-muted">/</span><span className="text-down">{dec}</span>
          <div className="mt-2 flex h-1.5 overflow-hidden rounded-full bg-raised">
            <div className="bg-up" style={{ width: `${(100 * adv) / Math.max(1, quotes.length)}%` }} />
            <div className="bg-down" style={{ width: `${(100 * dec) / Math.max(1, quotes.length)}%` }} />
          </div>
        </Kpi>
      </div>

      {/* 3D graph + controls */}
      <div className="grid gap-5 xl:grid-cols-12">
        <Card className="xl:col-span-8" title={<span className="flex items-center gap-2"><Activity size={14} /> Live quantum market graph</span>}
              right={<span className="chip">{G ? `${G.n_bars} one-minute returns · k = 4 neighbours` : "building graph…"}</span>}>
          {nodes.length ? (
            <Boundary label="3D graph"><QuantumGraph3D nodes={nodes} edges={edges} flow={G?.P} selected={ticker} onSelect={(t) => setSel({ ...sel, [market]: t })}
                            accent={col.accent} muted={col.muted} dark={dark} reducedMotion={reduced} height={540} /></Boundary>
          ) : graph.isLoading || live.isLoading ? <Skeleton h={500} /> : (
            <div className="grid h-[540px] place-items-center text-sm text-muted">Not enough intraday bars for a graph yet.</div>
          )}
        </Card>
        <div className="space-y-5 xl:col-span-4">
          <Card title="Walk controls" bodyClass="space-y-6 p-5">
            <OmegaDial value={omega} onChange={setOmega} />
            <div>
              <div className="mb-2 flex items-baseline justify-between"><span className="text-sm text-muted">Graph window</span>
                <span className="num font-mono text-accent">{look} min</span></div>
              <input aria-label="graph window" type="range" min={30} max={375} step={15} value={look} onChange={(e) => setLook(+e.target.value)} className="dial w-full disabled:opacity-40" disabled={SNAPSHOT} />
              {SNAPSHOT && <div className="mt-1.5 text-[11px] text-muted">Fixed at 120 minutes in the snapshot.</div>}
            </div>
          </Card>
          <Card title={q ? `${q.label} on the walk` : "Selected stock"} bodyClass="p-5">
            {G && gi >= 0 ? (
              <dl className="grid grid-cols-2 gap-x-4 gap-y-4 text-sm">
                <Stat k="Return probability" v={G.nodes!.q_self?.[gi]?.toFixed(3)} hint="how isolated it is" />
                <Stat k="Spread entropy" v={G.nodes!.q_ent?.[gi]?.toFixed(2)} hint="how widely risk spreads" />
                <Stat k="QSW spillover" v={pct(G.nodes!.q_volspill?.[gi], 1)} hint="walk-weighted neighbour vol" />
                <Stat k="Neighbours" v={String(edges.filter((e) => e.source === ticker || e.target === ticker).length)} hint="kNN links" />
              </dl>
            ) : <div className="text-sm text-muted">Select a stock in the graph or the table.</div>}
            <p className="mt-5 border-t border-line/60 pt-4 text-xs leading-5 text-muted">
              Colour: change vs previous close. Size: intraday volatility. Glow: QSW spillover. Particles flow along links in proportion to the
              walk's transition probabilities, so moving ω changes the flow. Quantum walks are <b className="text-ink/80">classical simulations</b> in R.
            </p>
          </Card>
        </div>
      </div>

      {/* candles */}
      <Card title={<span>{q?.label ?? ticker} · 1-minute candles, VWAP, volume ({market === "NSE" ? "IST" : "New York time"})</span>}
            right={candles.data?.active_last ? <span className="chip"><span className="h-1.5 w-1.5 animate-pulseDot rounded-full bg-accent" /> last candle forming</span> : null}
            bodyClass="p-3">
        {candles.data?.candles?.length ? <Boundary label="candle chart"><CandleChart candles={candles.data.candles} height={430} /></Boundary> : <Skeleton h={400} />}
      </Card>

      {/* risk table */}
      <Card title="Live risk table" right={L?.store && (
        <span className="chip"><Database size={12} /> {compact(L.store.candles)} candles stored · last write {L.store.written} ok / {L.store.rejected} rejected · fetch {L.fetch_sec?.toFixed(1)} s</span>)}>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[860px] text-sm">
            <thead className="text-left text-xs uppercase tracking-wider text-muted">
              <tr>
                {([["label", "Stock"], ["last", "Last"], ["change", "Change"], ["rv", "Intraday vol"], ["spill", "QSW spillover"], ["qself", "Return prob."], ["fc", "GHAR 5-day vol"]] as [SortKey, string][]).map(([k, t]) => (
                  <th key={k} className="px-5 py-3 font-medium">
                    <button className="inline-flex items-center gap-1 hover:text-ink" onClick={() => setSort({ k, desc: sort.k === k ? !sort.desc : true })}>
                      {t}<ArrowDownUp size={11} className={sort.k === k ? "text-accent" : "opacity-40"} />
                    </button>
                  </th>))}
                <th className="px-5 py-3 font-medium">Today</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <motion.tr layout key={r.ticker} onClick={() => setSel({ ...sel, [market]: r.ticker })}
                           className={`cursor-pointer border-t border-line/50 transition hover:bg-raised/60 ${r.ticker === ticker ? "bg-accent/10" : ""}`}>
                  <td className="px-5 py-2.5"><div className="font-medium">{r.label}</div><div className="text-xs text-muted">{r.name}</div></td>
                  <td className="num px-5">{price(r.last, market)}</td>
                  <td className="px-5"><Delta x={r.change} /></td>
                  <td className="px-5"><Bar v={r.rv} max={Math.max(...rows.map((x) => x.rv ?? 0))} color={col.accent} /></td>
                  <td className="num px-5">{pct(r.spill, 1)}</td>
                  <td className="num px-5">{r.qself?.toFixed(3) ?? "—"}</td>
                  <td className="num px-5">{pct(r.fc, 1)}</td>
                  <td className="px-5"><Sparkline data={L?.spark?.[r.ticker]} color={(r.change ?? 0) >= 0 ? col.up : col.down} /></td>
                </motion.tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>
      <p className="pb-4 text-center text-xs text-muted">
        Data: Yahoo chart API, polled by the R server once a minute and shared by all viewers{SNAPSHOT ? " (this page shows a saved snapshot)" : ""}. It is free and unofficial, so delays are possible.
        Live data are for viewing only; they never enter the research results and are not trading advice.
      </p>
    </div>
  );
}

function TickerTape({ quotes, spark, market, onPick, col, reduced }: {
  quotes: Quote[]; spark?: Record<string, number[]>; market: Market; onPick: (t: string) => void; col: Record<string, string>; reduced: boolean;
}) {
  if (!quotes.length) return <div className="glass h-14 animate-pulse" />;
  const items = [...quotes, ...quotes];
  return (
    <div className="glass group relative overflow-hidden py-2.5" aria-label="ticker tape">
      <div className={`flex w-max gap-2 ${reduced ? "" : "animate-marquee group-hover:[animation-play-state:paused]"}`}>
        {items.map((x, i) => (
          <button key={i} onClick={() => onPick(x.ticker)} className="flex items-center gap-3 rounded-xl px-3 py-1 hover:bg-raised/70" tabIndex={i < quotes.length ? 0 : -1}>
            <span className="text-sm font-semibold">{x.label}</span>
            <span className="num text-sm text-muted">{price(x.last, market)}</span>
            <Delta x={x.change} />
            <Sparkline data={spark?.[x.ticker]?.slice(-40)} color={(x.change ?? 0) >= 0 ? col.up : col.down} width={56} height={20} />
          </button>
        ))}
      </div>
      <div className="pointer-events-none absolute inset-y-0 left-0 w-16 bg-gradient-to-r from-surface to-transparent" />
      <div className="pointer-events-none absolute inset-y-0 right-0 w-16 bg-gradient-to-l from-surface to-transparent" />
    </div>
  );
}

const Stat = ({ k, v, hint }: { k: string; v?: string; hint: string }) => (
  <div><dt className="text-xs text-muted">{k}</dt><dd className="num mt-0.5 text-xl font-semibold">{v ?? "—"}</dd><div className="text-[11px] text-muted">{hint}</div></div>
);
const Bar = ({ v, max, color }: { v: number | null; max: number; color: string }) => (
  <div className="flex items-center gap-2">
    <div className="h-1.5 w-20 overflow-hidden rounded-full bg-raised"><div className="h-full rounded-full" style={{ width: `${(100 * (v ?? 0)) / (max || 1)}%`, background: color }} /></div>
    <span className="num">{pct(v, 1)}</span>
  </div>
);
const ErrorState = ({ msg }: { msg: string }) => (
  <div className="glass mx-auto mt-20 max-w-xl p-8 text-center">
    <AlertTriangle className="mx-auto mb-3 text-warn" />
    <div className="font-semibold">The R API is not reachable</div>
    <p className="mt-2 text-sm text-muted">Start it with <code className="rounded bg-raised px-1.5 py-0.5">Rscript api/run_api.R</code> from the project root.</p>
    <p className="mt-3 font-mono text-xs text-muted">{msg}</p>
  </div>
);
