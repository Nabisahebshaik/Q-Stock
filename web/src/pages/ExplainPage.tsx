import { Bar, BarChart, Cell, CartesianGrid, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { Bot, Info } from "lucide-react";
import { Market, useExplain, useForecast, useShowingSnapshot, useStatus } from "../lib/api";
import { cssHex, pct, useThemeTick } from "../lib/util";
import { Boundary, Card, Kpi, Segmented, Skeleton } from "../components/ui";

/** Explainable forecast (XAI): exact additive breakdown of the live graph-HAR volatility forecast. */
export default function ExplainPage({ market, setMarket, ticker, setTicker, onAsk }: {
  market: Market; setMarket: (m: Market) => void; ticker: string; setTicker: (t: string) => void; onAsk: (q: string) => void;
}) {
  useThemeTick();
  const SNAPSHOT = useShowingSnapshot();
  const status = useStatus();
  const fc = useForecast(market);
  const ex = useExplain(market, ticker);
  const tickers = status.data?.find((s) => s.market === market)?.tickers ?? [];
  const E = ex.data?.explanation;
  const col = { up: cssHex("up"), down: cssHex("down"), accent: cssHex("accent"), line: cssHex("line"), muted: cssHex("muted"), ink: cssHex("ink") };
  const fmap = Object.fromEntries((fc.data?.forecasts ?? []).map((f) => [f.ticker, f.vol5_ann]));
  const label = ticker.replace(/\.NS$/, "");
  const bars = (E?.features ?? []).map((f) => ({ name: f.label, c: f.contribution, factor: f.vol_factor }));
  // symmetric padding so the "xfactor" labels never fall outside the plot
  const lo = Math.min(0, ...bars.map((b) => b.c)), hi = Math.max(0, ...bars.map((b) => b.c)), pad = 0.22 * Math.max(hi - lo, 1e-6);
  const domain: [number, number] = [lo < 0 ? lo - pad : 0, hi > 0 ? hi + pad : 0];

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <Segmented value={market} onChange={setMarket} options={[{ value: "NSE", label: "NSE" }, { value: "NASDAQ", label: "NASDAQ" }]} />
        <span className="chip">XAI · exact linear attribution</span>
        {SNAPSHOT && <span className="chip border-warn/60 text-warn">snapshot</span>}
        <button className="btn ml-auto" onClick={() => onAsk(`Why is ${label}'s volatility forecast where it is?`)}><Bot size={14} /> Ask about {label}</button>
      </div>

      <div className="grid gap-3 lg:grid-cols-[230px_1fr]">
        <Card title="Universe · 5d vol fcst" bodyClass="max-h-[640px] overflow-y-auto">
          <ul>
            {tickers.map((t) => (
              <li key={t.ticker}>
                <button onClick={() => setTicker(t.ticker)}
                        className={`flex w-full items-center justify-between border-b border-line/50 px-3 py-1.5 text-left text-[12px] ${t.ticker === ticker ? "bg-accent text-black" : "hover:bg-raised"}`}>
                  <span className="font-semibold">{t.label}</span><span className="num">{pct(fmap[t.ticker], 1)}</span>
                </button>
              </li>
            ))}
          </ul>
        </Card>

        <div className="space-y-3">
          {ex.isLoading && <Skeleton h={300} />}
          {ex.data && !E && (
            <Card title={`${label} · explanation`}><p className="p-4 text-warn">The live forecast is not available right now (the daily price refresh failed or has not run), so there is nothing to explain. Nothing is estimated in its place.</p></Card>
          )}
          {E && (
            <>
              <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                <Kpi label={`${label} · fcst vol (5d, ann.)`} accent sub={`as of close ${E.as_of}`}><span className="num">{pct(E.vol5_ann, 1)}</span></Kpi>
                <Kpi label={`${market} average stock`} sub="mean forecast of the universe today"><span className="num text-muted">{pct(E.baseline_vol5_ann, 1)}</span></Kpi>
                <Kpi label="Gap vs average" sub="product of the factors below"><span className={`num ${E.vol5_ann >= E.baseline_vol5_ann ? "text-down" : "text-up"}`}>×{(E.vol5_ann / E.baseline_vol5_ann).toFixed(2)}</span></Kpi>
                <Kpi label="Risk rank" sub="1 = most volatile forecast"><span className="num">{E.rank} / {E.n_universe}</span></Kpi>
              </div>

              <Card title="Reading" right={<span className="text-[11px] font-semibold">GHAR · {ex.data?.model?.n?.toLocaleString()} obs · {ex.data?.model?.train_from} → {ex.data?.model?.train_to}</span>}>
                <p className="px-4 py-3 text-[13px] leading-relaxed">{E.summary}</p>
              </Card>

              <Card title="Drivers · contribution to the gap (log-variance; bars sum exactly to the gap)">
                <Boundary label="driver chart">
                  <div className="h-[280px] px-2 py-3">
                    <ResponsiveContainer>
                      <BarChart data={bars} layout="vertical" margin={{ left: 8, right: 56, top: 4, bottom: 4 }}>
                        <CartesianGrid stroke={col.line} horizontal={false} strokeDasharray="2 4" />
                        <XAxis type="number" domain={domain} tickFormatter={(v: number) => v.toFixed(3)} tick={{ fill: col.muted, fontSize: 11, fontFamily: "JetBrains Mono" }} stroke={col.line} />
                        <YAxis type="category" dataKey="name" width={230} tick={{ fill: col.ink, fontSize: 11, fontFamily: "JetBrains Mono" }} stroke={col.line} />
                        <ReferenceLine x={0} stroke={col.accent} />
                        <Tooltip cursor={{ fill: "rgba(255,160,26,0.08)" }} contentStyle={{ background: "#000", border: `1px solid ${col.accent}`, fontFamily: "JetBrains Mono", fontSize: 12 }}
                                 formatter={(v: number, _n, p) => [`${v >= 0 ? "+" : ""}${v.toFixed(4)}  (vol ×${(p.payload as { factor: number }).factor.toFixed(3)})`, "contribution"]} />
                        <Bar dataKey="c" isAnimationActive={false} label={{ position: "right", fill: col.ink, fontSize: 11, fontFamily: "JetBrains Mono", formatter: (v: number) => `×${Math.exp(v / 2).toFixed(2)}` }}>
                          {bars.map((b, i) => <Cell key={i} fill={b.c >= 0 ? col.down : col.up} />)}
                        </Bar>
                      </BarChart>
                    </ResponsiveContainer>
                  </div>
                </Boundary>
                <p className="flex items-start gap-1.5 border-t border-line px-4 py-2 text-[11px] text-muted"><Info size={12} className="mt-0.5 shrink-0" />
                  Red raises the forecast above the market average, green lowers it. The model is linear in these six inputs, so this split is exact (linear SHAP with today's universe as background); check sum {E.check_sum.toExponential(1)}.</p>
              </Card>

              <Card title="Inputs" bodyClass="overflow-x-auto">
                <table className="w-full text-[12px]">
                  <thead><tr className="border-b border-line text-left text-[10.5px] uppercase tracking-wider text-muted">
                    <th className="px-3 py-1.5">Input</th><th className="px-3">Group</th><th className="px-3 text-right">{label}</th><th className="px-3 text-right">Mkt avg</th>
                    <th className="px-3 text-right">Coef</th><th className="px-3 text-right">Contribution</th><th className="px-3 text-right">Vol ×</th></tr></thead>
                  <tbody>{E.features.map((f) => (
                    <tr key={f.feature} className="border-b border-line/40 hover:bg-raised">
                      <td className="px-3 py-1.5">{f.label}</td><td className="px-3 text-muted">{f.group}</td>
                      <td className="num px-3 text-right">{pct(f.value_vol, 1)}</td><td className="num px-3 text-right text-muted">{pct(f.mean_vol, 1)}</td>
                      <td className="num px-3 text-right">{f.coef.toFixed(3)}</td>
                      <td className={`num px-3 text-right ${f.contribution >= 0 ? "text-down" : "text-up"}`}>{f.contribution >= 0 ? "+" : ""}{f.contribution.toFixed(4)}</td>
                      <td className="num px-3 text-right">{f.vol_factor.toFixed(3)}</td>
                    </tr>))}
                    {E.groups.map((g) => (
                      <tr key={g.group} className="bg-raised/60 font-semibold">
                        <td className="px-3 py-1.5" colSpan={5}>Σ {g.group}</td>
                        <td className={`num px-3 text-right ${g.contribution >= 0 ? "text-down" : "text-up"}`}>{g.contribution >= 0 ? "+" : ""}{g.contribution.toFixed(4)}</td>
                        <td className="num px-3 text-right">{Math.exp(g.contribution / 2).toFixed(3)}</td>
                      </tr>))}
                  </tbody>
                </table>
              </Card>
            </>
          )}

          {!!ex.data?.research_shap?.length && (
            <Card title={`Research model · mean |SHAP| by input (${market}, volatility target, walk-forward)`} bodyClass="overflow-x-auto">
              <table className="w-full text-[12px]">
                <thead><tr className="border-b border-line text-left text-[10.5px] uppercase tracking-wider text-muted">
                  <th className="px-3 py-1.5">Input</th><th className="px-3">Group</th><th className="px-3">Regime</th><th className="px-3 text-right">Mean |SHAP|</th><th className="px-3 text-right">Share</th></tr></thead>
                <tbody>{ex.data.research_shap.map((r, i) => (
                  <tr key={i} className="border-b border-line/40">
                    <td className="px-3 py-1">{r.feature}</td><td className={`px-3 ${r.group.startsWith("QSW") ? "text-quantum" : "text-muted"}`}>{r.group}</td><td className="px-3">{r.regime}</td>
                    <td className="num px-3 text-right">{r.mean_abs_shap.toFixed(4)}</td><td className="num px-3 text-right">{pct(r.share_within_task, 1)}</td></tr>))}
                </tbody>
              </table>
              <p className="border-t border-line px-4 py-2 text-[11px] text-muted">From results/tables/explainability_shap.csv (scripts/15_explainability.R): the research model adds quantum-walk (QSW, ω = 0.25) features to HAR; the live forecast above uses the classical graph-HAR baseline.</p>
            </Card>
          )}
        </div>
      </div>
    </div>
  );
}
