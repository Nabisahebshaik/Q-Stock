import { Component, ReactNode, useEffect } from "react";
import { animate, motion, useMotionValue, useTransform } from "framer-motion";
import { ArrowDownRight, ArrowUpRight, Minus } from "lucide-react";

export function Card({ title, right, children, className = "", bodyClass = "" }: {
  title?: ReactNode; right?: ReactNode; children: ReactNode; className?: string; bodyClass?: string;
}) {
  return (
    <motion.section initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.45, ease: "easeOut" }}
                    className={`glass overflow-hidden ${className}`}>
      {(title || right) && (
        <header className="flex items-center justify-between gap-3 border-b border-line/60 px-5 py-3">
          <h2 className="card-title">{title}</h2>
          <div className="flex items-center gap-2">{right}</div>
        </header>
      )}
      <div className={bodyClass}>{children}</div>
    </motion.section>
  );
}

/** Number that animates smoothly to each new value. */
export function AnimatedNumber({ value, format }: { value: number | null | undefined; format: (x: number) => string }) {
  const mv = useMotionValue(value ?? 0);
  const text = useTransform(mv, (x) => (value == null ? "—" : format(x)));
  useEffect(() => { if (value != null) { const c = animate(mv, value, { duration: 0.8, ease: "easeOut" }); return c.stop; } }, [value, mv]);
  return <motion.span className="num">{text}</motion.span>;
}

export function Delta({ x, digits = 2 }: { x: number | null | undefined; digits?: number }) {
  if (x == null || !isFinite(x)) return <span className="text-muted">—</span>;
  const Icon = x > 0.00005 ? ArrowUpRight : x < -0.00005 ? ArrowDownRight : Minus;
  const cls = x > 0.00005 ? "text-up" : x < -0.00005 ? "text-down" : "text-muted";
  return <span className={`num inline-flex items-center gap-0.5 ${cls}`}><Icon size={14} aria-hidden />{x > 0 ? "+" : ""}{(100 * x).toFixed(digits)}%</span>;
}

export function Kpi({ label, children, sub, accent }: { label: string; children: ReactNode; sub?: ReactNode; accent?: boolean }) {
  return (
    <motion.div layout initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="glass relative overflow-hidden px-5 py-4">
      {accent && <div className="pointer-events-none absolute -right-10 -top-10 h-32 w-32 rounded-full bg-quantum/20 blur-2xl" />}
      <div className="card-title">{label}</div>
      <div className="mt-1.5 text-[28px] font-semibold leading-tight tracking-tight">{children}</div>
      {sub && <div className="mt-1 text-xs text-muted">{sub}</div>}
    </motion.div>
  );
}

export function Sparkline({ data, color, width = 96, height = 28 }: { data?: number[]; color: string; width?: number; height?: number }) {
  if (!data || data.length < 2) return <svg width={width} height={height} />;
  const lo = Math.min(...data), hi = Math.max(...data), span = hi - lo || 1;
  const pts = data.map((v, i) => `${(i / (data.length - 1)) * width},${height - 2 - ((v - lo) / span) * (height - 4)}`).join(" ");
  const id = `sg${Math.random().toString(36).slice(2, 8)}`;
  return (
    <svg width={width} height={height} aria-hidden>
      <defs><linearGradient id={id} x1="0" x2="0" y1="0" y2="1"><stop offset="0" stopColor={color} stopOpacity="0.35" /><stop offset="1" stopColor={color} stopOpacity="0" /></linearGradient></defs>
      <polygon points={`0,${height} ${pts} ${width},${height}`} fill={`url(#${id})`} />
      <polyline points={pts} fill="none" stroke={color} strokeWidth="1.6" strokeLinejoin="round" />
    </svg>
  );
}

export function Segmented<T extends string>({ value, options, onChange }: { value: T; options: { value: T; label: ReactNode }[]; onChange: (v: T) => void }) {
  return (
    <div className="inline-flex rounded-xl border border-line bg-raised/60 p-1" role="tablist">
      {options.map((o) => (
        <button key={o.value} role="tab" aria-selected={value === o.value} onClick={() => onChange(o.value)}
                className={`seg ${value === o.value ? "seg-on" : "seg-off"}`}>{o.label}</button>
      ))}
    </div>
  );
}

export function OmegaDial({ value, onChange, children }: { value: number; onChange: (v: number) => void; children?: ReactNode }) {
  return (
    <div>
      <div className="mb-2 flex items-baseline justify-between">
        <span className="text-sm text-muted">Quantum ↔ classical dial</span>
        <span className="num font-mono text-lg text-accent">ω = {value.toFixed(2)}</span>
      </div>
      <input aria-label="omega" type="range" min={0} max={1} step={0.05} value={value} onChange={(e) => onChange(+e.target.value)} className="dial w-full" />
      <div className="mt-1.5 flex justify-between text-[11px] text-muted"><span>0 · coherent quantum walk</span><span>1 · classical random walk</span></div>
      {children}
    </div>
  );
}

export function Skeleton({ h = 200 }: { h?: number }) {
  return <div className="m-5 animate-pulse rounded-xl bg-raised/70" style={{ height: h }} />;
}

/** Contains a failing widget so the rest of the page keeps working. */
export class Boundary extends Component<{ children: ReactNode; label?: string }, { err: string | null }> {
  state = { err: null as string | null };
  static getDerivedStateFromError(e: Error) { return { err: e.message }; }
  componentDidCatch(e: Error) { console.error(`[${this.props.label ?? "widget"}]`, e); }
  render() {
    return this.state.err
      ? <div className="m-5 rounded-xl border border-down/40 bg-down/5 p-4 text-sm text-muted">This {this.props.label ?? "panel"} failed to render: <span className="font-mono text-xs">{this.state.err}</span></div>
      : this.props.children;
  }
}
