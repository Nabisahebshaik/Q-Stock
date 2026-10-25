import { useMemo, useState } from "react";
import { Camera, Check, ChevronDown, FlaskConical, Maximize, Minimize, PanelLeft, Redo2, Search, Settings, Undo2 } from "lucide-react";
import type { BarInterval } from "../../lib/api";
import { CHART_TYPES, INTERVALS, intervalLabel, type ChartSettings, type ChartType, type ScaleMode } from "./types";
import ChartTypeIcon from "./ChartTypeIcon";
import { IconBtn, MenuHead, MenuItem, MenuSep, Popover } from "./Popover";

export interface TickerInfo { ticker: string; label: string; name: string }

export default function ChartToolbar(p: {
  tickers: TickerInfo[]; ticker: string; onTicker: (t: string) => void;
  interval: BarInterval; onInterval: (i: BarInterval) => void; allowed: (i: BarInterval) => boolean;
  chartType: ChartType; onChartType: (t: ChartType) => void;
  onIndicators: () => void;
  canUndo: boolean; canRedo: boolean; onUndo: () => void; onRedo: () => void;
  onScreenshot: () => void; onFullscreen: () => void; fullscreen: boolean;
  scaleMode: ScaleMode; onScaleMode: (m: ScaleMode) => void;
  settings: ChartSettings; onSettings: (s: ChartSettings) => void;
  toolsOpen: boolean; onToggleTools: () => void;
}) {
  const cur = p.tickers.find((t) => t.ticker === p.ticker);
  const CT = CHART_TYPES.find((c) => c.value === p.chartType) ?? CHART_TYPES[0];
  const sep = <span className="mx-0.5 h-5 w-px shrink-0 bg-line" aria-hidden />;

  return (
    <div className="flex items-center gap-0.5 overflow-x-auto border-b border-line/70 px-1.5 py-1 [scrollbar-width:none]" role="toolbar" aria-label="Chart toolbar">
      <IconBtn label={p.toolsOpen ? "Hide drawing tools" : "Show drawing tools"} onClick={p.onToggleTools} active={p.toolsOpen} className="md:hidden"><PanelLeft size={17} /></IconBtn>
      <SymbolPicker tickers={p.tickers} current={cur} ticker={p.ticker} onPick={p.onTicker} />
      {sep}
      <Popover label="Interval" title="Interval" button={<span className="flex items-center gap-0.5 px-0.5 font-medium text-ink">{intervalLabel(p.interval)}<ChevronDown size={13} className="text-muted" /></span>}>
        {(close) => (<>
          <MenuHead>Intraday</MenuHead>
          {INTERVALS.filter((i) => i.intraday).map((i) => (
            <MenuItem key={i.value} active={i.value === p.interval} disabled={!p.allowed(i.value)} onClick={() => { p.onInterval(i.value); close(); }}
                      hint={i.value === "5s" ? "snapshot-built" : undefined}>{label(i.value)}</MenuItem>
          ))}
          <MenuSep /><MenuHead>Daily and longer</MenuHead>
          {INTERVALS.filter((i) => !i.intraday).map((i) => (
            <MenuItem key={i.value} active={i.value === p.interval} disabled={!p.allowed(i.value)} onClick={() => { p.onInterval(i.value); close(); }}>{label(i.value)}</MenuItem>
          ))}
        </>)}
      </Popover>
      {sep}
      <Popover label="Chart type" title={`Chart type: ${CT.label}`} button={<ChartTypeIcon type={CT.value} />}>
        {(close) => CHART_TYPES.map((c) => (
          <MenuItem key={c.value} active={c.value === p.chartType} onClick={() => { p.onChartType(c.value); close(); }}><ChartTypeIcon type={c.value} size={16} />{c.label}</MenuItem>
        ))}
      </Popover>
      {sep}
      <IconBtn label="Indicators" onClick={p.onIndicators} className="px-2"><FlaskConical size={16} /><span className="hidden sm:inline">Indicators</span></IconBtn>
      {sep}
      <IconBtn label="Undo drawing" onClick={p.onUndo} disabled={!p.canUndo}><Undo2 size={17} /></IconBtn>
      <IconBtn label="Redo drawing" onClick={p.onRedo} disabled={!p.canRedo}><Redo2 size={17} /></IconBtn>
      <span className="ml-auto" />
      <Popover label="Chart settings" align="right" button={<Settings size={17} />} panelClass="w-56">
        {() => (<>
          <MenuHead>Price scale</MenuHead>
          {([["normal", "Regular"], ["percent", "Percent"], ["log", "Logarithmic"]] as [ScaleMode, string][]).map(([m, t]) => (
            <MenuItem key={m} active={p.scaleMode === m} onClick={() => p.onScaleMode(m)}><Tick on={p.scaleMode === m} />{t}</MenuItem>
          ))}
          <MenuSep /><MenuHead>Canvas</MenuHead>
          <MenuItem onClick={() => p.onSettings({ ...p.settings, grid: !p.settings.grid })}><Tick on={p.settings.grid} />Grid lines</MenuItem>
          <MenuSep /><MenuHead>Crosshair</MenuHead>
          <MenuItem active={p.settings.crosshair === "normal"} onClick={() => p.onSettings({ ...p.settings, crosshair: "normal" })}><Tick on={p.settings.crosshair === "normal"} />Free</MenuItem>
          <MenuItem active={p.settings.crosshair === "magnet"} onClick={() => p.onSettings({ ...p.settings, crosshair: "magnet" })}><Tick on={p.settings.crosshair === "magnet"} />Magnet to close</MenuItem>
        </>)}
      </Popover>
      <IconBtn label={p.fullscreen ? "Exit fullscreen" : "Fullscreen"} onClick={p.onFullscreen}>{p.fullscreen ? <Minimize size={17} /> : <Maximize size={17} />}</IconBtn>
      <IconBtn label="Take a snapshot (PNG)" onClick={p.onScreenshot}><Camera size={17} /></IconBtn>
    </div>
  );
}

