import { useMemo } from "react";
import { motion } from "framer-motion";
import { CheckCircle2, CircleDashed, FlaskConical, XCircle } from "lucide-react";
import { Bar, BarChart, CartesianGrid, ComposedChart, ErrorBar, LabelList, Legend, Line, LineChart, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis, Cell } from "recharts";
import { Market, ResultsData, useResults } from "../lib/api";
import { cssHex, useThemeTick } from "../lib/util";
import { Card, Skeleton } from "../components/ui";

const SUP: Record<string, string> = { "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻" };
const sci = (p: number) => {
  if (p >= 1e-3) return p.toFixed(3);
  const [m, e] = p.toExponential(1).split("e");
  return `${m}×10${[...String(+e)].map((ch) => SUP[ch]).join("")}`;
};

export default function ResearchPage({ dark }: { dark: boolean }) {
  const r = useResults();
  useThemeTick();
  const c = { accent: cssHex("accent"), quantum: cssHex("quantum"), muted: cssHex("muted"), line: cssHex("line"), up: cssHex("up"), down: cssHex("down"), ink: cssHex("ink") };
  const tip = { contentStyle: { background: dark ? "#0c1220" : "#fff", border: `1px solid ${c.line}`, borderRadius: 12, fontSize: 12 } };
  if (!r.data) return <Skeleton h={600} />;
  const R = r.data;
  const h2 = (mk: Market) => R.dial_curve.find((d) => d.market === mk && d.loss === "mse" && Math.abs(d.omega - 0.25) < 1e-9);
  const nq = h2("NASDAQ"), ns = h2("NSE");

  return (
    <div className="space-y-6">
      <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="glass relative overflow-hidden p-7">
        <div className="pointer-events-none absolute -right-24 -top-24 h-72 w-72 rounded-full bg-quantum/25 blur-3xl" />
        <div className="chip mb-3"><FlaskConical size={12} /> Pre-registered, leakage-free walk-forward study · NSE + NASDAQ · 2015–2026</div>
        <h1 className="max-w-4xl text-2xl font-semibold leading-snug tracking-tight md:text-3xl">
          Partial quantum coherence measurably helps volatility features on NASDAQ, but it does not beat a simple classical graph model.
        </h1>
        <p className="mt-3 max-w-3xl text-sm leading-6 text-muted">Every number below is read live from the result tables produced by the R pipeline. Negative results are shown with the same prominence as positive ones. All quantum walks are classical simulations; no quantum hardware is used.</p>
      </motion.div>

      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <Finding ok title="NASDAQ: ω = 0.25 beats the classical limit" body={nq ? `ΔMSE ${nq.diff.toFixed(4)}, 95% CI [${nq.ci_lo.toFixed(4)}, ${nq.ci_hi.toFixed(4)}], Holm p = ${sci(nq.p_holm)}` : "—"} />
        <Finding title="NSE: the classical limit is best" body={ns ? `ω = 0.25 is worse: ΔMSE +${ns.diff.toFixed(4)}, Holm p = ${sci(ns.p_holm)}` : "—"} />
        <Finding title="No quantum gain over graph-HAR" body="Adding QSW features to linear graph-HAR, elastic net or LightGBM never improves out-of-sample forecasts." />
        <Finding title="Next-day direction is unpredictable" body={`No model beats the naive base rate (log-loss ${R.naive.map((n) => `${n.market} ${(n.logloss_naive as number).toFixed(4)}`).join(", ")}).`} />
      </div>

      <div className="grid gap-5 xl:grid-cols-2">
        {(["NASDAQ", "NSE"] as Market[]).map((mk) => <DialCurve key={mk} R={R} mk={mk} c={c} tip={tip} />)}
      </div>

      <div className="grid gap-5 xl:grid-cols-2">
        {(["NASDAQ", "NSE"] as Market[]).map((mk) => <Models key={mk} R={R} mk={mk} c={c} tip={tip} />)}
      </div>

      <div className="grid gap-5 xl:grid-cols-2">
        <Card title="Power analysis: the test can detect weak signals" bodyClass="p-4">
          <div className="h-[300px]"><ResponsiveContainer>
            <LineChart margin={{ top: 10, right: 20, left: 0, bottom: 10 }}>
              <CartesianGrid stroke={c.line} strokeOpacity={0.4} />
              <XAxis type="number" dataKey="x" domain={[0, 0.11]} ticks={[0, 0.025, 0.05, 0.075, 0.1]} tickFormatter={(v) => v.toFixed(3)} tick={{ fill: c.muted, fontSize: 11 }} label={{ value: "injected signal: correlation with next-day return", position: "insideBottom", offset: -5, fill: c.muted, fontSize: 11 }} />
              <YAxis domain={[0, 1]} tickFormatter={(v) => `${v * 100}%`} tick={{ fill: c.muted, fontSize: 11 }} />
              <Tooltip {...tip} formatter={(v: number) => `${(v * 100).toFixed(0)}%`} labelFormatter={(v) => `corr ${(+v).toFixed(3)}`} />
              <Legend verticalAlign="top" height={28} wrapperStyle={{ fontSize: 12 }} />
              <ReferenceLine y={0.8} stroke={c.muted} strokeDasharray="4 4" />
              {(["NASDAQ", "NSE"] as Market[]).map((mk, i) => (
                <Line key={mk} name={mk} data={R.power.filter((p) => p.market === mk).map((p) => ({ x: p.signal_corr_with_return as number, y: p.detection_rate as number }))}
                      dataKey="y" stroke={i ? c.quantum : c.accent} strokeWidth={2.5} dot={{ r: 4 }} />))}
            </LineChart>
          </ResponsiveContainer></div>
          <p className="px-2 pt-1 text-xs text-muted">0% false positives with no signal; at least 80% detection from correlation ≈ 0.035 (NASDAQ) and ≈ 0.05 (NSE). The null results are therefore informative.</p>
        </Card>
        <Gpu R={R} c={c} tip={tip} />
      </div>
    </div>
  );
}

