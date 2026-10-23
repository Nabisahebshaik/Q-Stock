import { useEffect, useMemo, useState } from "react";
import { Pause, Play } from "lucide-react";
import { Bar, BarChart, CartesianGrid, Legend, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { Market, SNAPSHOT, useDial } from "../lib/api";
import { cssHex, mix, useReducedMotion, useThemeTick } from "../lib/util";
import { Card, OmegaDial, Segmented, Skeleton } from "../components/ui";
import QuantumGraph3D, { GNode } from "../components/QuantumGraph3D";

const entropy = (p: number[]) => -p.reduce((s, x) => s + (x > 0 ? x * Math.log(x) : 0), 0);

export default function DialPage({ dark }: { dark: boolean }) {
  const [market, setMarket] = useState<Market>("NASDAQ");
  const [date, setDate] = useState("");
  const [omega, setOmega] = useState(0.25);
  const [start, setStart] = useState<Record<Market, string>>({ NASDAQ: "NVDA", NSE: "RELIANCE.NS" });
  const [playing, setPlaying] = useState(false);
  const dial = useDial(market, date, omega);
  const reduced = useReducedMotion();
  useThemeTick();
  const col = { accent: cssHex("accent"), quantum: cssHex("quantum"), muted: cssHex("muted"), up: cssHex("up"), line: cssHex("line"), ink: cssHex("ink") };

  useEffect(() => {
    if (!playing) return;
    const id = setInterval(() => setOmega((w) => (w >= 1 ? 0 : Math.round((w + 0.05) * 100) / 100)), 700);
    return () => clearInterval(id);
  }, [playing]);

  const D = dial.data;
  const ids = D?.nodes?.id ?? [];
  const s = Math.max(0, ids.indexOf(start[market]));
  const p = D?.P?.[s] ?? [], pq = D?.P_quantum?.[s] ?? [], pc = D?.P_classical?.[s] ?? [];
  const pmax = Math.max(...p, 1e-9);

  const nodes: GNode[] = useMemo(() => ids.map((id, i) => {
    const z = (p[i] ?? 0) / pmax;
    return { id, label: D!.nodes!.label[i], color: i === s ? col.up : mix(dark ? "#3a4560" : "#c3cad8", mix(col.quantum, col.accent, z), Math.sqrt(z)),
             size: 0.2 + 0.32 * Math.sqrt(z), glow: i === s ? 0.35 : z,
             tooltip: [`P(ω=${omega.toFixed(2)}) = ${(p[i] ?? 0).toFixed(3)}`, `P(quantum, ω=0) = ${(pq[i] ?? 0).toFixed(3)}`, `P(classical, ω=1) = ${(pc[i] ?? 0).toFixed(3)}`] };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }), [D, s, omega, dark, col.accent, col.quantum]);
  const edges = useMemo(() => (D ? D.edges.source.map((x, i) => ({ source: x, target: D.edges.target[i], weight: Math.max(0, D.edges.rho[i]) })) : []), [D]);
  const bars = ids.map((_, i) => ({ t: D!.nodes!.label[i], sel: p[i], q: pq[i], c: pc[i] })).sort((a, b) => b.c - a.c);

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center gap-3">
        <Segmented value={market} onChange={(m) => { setMarket(m); setDate(""); }} options={[{ value: "NASDAQ", label: "NASDAQ" }, { value: "NSE", label: "NSE" }]} />
        <label className="chip gap-2">Date
          <input type="date" value={date || D?.date || ""} min={D?.min_date} max={D?.max_date} onChange={(e) => setDate(e.target.value)} disabled={SNAPSHOT} title={SNAPSHOT ? "Fixed to the latest date in the snapshot" : undefined}
                 className="bg-transparent text-ink outline-none disabled:opacity-60 [color-scheme:inherit]" />
        </label>
        <label className="chip gap-2">Walker starts at
          <select value={start[market]} onChange={(e) => setStart({ ...start, [market]: e.target.value })} className="bg-transparent text-ink outline-none">
            {ids.map((id, i) => <option key={id} value={id} className="bg-surface">{D!.nodes!.label[i]}</option>)}
          </select>
        </label>
        <span className="text-xs text-muted">60-day correlation kNN graph of {D?.date ?? "…"}; Lindblad QSW integrated in R (RK4), time-averaged over τ ∈ (0, 2].</span>
      </div>

      <div className="grid gap-5 xl:grid-cols-12">
        <Card className="xl:col-span-8" title="Where a walker from the selected stock ends up">
          {nodes.length ? <QuantumGraph3D nodes={nodes} edges={edges} flow={D?.P} selected={start[market]} onSelect={(t) => setStart({ ...start, [market]: t })}
                                          accent={col.accent} muted={col.muted} dark={dark} reducedMotion={reduced} height={560} /> : <Skeleton h={520} />}
        </Card>
        <div className="space-y-5 xl:col-span-4">
          <Card title="Dial" bodyClass="space-y-5 p-5">
            <OmegaDial value={omega} onChange={(w) => { setPlaying(false); setOmega(w); }} />
            <button className="btn" onClick={() => setPlaying(!playing)}>{playing ? <Pause size={15} /> : <Play size={15} />}{playing ? "Pause sweep" : "Sweep ω from 0 to 1"}</button>
          </Card>
          <Card title="Walk statistics" bodyClass="p-5">
            <table className="w-full text-sm">
              <thead className="text-left text-xs text-muted"><tr><th className="pb-2 font-medium">Walk</th><th className="pb-2 font-medium">Return prob.</th><th className="pb-2 font-medium">Entropy</th></tr></thead>
              <tbody className="num">
                {[[`ω = ${omega.toFixed(2)}`, p], ["ω = 0 · quantum", pq], ["ω = 1 · classical", pc]].map(([k, v]) => (
                  <tr key={k as string} className="border-t border-line/50"><td className="py-2">{k as string}</td>
                    <td>{((v as number[])[s] ?? 0).toFixed(4)}</td><td>{entropy(v as number[]).toFixed(3)}</td></tr>))}
              </tbody>
            </table>
            <p className="mt-4 text-xs leading-5 text-muted">A coherent walk (ω = 0) interferes: probability concentrates on some stocks and cancels on others. The classical walk (ω = 1) diffuses smoothly. The research tests which level of coherence gives the most useful volatility features.</p>
          </Card>
        </div>
      </div>

      <Card title="Probability by stock: selected dial setting vs the two limits" bodyClass="p-4">
        <div className="h-[340px]">
          <ResponsiveContainer>
            <BarChart data={bars} margin={{ top: 10, right: 10, left: 0, bottom: 30 }} barGap={1}>
              <CartesianGrid stroke={col.line} strokeOpacity={0.4} vertical={false} />
              <XAxis dataKey="t" angle={-45} textAnchor="end" interval={0} tick={{ fill: col.muted, fontSize: 11 }} height={60} />
              <YAxis tick={{ fill: col.muted, fontSize: 11 }} tickFormatter={(v) => v.toFixed(2)} />
              <Tooltip contentStyle={{ background: dark ? "#0c1220" : "#fff", border: `1px solid ${col.line}`, borderRadius: 12 }} formatter={(v: number) => v.toFixed(4)} />
              <Legend wrapperStyle={{ fontSize: 12, color: col.muted }} />
              <Bar dataKey="sel" name={`ω = ${omega.toFixed(2)} (selected)`} fill={col.accent} radius={[4, 4, 0, 0]} />
              <Bar dataKey="q" name="ω = 0 (quantum)" fill={col.quantum} radius={[4, 4, 0, 0]} />
              <Bar dataKey="c" name="ω = 1 (classical)" fill={dark ? "#7d8799" : "#9aa3b2"} radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </Card>
    </div>
  );
}
