import { motion } from "framer-motion";
import { Atom, Boxes, Cpu, Database, Globe, HardDrive, LayoutDashboard, Server, Sparkles, Table2 } from "lucide-react";
import { useResults } from "../lib/api";
import { compact, exact, useReducedMotion } from "../lib/util";

interface Stage { icon: typeof Globe; name: string; tech: string; facts: string[] }

export default function PipelinePage() {
  const r = useResults().data;
  const reduced = useReducedMotion();
  const spark = r?.spark?.length ? r.spark.reduce((a, b) => ((b.rows as number) > (a.rows as number) ? b : a)) : null;
  const gpu = r?.gpu?.filter((x) => x.method === "ctqw" && x.n_nodes === 1600);
  const t = (b: string) => gpu?.find((x) => x.backend === b)?.median_seconds as number | undefined;
  const speed = t("base_R_cpu_f64") && t("torch_cuda_f32") ? Math.round(t("base_R_cpu_f64")! / t("torch_cuda_f32")!) : null;

  const stages: Stage[] = [
    { icon: Globe, name: "Ingest", tech: "Yahoo chart API · GDELT", facts: ["20 NSE + 20 NASDAQ large caps", "daily 2015 → 2026-10-21", "live 1-minute bars (dashboard)"] },
    { icon: HardDrive, name: "HDFS", tech: "WebHDFS from R · Cloudera CDH 5.13", facts: ["raw + curated layers", "R → REST, no Python"] },
    { icon: Boxes, name: "MapReduce", tech: "Java job with combiner on YARN", facts: [`${r?.mr_groups ? exact(r.mr_groups) : "—"} ticker-month groups`, "matches R exactly (max error 1.8×10⁻¹⁵)"] },
    { icon: Table2, name: "Hive", tech: "external tables · window functions", facts: ["117,600 daily rows", "consistency query: 0 mismatches"] },
    { icon: Sparkles, name: "Spark", tech: "sparklyr · Spark 3.5", facts: [spark ? `${compact(spark.rows as number)} rows in ${(spark.spark_seconds as number).toFixed(1)} s` : "7.5M rows", "point-in-time joins; agrees with R to 10⁻¹⁵"] },
    { icon: Atom, name: "Quantum-walk core", tech: "R · DTQW / CTQW / Lindblad QSW", facts: ["leakage-free walk-forward", "pre-registered tests, Holm-corrected", "187 unit-test expectations"] },
    { icon: Cpu, name: "GPU", tech: "torch for R · CUDA · RTX 4060", facts: [speed ? `CTQW about ${speed}× faster than base R (1,600 nodes, f32)` : "CUDA benchmark", "f64 limits stated honestly"] },
    { icon: Server, name: "API", tech: "R plumber", facts: ["one shared live fetch per minute", "idempotent candle store (SQLite / PostgreSQL SQL)"] },
    { icon: LayoutDashboard, name: "This interface", tech: "React · three.js · TradingView charts", facts: ["presentation only", "every number comes from R"] },
  ];

  return (
    <div className="space-y-6">
      <div className="glass p-7">
        <div className="chip mb-3"><Database size={12} /> CSE 465 · Principles of Big Data Management</div>
        <h1 className="text-2xl font-semibold tracking-tight md:text-3xl">An R-only Big Data pipeline, end to end</h1>
        <p className="mt-2 max-w-3xl text-sm leading-6 text-muted">Each stage below was validated against an independent computation. The numbers are read from the project's result tables where available.</p>
      </div>
      <div className="relative grid gap-4 md:grid-cols-3">
        {stages.map((s, i) => (
          <motion.div key={s.name} initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: reduced ? 0 : i * 0.07 }}
                      className="glass group relative p-5">
            <div className="flex items-start gap-3">
              <div className="relative grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-gradient-to-br from-quantum/30 to-accent/30 text-accent">
                <s.icon size={20} />
                {!reduced && <span className="absolute inset-0 animate-ping rounded-xl bg-accent/10 [animation-duration:3s]" />}
              </div>
              <div>
                <div className="text-xs text-muted">Stage {i + 1}</div>
                <div className="font-semibold">{s.name}</div>
                <div className="text-xs text-accent">{s.tech}</div>
              </div>
            </div>
            <ul className="mt-4 space-y-1.5 text-sm text-muted">{s.facts.map((f) => <li key={f} className="num flex gap-2"><span className="text-accent">›</span>{f}</li>)}</ul>
            {i < stages.length - 1 && (
              <div className="pointer-events-none absolute -right-4 top-1/2 hidden h-0.5 w-4 overflow-hidden bg-line md:block">
                {!reduced && <motion.div className="h-full w-2 bg-accent" animate={{ x: [-8, 16] }} transition={{ duration: 1.2, repeat: Infinity, ease: "linear", delay: i * 0.15 }} />}
              </div>
            )}
          </motion.div>
        ))}
      </div>
    </div>
  );
}