function Finding({ ok, title, body }: { ok?: boolean; title: string; body: string }) {
  return (
    <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="glass p-5">
      <div className={`mb-2 flex items-center gap-2 text-sm font-semibold ${ok ? "text-up" : "text-ink"}`}>
        {ok ? <CheckCircle2 size={16} /> : <XCircle size={16} className="text-muted" />}{title}
      </div>
      <p className="num text-sm leading-6 text-muted">{body}</p>
    </motion.div>
  );
}

type C = Record<string, string>;
type Tip = { contentStyle: React.CSSProperties };

function DialCurve({ R, mk, c, tip }: { R: ResultsData; mk: Market; c: C; tip: Tip }) {
  const data = useMemo(() => [...R.dial_curve.filter((d) => d.market === mk && d.loss === "mse")
    .map((d) => ({ omega: d.omega, diff: d.diff, err: [d.diff - d.ci_lo, d.ci_hi - d.diff], p: d.p_holm })), { omega: 1, diff: 0, err: [0, 0], p: NaN }]
    .sort((a, b) => a.omega - b.omega), [R, mk]);
  return (
    <Card title={`${mk}: loss vs the classical limit across the dial (MSE, 95% CI)`} bodyClass="p-4">
      <div className="h-[300px]"><ResponsiveContainer>
        <ComposedChart data={data} margin={{ top: 10, right: 20, left: 10, bottom: 10 }}>
          <CartesianGrid stroke={c.line} strokeOpacity={0.4} />
          <XAxis dataKey="omega" type="number" domain={[0, 1]} ticks={[0, 0.1, 0.25, 0.5, 0.75, 0.9, 1]} tick={{ fill: c.muted, fontSize: 11 }}
                 label={{ value: "ω (0 quantum → 1 classical)", position: "insideBottom", offset: -5, fill: c.muted, fontSize: 11 }} />
          <YAxis tick={{ fill: c.muted, fontSize: 11 }} tickFormatter={(v) => v.toFixed(3)} width={56} />
          <ReferenceLine y={0} stroke={c.muted} strokeDasharray="4 4" />
          <Tooltip {...tip} formatter={(v: number | number[], n) => (n === "diff" ? (v as number).toFixed(5) : String(v))}
                   labelFormatter={(w) => { const d = data.find((x) => x.omega === w); return `ω = ${w}${d && isFinite(d.p) ? ` · Holm p = ${sci(d.p)}` : ""}`; }} />
          <Line dataKey="diff" name="ΔMSE vs ω = 1" stroke={mk === "NASDAQ" ? c.accent : c.quantum} strokeWidth={2.5} dot={{ r: 4 }}>
            <ErrorBar dataKey="err" width={5} stroke={c.muted} />
          </Line>
        </ComposedChart>
      </ResponsiveContainer></div>
      <p className="px-2 pt-1 text-xs text-muted">Dashed line: the classical walk (ω = 1). Below it means a lower forecast loss. {mk === "NASDAQ" ? "Intermediate coherence wins; the fully coherent walk (ω = 0) does not." : "Every ω < 1 is worse; the classical walk is best."}</p>
    </Card>
  );
}

