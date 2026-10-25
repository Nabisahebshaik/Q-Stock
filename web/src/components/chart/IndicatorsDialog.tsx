import { useEffect, useRef, useState } from "react";
import { Eye, EyeOff, Lock, Plus, Search, Trash2, X } from "lucide-react";
import { IND_META, newSpec, specTitle, type IndicatorSpec, type IndicatorType } from "./types";

const TYPES: IndicatorType[] = ["volume", "vwap", "sma", "ema", "bb", "rsi"];
const MAX_SERVER = 8; // contract: at most 8 `ind` tokens

/** Add / edit / remove indicators. Parameters are sent to the R API, which computes the values. */
export default function IndicatorsDialog({ specs, onChange, onClose, focus, locked, intraday }: {
  specs: IndicatorSpec[]; onChange: (s: IndicatorSpec[]) => void; onClose: () => void;
  focus?: string | null; locked: boolean; intraday: boolean;
}) {
  const [q, setQ] = useState("");
  const box = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const key = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    document.addEventListener("keydown", key);
    return () => document.removeEventListener("keydown", key);
  }, [onClose]);
  useEffect(() => {
    if (focus) box.current?.querySelector<HTMLElement>(`[data-uid="${focus}"]`)?.scrollIntoView({ block: "nearest" });
  }, [focus]);
  const serverCount = specs.filter((s) => s.type !== "volume").length;
  const upd = (uid: string, patch: Partial<IndicatorSpec>) => onChange(specs.map((s) => (s.uid === uid ? { ...s, ...patch } : s)));
  const add = (t: IndicatorType) => onChange([...specs, newSpec(t)]);
  const shown = TYPES.filter((t) => `${IND_META[t].name} ${IND_META[t].desc}`.toLowerCase().includes(q.toLowerCase()));

  return (
    <div className="absolute inset-0 z-[70] grid place-items-center bg-bg/60 p-3" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div ref={box} role="dialog" aria-modal="true" aria-label="Indicators"
           className="flex max-h-full w-full max-w-lg flex-col overflow-hidden rounded-xl border border-line bg-surface shadow-2xl shadow-black/40">
        <header className="flex items-center justify-between border-b border-line/70 px-4 py-2.5">
          <h3 className="text-sm font-semibold">Indicators</h3>
          <button type="button" aria-label="Close" title="Close" onClick={onClose} className="grid h-7 w-7 place-items-center rounded text-muted hover:bg-raised hover:text-ink"><X size={16} /></button>
        </header>
        <div className="overflow-y-auto">
          <div className="border-b border-line/70 p-3">
            <label className="flex items-center gap-2 rounded-md border border-line bg-raised/60 px-2.5 py-1.5 text-sm">
              <Search size={14} className="text-muted" />
              <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search" aria-label="Search indicators" className="w-full bg-transparent outline-none placeholder:text-muted" />
            </label>
            <div className="mt-2 grid gap-1">
              {shown.map((t) => {
                const full = t !== "volume" && serverCount >= MAX_SERVER;
                const dup = (t === "volume" || t === "vwap") && specs.some((s) => s.type === t);
                return (
                  <button key={t} type="button" disabled={full || dup} onClick={() => add(t)}
                          className="flex items-center gap-3 rounded-md px-2 py-1.5 text-left text-sm hover:bg-raised disabled:cursor-not-allowed disabled:opacity-40">
                    <Plus size={14} className="text-accent" />
                    <span className="w-12 font-medium">{IND_META[t].name}</span>
                    <span className="text-xs text-muted">{IND_META[t].desc}{t === "vwap" && !intraday ? " · not on daily bars" : ""}</span>
                  </button>
                );
              })}
            </div>
            {serverCount >= MAX_SERVER && <p className="mt-1 text-[11px] text-muted">At most {MAX_SERVER} server indicators per chart.</p>}
          </div>
          <div className="p-3">
            <div className="mb-1.5 flex items-center gap-2 text-[11px] font-medium uppercase tracking-wider text-muted">
              On chart {locked && <span className="inline-flex items-center gap-1 normal-case tracking-normal"><Lock size={11} /> parameters fixed in the snapshot</span>}
            </div>
            {specs.length === 0 && <p className="text-sm text-muted">No indicators.</p>}
            <ul className="grid gap-1">
              {specs.map((s) => {
                const m = IND_META[s.type];
                return (
                  <li key={s.uid} data-uid={s.uid}
                      className={`flex flex-wrap items-center gap-2 rounded-md px-2 py-1.5 text-sm ${focus === s.uid ? "bg-accent/10 ring-1 ring-accent/40" : "bg-raised/40"}`}>
                    <input type="color" value={s.color} onChange={(e) => upd(s.uid, { color: e.target.value })} aria-label={`${specTitle(s)} colour`} title="Colour"
                           className="h-6 w-6 cursor-pointer rounded border border-line bg-transparent p-0" />
                    <span className="min-w-20 font-medium">{specTitle(s)}</span>
                    {m.n && <NumField label="Length" value={s.n!} min={m.n[1]} max={m.n[2]} step={1} disabled={locked} onCommit={(n) => upd(s.uid, { n })} />}
                    {m.k && <NumField label="StdDev" value={s.k!} min={m.k[1]} max={m.k[2]} step={0.5} disabled={locked} onCommit={(k) => upd(s.uid, { k })} />}
                    <span className="ml-auto flex items-center">
                      <button type="button" title={s.visible ? "Hide" : "Show"} aria-label={s.visible ? "Hide" : "Show"} onClick={() => upd(s.uid, { visible: !s.visible })}
                              className="grid h-7 w-7 place-items-center rounded text-muted hover:bg-raised hover:text-ink">{s.visible ? <Eye size={14} /> : <EyeOff size={14} />}</button>
                      <button type="button" title="Remove" aria-label={`Remove ${specTitle(s)}`} onClick={() => onChange(specs.filter((x) => x.uid !== s.uid))}
                              className="grid h-7 w-7 place-items-center rounded text-muted hover:bg-raised hover:text-down"><Trash2 size={14} /></button>
                    </span>
                  </li>
                );
              })}
            </ul>
            <p className="mt-3 text-[11px] leading-4 text-muted">Indicator values are computed in R on the server, including warm-up bars before the range start.</p>
          </div>
        </div>
      </div>
    </div>
  );
}

/** Number input that applies on blur / Enter (each change is a new API request). */
function NumField({ label, value, min, max, step, disabled, onCommit }: {
  label: string; value: number; min: number; max: number; step: number; disabled?: boolean; onCommit: (v: number) => void;
}) {
  const [draft, setDraft] = useState(String(value));
  useEffect(() => setDraft(String(value)), [value]);
  const commit = () => {
    const v = Number(draft);
    if (!isFinite(v)) { setDraft(String(value)); return; }
    const c = Math.min(max, Math.max(min, step >= 1 ? Math.round(v) : Math.round(v / step) * step));
    setDraft(String(c)); if (c !== value) onCommit(c);
  };
  return (
    <label className="flex items-center gap-1 text-xs text-muted">
      {label}
      <input type="number" inputMode="decimal" value={draft} min={min} max={max} step={step} disabled={disabled}
             onChange={(e) => setDraft(e.target.value)} onBlur={commit} onKeyDown={(e) => { if (e.key === "Enter") commit(); }}
             className="num w-16 rounded border border-line bg-surface px-1.5 py-0.5 text-sm text-ink outline-none focus:border-accent disabled:opacity-50" />
    </label>
  );
}