const label = (i: BarInterval) => {
  const n = parseInt(i, 10), u = i.replace(/^\d+/, "");
  const word = u === "s" ? "second" : u === "m" ? "minute" : u === "h" ? "hour" : u === "d" ? "day" : u === "w" ? "week" : "month";
  return `${n} ${word}${n > 1 ? "s" : ""}`;
};
const Tick = ({ on }: { on: boolean }) => <Check size={14} className={on ? "text-accent" : "opacity-0"} aria-hidden />;

function SymbolPicker({ tickers, current, ticker, onPick }: { tickers: TickerInfo[]; current?: TickerInfo; ticker: string; onPick: (t: string) => void }) {
  const [q, setQ] = useState("");
  const list = useMemo(() => {
    const s = q.trim().toLowerCase();
    return s ? tickers.filter((t) => `${t.label} ${t.ticker} ${t.name}`.toLowerCase().includes(s)) : tickers;
  }, [tickers, q]);
  return (
    <Popover label="Symbol search" title={current?.name ?? ticker} panelClass="w-72"
             button={<span className="flex items-center gap-1.5 px-1 font-semibold text-ink"><Search size={14} className="text-muted" />{current?.label ?? ticker}</span>}>
      {(close) => (<>
        <div className="p-1">
          <input autoFocus value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search symbol" aria-label="Search symbol"
                 onKeyDown={(e) => { if (e.key === "Enter" && list[0]) { onPick(list[0].ticker); setQ(""); close(); } }}
                 className="w-full rounded-md border border-line bg-raised/60 px-2.5 py-1.5 text-sm outline-none placeholder:text-muted focus:border-accent" />
        </div>
        {list.map((t) => (
          <MenuItem key={t.ticker} active={t.ticker === ticker} onClick={() => { onPick(t.ticker); setQ(""); close(); }} hint={t.ticker}>
            <span className="w-24 shrink-0 font-medium">{t.label}</span><span className="truncate text-xs text-muted">{t.name}</span>
          </MenuItem>
        ))}
        {!list.length && <div className="px-2.5 py-2 text-sm text-muted">No match in this market.</div>}
      </>)}
    </Popover>
  );
}
