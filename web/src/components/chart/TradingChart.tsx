import { ReactNode, useEffect, useMemo, useRef } from "react";
import {
  createChart, CrosshairMode, IChartApi, IPriceLine, ISeriesApi, LineStyle, PriceScaleMode, SeriesType, Time, UTCTimestamp,
} from "lightweight-charts";
import type { Bar, IndicatorOut } from "../../lib/api";
import { cssColor, useThemeTick } from "../../lib/util";
import type { ChartSettings, ChartType, IndicatorSpec, ScaleMode } from "./types";
import { matchIndicator } from "./indicators";

export interface TradingChartProps {
  bars: Bar[];
  indicators: IndicatorOut[];
  specs: IndicatorSpec[];
  chartType: ChartType;
  scaleMode: ScaleMode;
  autoScale: boolean;
  settings: ChartSettings;
  intraday: boolean;
  seconds: boolean;
  /** Content fits when this key changes (symbol / interval / range), not on every refetch. */
  fitKey: string;
  /** Called whenever the chart or its main series is (re)created; the drawing manager attaches here. */
  onReady?: (chart: IChartApi, series: ISeriesApi<SeriesType>) => void;
  /** Called just before the main series or the chart is removed, so attachments can detach first. */
  onDetach?: () => void;
  /** Bar time under the crosshair, or null when the pointer leaves. */
  onHover?: (time: number | null) => void;
  /** Left column, e.g. the drawing toolbar. */
  leftSlot?: ReactNode;
  /** Overlay on the chart's top-left corner (legend). */
  children?: ReactNode;
}

const ts = (t: number) => t as UTCTimestamp;

/** Price band layout (lightweight-charts 4 has no panes): main, optional RSI band, optional volume band. */
function margins(vol: boolean, rsi: boolean) {
  if (vol && rsi) return { main: { top: 0.06, bottom: 0.38 }, rsi: { top: 0.65, bottom: 0.19 }, vol: { top: 0.85, bottom: 0 } };
  if (rsi) return { main: { top: 0.06, bottom: 0.3 }, rsi: { top: 0.75, bottom: 0.02 }, vol: { top: 0.85, bottom: 0 } };
  if (vol) return { main: { top: 0.06, bottom: 0.22 }, rsi: { top: 0.75, bottom: 0.02 }, vol: { top: 0.8, bottom: 0 } };
  return { main: { top: 0.06, bottom: 0.06 }, rsi: { top: 0.75, bottom: 0.02 }, vol: { top: 0.85, bottom: 0 } };
}

function addMain(ch: IChartApi, type: ChartType, bars: Bar[]): ISeriesApi<SeriesType> {
  const up = cssColor("up"), down = cssColor("down"), accent = cssColor("accent");
  switch (type) {
    case "hollow":
      return ch.addCandlestickSeries({ upColor: "rgba(0, 0, 0, 0)", downColor: down, borderUpColor: up, borderDownColor: down, wickUpColor: up, wickDownColor: down });
    case "bars":
      return ch.addBarSeries({ upColor: up, downColor: down, thinBars: false });
    case "line":
      return ch.addLineSeries({ color: accent, lineWidth: 2 });
    case "area":
      return ch.addAreaSeries({ lineColor: accent, topColor: cssColor("accent", 0.35), bottomColor: cssColor("accent", 0.02), lineWidth: 2 });
    case "baseline":
      return ch.addBaselineSeries({
        baseValue: { type: "price", price: bars[0]?.close ?? 0 },
        topLineColor: up, topFillColor1: cssColor("up", 0.28), topFillColor2: cssColor("up", 0.04),
        bottomLineColor: down, bottomFillColor1: cssColor("down", 0.04), bottomFillColor2: cssColor("down", 0.28), lineWidth: 2,
      });
    default:
      return ch.addCandlestickSeries({ upColor: up, downColor: down, borderUpColor: up, borderDownColor: down, wickUpColor: up, wickDownColor: down });
  }
}
const ohlcType = (t: ChartType) => t === "candles" || t === "hollow" || t === "bars";

