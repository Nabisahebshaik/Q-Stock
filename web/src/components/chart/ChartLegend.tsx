import { ReactNode, useMemo } from "react";
import { Copy, Eye, EyeOff, MoreHorizontal, Settings2, Trash2 } from "lucide-react";
import type { Bar, IndicatorOut } from "../../lib/api";
import { compact } from "../../lib/util";
import { IND_META, specTitle, type IndicatorSpec } from "./types";
import { lineLookup, matchIndicator } from "./indicators";
import { MenuItem, MenuSep, Popover } from "./Popover";

const fmt = (x: number | undefined | null, d: number) => (x == null || !isFinite(x) ? "—" : x.toLocaleString("en-US", { minimumFractionDigits: d, maximumFractionDigits: d }));

export default function ChartLegend({ label, name, interval, market, bar, prev, specs, indicators, onToggle, onSettings, onRemove, onCopy }: {
  label: string; name?: string; interval: string; market: string; bar?: Bar; prev?: Bar;
  specs: IndicatorSpec[]; indicators: IndicatorOut[];
  onToggle: (uid: string) => void; onSettings: (uid: string) => void; onRemove: (uid: string) => void; onCopy: (uid: string) => void;
}) {
  const d = bar && bar.close < 10 ? 4 : 2;
  const ch = bar && prev ? bar.close - prev.close : bar ? bar.close - bar.open : null;
  const base = prev?.close ?? bar?.open;
  const chPct = ch != null && base ? (100 * ch) / base : null;
  const dirCls = ch == null ? "text-muted" : ch > 0 ? "text-up" : ch < 0 ? "text-down" : "text-muted";
  const lookups = useMemo(() => new Map(specs.map((s) => {
    const o = matchIndicator(s, indicators);
    return [s.uid, o ? lineLookup(o) : null] as const;
  })), [specs, indicators]);

  return (
    <div className="pointer-events-none absolute left-2 top-1.5 z-10 max-w-[calc(100%-70px)] select-none text-[12px] leading-5">
      <div className="flex flex-wrap items-baseline gap-x-2">
        <span className="font-semibold text-ink" title={name}>{label}</span>
        <span className="text-muted">· {interval} · {market}</span>
        {bar && (
          <span className="num flex flex-wrap gap-x-2 text-muted">
            <span>O<span className={`ml-0.5 ${dirCls}`}>{fmt(bar.open, d)}</span></span>
            <span>H<span className={`ml-0.5 ${dirCls}`}>{fmt(bar.high, d)}</span></span>
            <span>L<span className={`ml-0.5 ${dirCls}`}>{fmt(bar.low, d)}</span></span>
            <span>C<span className={`ml-0.5 ${dirCls}`}>{fmt(bar.close, d)}</span></span>
            <span className={dirCls}>{ch != null ? `${ch > 0 ? "+" : ""}${fmt(ch, d)} (${chPct! > 0 ? "+" : ""}${fmt(chPct, 2)}%)` : ""}</span>
          </span>
        )}
      </div>
      {specs.map((s) => {
        const lk = lookups.get(s.uid);
        const vals = s.type === "volume"
          ? (bar ? [compact(bar.volume)] : [])
          : (lk ?? []).map((l) => (bar ? fmt(l.at.get(bar.time), s.type === "rsi" ? 2 : d) : "—"));
        const missing = s.type !== "volume" && !lk;
        return (
          <div key={s.uid} className={`group pointer-events-auto flex w-max max-w-full items-center gap-1.5 rounded bg-surface/40 px-1 hover:bg-raised/80 ${s.visible ? "" : "opacity-50"}`}>
            <span className="text-ink/90">{specTitle(s)}</span>
            {vals.map((v, i) => <span key={i} className="num" style={{ color: s.color }}>{v}</span>)}
            {missing && <span className="text-[11px] text-muted" title="not returned by the server for this view">{s.type === "vwap" ? "intraday only" : "n/a"}</span>}
            <span className="ml-1 flex items-center opacity-60 transition group-hover:opacity-100 group-focus-within:opacity-100">
              <RowBtn label={s.visible ? `Hide ${IND_META[s.type].name}` : `Show ${IND_META[s.type].name}`} onClick={() => onToggle(s.uid)}>
                {s.visible ? <Eye size={13} /> : <EyeOff size={13} />}
              </RowBtn>
              {s.type !== "volume" && <RowBtn label="Settings" onClick={() => onSettings(s.uid)}><Settings2 size={13} /></RowBtn>}
              <RowBtn label="Remove" onClick={() => onRemove(s.uid)}><Trash2 size={13} /></RowBtn>
              <Popover label="More" btnClass={ROW_BTN} button={<MoreHorizontal size={13} />}>
                {(close) => (<>
                  <MenuItem onClick={() => { onToggle(s.uid); close(); }}>{s.visible ? <EyeOff size={14} /> : <Eye size={14} />}{s.visible ? "Hide" : "Show"}</MenuItem>
                  {s.type !== "volume" && <MenuItem onClick={() => { onSettings(s.uid); close(); }}><Settings2 size={14} />Settings…</MenuItem>}
                  <MenuItem onClick={() => { onCopy(s.uid); close(); }}><Copy size={14} />Copy settings</MenuItem>
                  <MenuSep />
                  <MenuItem onClick={() => { onRemove(s.uid); close(); }}><Trash2 size={14} className="text-down" />Remove</MenuItem>
                </>)}
              </Popover>
            </span>
          </div>
        );
      })}
    </div>
  );
}

const RowBtn = ({ label, onClick, children }: { label: string; onClick: () => void; children: ReactNode }) => (
  <button type="button" title={label} aria-label={label} onClick={onClick}
          className={ROW_BTN}>{children}</button>
);
const ROW_BTN = "grid h-6 w-6 place-items-center rounded text-muted hover:bg-line/60 hover:text-ink focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-accent";
