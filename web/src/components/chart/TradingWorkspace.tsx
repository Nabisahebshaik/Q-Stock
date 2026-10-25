import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { IChartApi, ISeriesApi, SeriesType } from "lightweight-charts";
import { Loader2, Lock } from "lucide-react";
import { BarInterval, BarRange, Market, useBars, useShowingSnapshot, useStatus } from "../../lib/api";
import {
  DEFAULT_INDICATORS, DEFAULT_INTERVAL, SNAPSHOT_IND, SNAPSHOT_VIEWS, intervalLabel, isIntraday, loadPref, savePref, specToken,
  type ChartSettings, type ChartType, type IndicatorSpec, type ScaleMode,
} from "./types";
import ChartToolbar from "./ChartToolbar";
import TradingChart from "./TradingChart";
import ChartLegend from "./ChartLegend";
import BottomBar from "./BottomBar";
import IndicatorsDialog from "./IndicatorsDialog";
import { DrawingToolbar, createDrawingManager, type DrawingManager, type DrawingTool } from "./drawing";

interface Prefs {
  interval: BarInterval; range: BarRange; chartType: ChartType; scaleMode: ScaleMode; autoScale: boolean;
  settings: ChartSettings; indicators: IndicatorSpec[]; magnet: boolean;
}
const PREF_KEY = "qstock-chart-ui";
const DEFAULT_PREFS = (): Prefs => ({
  interval: "1m", range: "1D", chartType: "candles", scaleMode: "normal", autoScale: true,
  settings: { grid: true, crosshair: "normal" }, indicators: DEFAULT_INDICATORS(), magnet: false,
});
const TZ: Record<Market, string> = { NSE: "Asia/Kolkata", NASDAQ: "America/New_York" };

/** TradingView-style chart workspace (docs/design/CHART_WORKSPACE.md §4). Bars and indicator values
 *  come from the R API (`useBars`); this component only holds UI state and renders. */