/** Sorted, strictly increasing times (the chart library rejects duplicates). */
function clean(bars: Bar[]): Bar[] {
  const out: Bar[] = [];
  for (const b of [...bars].sort((a, b) => a.time - b.time)) {
    if (out.length && out[out.length - 1].time === b.time) out[out.length - 1] = b; else out.push(b);
  }
  return out;
}

export default function TradingChart(p: TradingChartProps) {
  const { chartType, scaleMode, autoScale, settings, intraday, seconds, fitKey, specs, indicators } = p;
  const el = useRef<HTMLDivElement>(null);
  const chart = useRef<IChartApi>();
  const main = useRef<ISeriesApi<SeriesType>>();
  const vol = useRef<ISeriesApi<"Histogram">>();
  const overlays = useRef(new Map<string, ISeriesApi<"Line">>());
  const rsiLines = useRef<{ series: ISeriesApi<"Line">; lines: IPriceLine[] } | null>(null);
  const fitted = useRef("");
  const themeTick = useThemeTick();
  const bars = useMemo(() => clean(p.bars), [p.bars]);
  const barsRef = useRef(bars); barsRef.current = bars;
  const cb = useRef({ onReady: p.onReady, onHover: p.onHover, onDetach: p.onDetach }); cb.current = { onReady: p.onReady, onHover: p.onHover, onDetach: p.onDetach };
  const index = useMemo(() => new Map(bars.map((b, i) => [b.time, i])), [bars]);
  const indexRef = useRef(index); indexRef.current = index;

  // Chart: created once per mount.
  useEffect(() => {
    if (!el.current) return;
    const ch = createChart(el.current, {
      autoSize: true,
      layout: { background: { color: cssColor("surface") }, textColor: cssColor("muted"), fontFamily: "Inter, system-ui, sans-serif", fontSize: 11 },
      rightPriceScale: { borderColor: cssColor("line", 0.8) },
      timeScale: { borderColor: cssColor("line", 0.8), rightOffset: 6 },
      crosshair: { mode: CrosshairMode.Normal },
    });
    const v = ch.addHistogramSeries({ priceScaleId: "vol", priceFormat: { type: "volume" }, priceLineVisible: false, lastValueVisible: false });
    ch.subscribeCrosshairMove((param) => {
      const t = param.time as number | undefined;
      cb.current.onHover?.(t != null && indexRef.current.has(t) ? t : null);
    });
    chart.current = ch; vol.current = v;
    const ov = overlays.current;
    return () => {
      cb.current.onDetach?.();
      ch.remove(); chart.current = undefined; main.current = undefined; vol.current = undefined;
      ov.clear(); rsiLines.current = null; fitted.current = "";
    };
  }, []);

  // Theme, grid, crosshair.
  useEffect(() => {
    const ch = chart.current; if (!ch) return;
    const g = settings.grid ? cssColor("line", 0.35) : "rgba(0, 0, 0, 0)";
    ch.applyOptions({
      layout: { background: { color: cssColor("surface") }, textColor: cssColor("muted") },
      grid: { vertLines: { color: g }, horzLines: { color: g } },
      rightPriceScale: { borderColor: cssColor("line", 0.8) },
      timeScale: { borderColor: cssColor("line", 0.8) },
      crosshair: {
        mode: settings.crosshair === "magnet" ? CrosshairMode.Magnet : CrosshairMode.Normal,
        vertLine: { labelBackgroundColor: cssColor("raised") }, horzLine: { labelBackgroundColor: cssColor("raised") },
      },
    });
  }, [themeTick, settings.grid, settings.crosshair]);

  useEffect(() => {
    chart.current?.applyOptions({ timeScale: { timeVisible: intraday, secondsVisible: seconds } });
  }, [intraday, seconds]);

  // Main series per chart type (and theme, since its colours are set at creation).
  useEffect(() => {
    const ch = chart.current; if (!ch) return;
    if (main.current) { cb.current.onDetach?.(); ch.removeSeries(main.current); main.current = undefined; }
    const s = addMain(ch, chartType, barsRef.current);
    main.current = s;
    const b = barsRef.current;
    s.setData(ohlcType(chartType) ? b.map((x) => ({ time: ts(x.time), open: x.open, high: x.high, low: x.low, close: x.close }))
                                  : b.map((x) => ({ time: ts(x.time), value: x.close })));
    cb.current.onReady?.(ch, s);
  }, [chartType, themeTick]);

  // Bars -> main + volume.
  useEffect(() => {
    const s = main.current, v = vol.current; if (!s || !v) return;
    s.setData(ohlcType(chartType) ? bars.map((x) => ({ time: ts(x.time), open: x.open, high: x.high, low: x.low, close: x.close }))
                                  : bars.map((x) => ({ time: ts(x.time), value: x.close })));
    if (chartType === "baseline" && bars.length) s.applyOptions({ baseValue: { type: "price", price: bars[0].close } });
    const up = cssColor("up", 0.5), down = cssColor("down", 0.5);
    v.setData(bars.map((x) => ({ time: ts(x.time), value: x.volume, color: x.close >= x.open ? up : down })));
    if (bars.length && fitted.current !== fitKey) { fitted.current = fitKey; chart.current?.timeScale().fitContent(); }
  }, [bars, chartType, themeTick, fitKey]);

  // Overlays (price pane) and RSI band; reconciled against the visible specs.
  useEffect(() => {
    const ch = chart.current; if (!ch) return;
    const want = new Set<string>();
    let hasRsi = false;
    for (const spec of specs) {
      if (spec.type === "volume" || !spec.visible) continue;
      const out = matchIndicator(spec, indicators); if (!out) continue;
      const isRsi = spec.type === "rsi";
      out.lines.forEach((ln, li) => {
        const key = `${spec.uid}:${li}`; want.add(key);
        let s = overlays.current.get(key);
        if (!s) {
          s = ch.addLineSeries({ priceLineVisible: false, lastValueVisible: isRsi, crosshairMarkerVisible: false, ...(isRsi ? { priceScaleId: "rsi" } : {}) });
          overlays.current.set(key, s);
        }
        const band = spec.type === "bb" && li > 0;
        s.applyOptions({ color: band ? spec.color + "b3" : spec.color, lineWidth: band ? 1 : isRsi ? 1 : 2, title: "" });
        s.setData(ln.values.map((x) => ({ time: ts(x.time) as Time, value: x.value })));
        if (isRsi && !hasRsi) {
          hasRsi = true;
          if (rsiLines.current?.series !== s) {
            const mk = (price: number) => s!.createPriceLine({ price, color: cssColor("muted", 0.6), lineWidth: 1, lineStyle: LineStyle.Dashed, axisLabelVisible: false, title: "" });
            rsiLines.current = { series: s, lines: [mk(70), mk(30)] };
          }
        }
      });
    }
    for (const [key, s] of overlays.current) {
      if (!want.has(key)) {
        if (rsiLines.current?.series === s) rsiLines.current = null;
        ch.removeSeries(s); overlays.current.delete(key);
      }
    }
    const volOn = specs.some((x) => x.type === "volume" && x.visible);
    const m = margins(volOn, hasRsi);
    vol.current?.applyOptions({ visible: volOn });
    ch.priceScale("vol").applyOptions({ scaleMargins: m.vol });
    ch.priceScale("right").applyOptions({ scaleMargins: m.main });
    if (hasRsi) ch.priceScale("rsi").applyOptions({ scaleMargins: m.rsi });
  }, [specs, indicators, themeTick]);

  // Scale mode / auto-scale.
  useEffect(() => {
    const mode = scaleMode === "log" ? PriceScaleMode.Logarithmic : scaleMode === "percent" ? PriceScaleMode.Percentage : PriceScaleMode.Normal;
    chart.current?.priceScale("right").applyOptions({ mode, autoScale });
  }, [scaleMode, autoScale]);

  return (
    <div className="flex h-full min-h-0 w-full">
      {p.leftSlot}
      <div className="relative h-full min-h-0 min-w-0 flex-1">
        <div ref={el} className="absolute inset-0" />
        {p.children}
      </div>
    </div>
  );
}