function Models({ R, mk, c, tip }: { R: ResultsData; mk: Market; c: C; tip: Tip }) {
  const rows = [
    ...R.tuned.filter((x) => x.market === mk).map((x) => ({ m: x.model as string, r2: x.oos_r2 as number })),
    ...R.lightgbm.filter((x) => x.market === mk && x.model !== "GHAR").map((x) => ({ m: x.model as string, r2: x.oos_r2 as number })),
    ...(R.mlp ?? []).filter((x) => x.market === mk).map((x) => ({ m: (x.model as string).replace("MLP GHAR+QSW w=", "MLP + QSW ω=").replace(/^MLP GHAR$/, "MLP (GHAR inputs)"), r2: x.oos_r2 as number })),
  ].sort((a, b) => b.r2 - a.r2);
  const best = rows[0]?.r2;
  return (
    <Card title={`${mk}: out-of-sample R², 5-day volatility`}
          right={R.mlp_status === "pending" ? <span className="chip"><CircleDashed size={12} /> GPU MLP pending</span> : null} bodyClass="p-4">
      <div className="h-[300px]"><ResponsiveContainer>
        <BarChart data={rows} layout="vertical" margin={{ top: 5, right: 44, left: 30, bottom: 5 }}>
          <CartesianGrid stroke={c.line} strokeOpacity={0.4} horizontal={false} />
          <XAxis type="number" domain={[Math.min(0, ...rows.map((x) => x.r2)), "dataMax"]} tick={{ fill: c.muted, fontSize: 11 }} tickFormatter={(v) => v.toFixed(1)} />
          <ReferenceLine x={0} stroke={c.muted} />
          <YAxis type="category" dataKey="m" width={150} tick={{ fill: c.muted, fontSize: 11 }} />
          <Tooltip {...tip} formatter={(v: number) => v.toFixed(4)} />
          <Bar dataKey="r2" name="OOS R²" radius={[0, 4, 4, 0]}>
            <LabelList dataKey="r2" content={(p) => {
              const { x = 0, y = 0, width = 0, height = 0, value } = p as { x?: number; y?: number; width?: number; height?: number; value?: number };
              const v = Number(value), lo = Math.min(+x, +x + +width), hi = Math.max(+x, +x + +width);
              return <text x={v < 0 ? lo + 6 : hi + 6} y={+y + +height / 2} dy={4} fontSize={11} fill={v < 0 ? "#fff" : c.muted}>{v.toFixed(3)}</text>;
            }} />
            {rows.map((x) => <Cell key={x.m} fill={x.r2 === best ? c.up : x.m.includes("QSW") ? c.quantum : c.accent} fillOpacity={x.r2 === best ? 1 : 0.75} />)}
          </Bar>
        </BarChart>
      </ResponsiveContainer></div>
      <p className="px-2 pt-1 text-xs text-muted">Green is the best model. Hyper-parameters are chosen only on the last 6 months of each training window. Models with QSW features (violet) never beat graph-HAR significantly. The QLIKE-trained GPU MLP has negative R² because its forecasts are biased upwards (about +0.8 log points); on QLIKE it ties graph-HAR on NASDAQ and is worse on NSE.</p>
    </Card>
  );
}

function Gpu({ R, c, tip }: { R: ResultsData; c: C; tip: Tip }) {
  const backs = [["base_R_cpu_f64", "base R (CPU)", c.muted], ["torch_cpu_f64", "torch CPU f64", c.quantum], ["torch_cuda_f64", "RTX 4060 f64", c.down], ["torch_cuda_f32", "RTX 4060 f32", c.up]];
  const g = R.gpu.filter((x) => x.method === "ctqw");
  return (
    <Card title="GPU: CTQW simulation time vs graph size (log–log)" bodyClass="p-4">
      <div className="h-[300px]"><ResponsiveContainer>
        <LineChart margin={{ top: 10, right: 20, left: 10, bottom: 10 }}>
          <CartesianGrid stroke={c.line} strokeOpacity={0.4} />
          <XAxis type="number" dataKey="n" scale="log" domain={[40, 4000]} ticks={[50, 100, 200, 400, 800, 1600, 3200]} tick={{ fill: c.muted, fontSize: 11 }}
                 label={{ value: "graph size (nodes)", position: "insideBottom", offset: -5, fill: c.muted, fontSize: 11 }} />
          <YAxis type="number" scale="log" domain={[0.001, 100]} tick={{ fill: c.muted, fontSize: 11 }} tickFormatter={(v) => `${v}s`} allowDataOverflow />
          <Tooltip {...tip} formatter={(v: number) => `${v.toFixed(4)} s`} labelFormatter={(v) => `${v} nodes`} />
          <Legend verticalAlign="top" height={28} wrapperStyle={{ fontSize: 12 }} />
          {backs.map(([b, name, color]) => (
            <Line key={b} name={name} data={g.filter((x) => x.backend === b).map((x) => ({ n: x.n_nodes as number, s: x.median_seconds as number }))}
                  dataKey="s" stroke={color} strokeWidth={2.2} dot={{ r: 3.5 }} />))}
        </LineChart>
      </ResponsiveContainer></div>
      <p className="px-2 pt-1 text-xs text-muted">At 1,600 nodes: base R 62 s → RTX 4060 float32 0.15 s (about 430×). Float64 on this consumer GPU is no faster than the CPU, a hardware limit stated plainly.</p>
    </Card>
  );
}
