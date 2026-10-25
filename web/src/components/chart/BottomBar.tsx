import { useEffect, useRef, useState } from "react";
import { CalendarDays, Info, Radio } from "lucide-react";
import type { BarRange } from "../../lib/api";
import { RANGES, type ScaleMode } from "./types";

export default function BottomBar(p: {
  range: BarRange; onRange: (r: BarRange) => void; allowed: (r: BarRange) => boolean;
  onGoTo: (isoDate: string) => void;
  tz: string;
  scaleMode: ScaleMode; onScaleMode: (m: ScaleMode) => void; autoScale: boolean; onAutoScale: (b: boolean) => void;
  note?: string | null; source?: string; live?: boolean; snapshot: boolean;
}) {
  const [dateOpen, setDateOpen] = useState(false);
  const date = useRef<HTMLInputElement>(null);
  useEffect(() => { if (dateOpen) date.current?.focus(); }, [dateOpen]);
  const tog = (on: boolean) => `rounded px-1.5 py-0.5 text-[12px] transition ${on ? "bg-accent/15 text-accent" : "text-muted hover:bg-raised hover:text-ink"}`;

  return (
    <div className="flex items-center gap-1 overflow-x-auto border-t border-line/70 px-1.5 py-1 text-[12px] [scrollbar-width:none]">
      <div className="flex shrink-0 items-center" role="group" aria-label="Date range">
        {RANGES.map((r) => (
          <button key={r.value} type="button" disabled={!p.allowed(r.value)} onClick={() => p.onRange(r.value)} aria-pressed={p.range === r.value}
                  className={`rounded px-1.5 py-0.5 font-medium transition disabled:cursor-not-allowed disabled:opacity-30 ${p.range === r.value ? "bg-accent/15 text-accent" : "text-muted hover:bg-raised hover:text-ink"}`}>
            {r.label}
          </button>
        ))}
      </div>
      <span className="mx-1 h-4 w-px shrink-0 bg-line" aria-hidden />
      {dateOpen ? (
        <input ref={date} type="date" aria-label="Go to date" onBlur={() => setDateOpen(false)}
               onChange={(e) => { if (e.target.value) { p.onGoTo(e.target.value); setDateOpen(false); } }}
               onKeyDown={(e) => { if (e.key === "Escape") setDateOpen(false); }}
               className="shrink-0 rounded border border-line bg-raised px-1 py-0.5 text-[12px] text-ink outline-none" />
      ) : (
        <button type="button" title="Go to date" aria-label="Go to date" onClick={() => setDateOpen(true)}
                className="grid h-6 w-6 shrink-0 place-items-center rounded text-muted hover:bg-raised hover:text-ink"><CalendarDays size={14} /></button>
      )}
      {p.source === "snapshot_5s" && <span className="shrink-0 rounded border border-warn/40 px-1.5 text-[11px] text-warn" title="5-second bars built by the API from 2-second Yahoo price snapshots; not exchange ticks">snapshot-built 5s</span>}
      {p.snapshot && <span className="shrink-0 rounded border border-line px-1.5 text-[11px] text-muted" title="Static snapshot: only 1D·1m and 1Y·1D views are saved">saved snapshot</span>}
      {p.live && !p.snapshot && <span className="inline-flex shrink-0 items-center gap-1 text-[11px] text-up"><Radio size={11} />live</span>}
      {p.note && <span className="inline-flex min-w-0 shrink items-center gap-1 truncate text-[11px] text-muted" title={p.note}><Info size={11} className="shrink-0" /><span className="truncate">{p.note}</span></span>}
      <span className="ml-auto" />
      <Clock tz={p.tz} />
      <span className="mx-1 h-4 w-px shrink-0 bg-line" aria-hidden />
      <div className="flex shrink-0 items-center gap-0.5">
        <button type="button" title="Percent scale" aria-pressed={p.scaleMode === "percent"} onClick={() => p.onScaleMode(p.scaleMode === "percent" ? "normal" : "percent")} className={tog(p.scaleMode === "percent")}>%</button>
        <button type="button" title="Logarithmic scale" aria-pressed={p.scaleMode === "log"} onClick={() => p.onScaleMode(p.scaleMode === "log" ? "normal" : "log")} className={tog(p.scaleMode === "log")}>log</button>
        <button type="button" title="Auto-fit the price scale" aria-pressed={p.autoScale} onClick={() => p.onAutoScale(!p.autoScale)} className={tog(p.autoScale)}>auto</button>
      </div>
    </div>
  );
}

/** Exchange clock, e.g. "15:28:32 UTC+5:30". */
function Clock({ tz }: { tz: string }) {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => { const id = window.setInterval(() => setNow(new Date()), 1000); return () => window.clearInterval(id); }, []);
  let time = "", off = "";
  try {
    time = new Intl.DateTimeFormat("en-GB", { timeZone: tz, hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false }).format(now);
    off = new Intl.DateTimeFormat("en-US", { timeZone: tz, timeZoneName: "shortOffset" }).formatToParts(now).find((x) => x.type === "timeZoneName")?.value ?? "";
    off = off.replace(/^GMT/, "UTC") || "UTC";
  } catch { time = now.toISOString().slice(11, 19); off = "UTC"; }
  return <span className="num shrink-0 text-muted" title={tz}>{time} {off}</span>;
}