export default function TradingWorkspace({ market, ticker, onTicker }: { market: Market; ticker: string; onTicker: (t: string) => void }) {
  const snapshot = useShowingSnapshot();
  const [prefs, setPrefs] = useState<Prefs>(() => ({ ...DEFAULT_PREFS(), ...loadPref<Partial<Prefs>>(PREF_KEY, {}) }));
  useEffect(() => savePref(PREF_KEY, prefs), [prefs]);
  const set = <K extends keyof Prefs>(k: K, v: Prefs[K]) => setPrefs((p) => ({ ...p, [k]: v }));

  // Snapshot mode serves only two saved views with the default indicator parameters.
  const isSnapView = SNAPSHOT_VIEWS.some((v) => v.range === prefs.range && v.interval === prefs.interval);
  const view = snapshot && !isSnapView ? SNAPSHOT_VIEWS[0] : { range: prefs.range, interval: prefs.interval };
  const ind = useMemo(() => (snapshot ? SNAPSHOT_IND : prefs.indicators.map(specToken).filter((x): x is string => !!x)
    .filter((x, i, a) => a.indexOf(x) === i).filter((x) => x !== "vwap" || isIntraday(view.interval)).slice(0, 8).join(",")),
  [snapshot, prefs.indicators, view.interval]);

  const bars = useBars(market, ticker, view.interval, view.range, ind);
  const status = useStatus();
  const tickers = useMemo(() => status.data?.find((s) => s.market === market)?.tickers ?? [], [status.data, market]);
  const D = bars.data;
  const fresh = D && D.ticker === ticker && D.market === market;
  const fitKey = D ? `${D.market}|${D.ticker}|${D.interval}|${D.range}` : "";

  const pickRange = (r: BarRange) => setPrefs((p) => ({ ...p, range: r, interval: snapshot ? SNAPSHOT_VIEWS.find((v) => v.range === r)?.interval ?? p.interval : DEFAULT_INTERVAL[r] }));
  const pickInterval = (i: BarInterval) => setPrefs((p) => ({ ...p, interval: i, range: snapshot ? SNAPSHOT_VIEWS.find((v) => v.interval === i)?.range ?? p.range : p.range }));
  const allowRange = (r: BarRange) => !snapshot || SNAPSHOT_VIEWS.some((v) => v.range === r);
  const allowInterval = (i: BarInterval) => !snapshot || SNAPSHOT_VIEWS.some((v) => v.interval === i);

  // Legend: hovered bar, else the newest.
  const [hover, setHover] = useState<number | null>(null);
  const barList = useMemo(() => D?.bars ?? [], [D]);
  const at = useMemo(() => new Map(barList.map((b, i) => [b.time, i])), [barList]);
  const hi = hover != null && at.has(hover) ? at.get(hover)! : barList.length - 1;

  // Indicators.
  const [dialog, setDialog] = useState<{ open: boolean; focus: string | null }>({ open: false, focus: null });
  const specs = prefs.indicators;
  const setSpecs = (s: IndicatorSpec[]) => set("indicators", s);
  const copySpec = (uid: string) => {
    const s = specs.find((x) => x.uid === uid); if (!s) return;
    const { type, n, k, color } = s;
    try { void navigator.clipboard?.writeText(JSON.stringify({ type, n, k, color })); } catch { /* clipboard unavailable */ }
  };

  // Chart + drawing manager.
  const root = useRef<HTMLDivElement>(null);
  const [api, setApi] = useState<{ chart: IChartApi; series: ISeriesApi<SeriesType> } | null>(null);
  const mgr = useRef<DrawingManager | null>(null);
  const [tool, setTool] = useState<DrawingTool>("cursor");
  const [locked, setLocked] = useState(false);
  const [visible, setVisible] = useState(true);
  const [hist, setHist] = useState({ undo: false, redo: false });
  const [toolsOpen, setToolsOpen] = useState(false);
  const onReady = useCallback((chart: IChartApi, series: ISeriesApi<SeriesType>) => setApi({ chart, series }), []);
  const onDetach = useCallback(() => { mgr.current?.destroy(); mgr.current = null; }, []);
  useEffect(() => {
    if (!api) return;
    const m = createDrawingManager(api.chart, api.series, {
      storageKey: `qstock-draw-${market}-${ticker}`,
      onChange: () => setHist({ undo: m.canUndo(), redo: m.canRedo() }),
    });
    mgr.current = m;
    setHist({ undo: m.canUndo(), redo: m.canRedo() });
    return () => { if (mgr.current === m) { m.destroy(); mgr.current = null; } };
  }, [api, market, ticker]);
  // Re-apply drawing modes to each new manager (chart type / ticker changes create one).
  useEffect(() => { mgr.current?.setTool(tool); }, [tool, api, market, ticker]);
  useEffect(() => { mgr.current?.setMagnet(prefs.magnet); }, [prefs.magnet, api, market, ticker]);
  useEffect(() => { mgr.current?.setLocked(locked); }, [locked, api, market, ticker]);
  useEffect(() => { mgr.current?.setVisible(visible); }, [visible, api, market, ticker]);
  const refreshHist = () => { const m = mgr.current; if (m) setHist({ undo: m.canUndo(), redo: m.canRedo() }); };

  const zoom = (f: number) => {
    const ts = api?.chart.timeScale(); const r = ts?.getVisibleLogicalRange(); if (!ts || !r) return;
    const mid = (r.from + r.to) / 2, half = ((r.to - r.from) / 2) * f;
    ts.setVisibleLogicalRange({ from: mid - half, to: mid + half });
  };
  const goTo = (iso: string) => {
    const ts = api?.chart.timeScale(); if (!ts || !barList.length) return;
    const [y, mo, d] = iso.split("-").map(Number);
    const t = Date.UTC(y, mo - 1, d) / 1000; // bar times are exchange-local clock read as UTC
    let i = barList.findIndex((b) => b.time >= t); if (i < 0) i = barList.length - 1;
    const r = ts.getVisibleLogicalRange(); const w = r ? Math.max(20, r.to - r.from) : 80;
    ts.setVisibleLogicalRange({ from: i - w / 2, to: i + w / 2 });
  };
  const screenshot = () => {
    const c = api?.chart.takeScreenshot(); if (!c) return;
    c.toBlob((b) => {
      if (!b) return;
      const a = document.createElement("a"); a.href = URL.createObjectURL(b);
      a.download = `${(D?.label ?? ticker).replace(/[^\w.-]+/g, "_")}_${intervalLabel(view.interval)}_${new Date().toISOString().slice(0, 10)}.png`;
      a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    }, "image/png");
  };
  const [fs, setFs] = useState(false);
  useEffect(() => { const f = () => setFs(document.fullscreenElement === root.current); document.addEventListener("fullscreenchange", f); return () => document.removeEventListener("fullscreenchange", f); }, []);
  const fullscreen = () => {
    try { if (document.fullscreenElement) void document.exitFullscreen(); else void root.current?.requestFullscreen?.(); } catch { /* not allowed */ }
  };

  const tickerInfo = tickers.find((t) => t.ticker === ticker);
  const label = (fresh ? D?.label : undefined) ?? tickerInfo?.label ?? ticker;
  const bar = barList[hi], prev = hi > 0 ? barList[hi - 1] : undefined;

  return (
    <div ref={root} className={`relative flex flex-col overflow-hidden border border-line/70 bg-surface ${fs ? "h-screen w-screen" : "h-[480px] rounded-2xl sm:h-[600px]"}`}>
      <ChartToolbar
        tickers={tickers.length ? tickers : [{ ticker, label, name: D?.name ?? "" }]} ticker={ticker} onTicker={onTicker}
        interval={view.interval} onInterval={pickInterval} allowed={allowInterval}
        chartType={prefs.chartType} onChartType={(t) => set("chartType", t)}
        onIndicators={() => setDialog({ open: true, focus: null })}
        canUndo={hist.undo} canRedo={hist.redo}
        onUndo={() => { mgr.current?.undo(); refreshHist(); }} onRedo={() => { mgr.current?.redo(); refreshHist(); }}
        onScreenshot={screenshot} onFullscreen={fullscreen} fullscreen={fs}
        scaleMode={prefs.scaleMode} onScaleMode={(m) => set("scaleMode", m)}
        settings={prefs.settings} onSettings={(s) => set("settings", s)}
        toolsOpen={toolsOpen} onToggleTools={() => setToolsOpen((o) => !o)}
      />
      {snapshot && (
        <div className="flex items-center gap-1.5 border-b border-line/70 bg-raised/40 px-3 py-1 text-[11px] text-muted">
          <Lock size={11} /> Saved snapshot: only the 1D · 1m and 1Y · 1D views are available, with the default indicator parameters.
        </div>
      )}
      <div className="relative min-h-0 flex-1">
        <TradingChart
          bars={barList} indicators={D?.indicators ?? []} specs={specs}
          chartType={prefs.chartType} scaleMode={prefs.scaleMode} autoScale={prefs.autoScale} settings={prefs.settings}
          intraday={isIntraday(view.interval)} seconds={view.interval === "5s"} fitKey={fitKey}
          onReady={onReady} onDetach={onDetach} onHover={setHover}
          leftSlot={
            <div className={`${toolsOpen ? "flex" : "hidden"} absolute inset-y-0 left-0 z-20 shrink-0 border-r border-line/70 bg-surface md:static md:flex`}>
              <DrawingToolbar tool={tool} onTool={setTool} magnet={prefs.magnet} onMagnet={(b: boolean) => set("magnet", b)}
                              locked={locked} onLocked={setLocked} visible={visible} onVisible={setVisible}
                              onClear={() => { mgr.current?.clear(); refreshHist(); }} onZoomIn={() => zoom(0.7)} onZoomOut={() => zoom(1.4)} />
            </div>
          }>
          <ChartLegend label={label} name={D?.name} interval={intervalLabel(view.interval)} market={market}
                       bar={fresh ? bar : undefined} prev={fresh ? prev : undefined} specs={specs} indicators={fresh ? D!.indicators : []}
                       onToggle={(uid) => setSpecs(specs.map((s) => (s.uid === uid ? { ...s, visible: !s.visible } : s)))}
                       onSettings={(uid) => setDialog({ open: true, focus: uid })}
                       onRemove={(uid) => setSpecs(specs.filter((s) => s.uid !== uid))} onCopy={copySpec} />
          {(bars.isFetching && !fresh) && (
            <div className="pointer-events-none absolute right-16 top-2 z-10 text-muted"><Loader2 size={16} className="animate-spin" aria-label="loading" /></div>
          )}
          {!barList.length && (
            <div className="absolute inset-0 z-[5] grid place-items-center p-6 text-center text-sm text-muted">
              {bars.isLoading ? "Loading bars…" : bars.isError ? <span>Bars are not available for this view.<br /><span className="font-mono text-[11px]">{String(bars.error)}</span></span> : "No bars in this range yet."}
            </div>
          )}
        </TradingChart>
        {dialog.open && (
          <IndicatorsDialog specs={specs} onChange={setSpecs} onClose={() => setDialog({ open: false, focus: null })}
                            focus={dialog.focus} locked={snapshot} intraday={isIntraday(view.interval)} />
        )}
      </div>
      <BottomBar range={view.range} onRange={pickRange} allowed={allowRange} onGoTo={goTo} tz={D?.tz ?? TZ[market]}
                 scaleMode={prefs.scaleMode} onScaleMode={(m) => set("scaleMode", m)} autoScale={prefs.autoScale} onAutoScale={(b) => set("autoScale", b)}
                 note={D?.note} source={D?.source} live={D?.live} snapshot={snapshot} />
    </div>
  );
}
