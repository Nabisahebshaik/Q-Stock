import { useEffect, useRef } from "react";
import { createChart, IChartApi, ISeriesApi, UTCTimestamp, CrosshairMode } from "lightweight-charts";
import type { Candle } from "../lib/api";
import { cssColor, useThemeTick } from "../lib/util";

/** Candles + VWAP + volume. Times arrive already shifted to the exchange's local clock. */
export default function CandleChart({ candles, height = 420 }: { candles: Candle[]; height?: number }) {
  const el = useRef<HTMLDivElement>(null);
  const chart = useRef<IChartApi>();
  const s = useRef<{ c: ISeriesApi<"Candlestick">; v: ISeriesApi<"Histogram">; w: ISeriesApi<"Line"> }>();
  const themeTick = useThemeTick();

  useEffect(() => {
    if (!el.current) return;
    const up = cssColor("up"), down = cssColor("down");
    const ch = createChart(el.current, {
      height, autoSize: true,
      layout: { background: { color: "transparent" }, textColor: cssColor("muted"), fontFamily: "Inter, system-ui, sans-serif" },
      grid: { vertLines: { color: cssColor("line", 0.35) }, horzLines: { color: cssColor("line", 0.35) } },
      rightPriceScale: { borderColor: cssColor("line", 0.8) },
      timeScale: { borderColor: cssColor("line", 0.8), timeVisible: true, secondsVisible: false },
      crosshair: { mode: CrosshairMode.Normal },
    });
    const c = ch.addCandlestickSeries({ upColor: up, downColor: down, borderUpColor: up, borderDownColor: down, wickUpColor: up, wickDownColor: down });
    const w = ch.addLineSeries({ color: cssColor("accent"), lineWidth: 2, priceLineVisible: false, lastValueVisible: false, title: "VWAP" });
    const v = ch.addHistogramSeries({ priceScaleId: "vol", priceFormat: { type: "volume" }, priceLineVisible: false, lastValueVisible: false });
    ch.priceScale("vol").applyOptions({ scaleMargins: { top: 0.8, bottom: 0 } });
    c.priceScale().applyOptions({ scaleMargins: { top: 0.06, bottom: 0.25 } });
    chart.current = ch; s.current = { c, v, w };
    return () => { ch.remove(); chart.current = undefined; };
  }, [height, themeTick]);

  useEffect(() => {
    if (!s.current) return;
    const up = cssColor("up", 0.55), down = cssColor("down", 0.55);
    const t = (x: Candle) => x.time as UTCTimestamp;
    s.current.c.setData(candles.map((x) => ({ time: t(x), open: x.open, high: x.high, low: x.low, close: x.close })));
    s.current.v.setData(candles.map((x) => ({ time: t(x), value: x.volume, color: x.close >= x.open ? up : down })));
    s.current.w.setData(candles.filter((x) => x.vwap != null).map((x) => ({ time: t(x), value: x.vwap as number })));
    chart.current?.timeScale().fitContent();
  }, [candles, themeTick]);

  return <div ref={el} style={{ height }} className="w-full" />;
}
