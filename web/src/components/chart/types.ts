import type { BarInterval, BarRange } from "../../lib/api";

/** UI-side vocabulary of the chart workspace (docs/design/CHART_WORKSPACE.md §1, §4). */
export type ChartType = "candles" | "hollow" | "bars" | "line" | "area" | "baseline";
export type ScaleMode = "normal" | "log" | "percent";
export type IndicatorType = "vwap" | "sma" | "ema" | "bb" | "rsi" | "volume";

export interface IndicatorSpec {
  uid: string;            // stable UI id (a type may appear twice, e.g. SMA 20 and SMA 50)
  type: IndicatorType;
  n?: number;             // length for sma/ema/bb/rsi
  k?: number;             // band width for bb
  color: string;          // hex
  visible: boolean;
}

export interface ChartSettings { grid: boolean; crosshair: "normal" | "magnet" }

export const INTERVALS: { value: BarInterval; label: string; intraday: boolean }[] = [
  { value: "5s", label: "5s", intraday: true }, { value: "1m", label: "1m", intraday: true },
  { value: "5m", label: "5m", intraday: true }, { value: "15m", label: "15m", intraday: true },
  { value: "30m", label: "30m", intraday: true }, { value: "1h", label: "1h", intraday: true },
  { value: "1d", label: "1D", intraday: false }, { value: "1w", label: "1W", intraday: false },
  { value: "1mo", label: "1M", intraday: false },
];
export const intervalLabel = (i: BarInterval) => INTERVALS.find((x) => x.value === i)?.label ?? i;
export const isIntraday = (i: BarInterval) => INTERVALS.find((x) => x.value === i)?.intraday ?? false;

export const RANGES: { value: BarRange; label: string }[] = [
  { value: "1D", label: "1D" }, { value: "5D", label: "5D" }, { value: "1M", label: "1M" }, { value: "3M", label: "3M" },
  { value: "6M", label: "6M" }, { value: "YTD", label: "YTD" }, { value: "1Y", label: "1Y" }, { value: "5Y", label: "5Y" },
  { value: "ALL", label: "All" },
];
/** Contract §2: default interval when a range is picked. */
export const DEFAULT_INTERVAL: Record<BarRange, BarInterval> = {
  "1D": "1m", "5D": "5m", "1M": "1d", "3M": "1d", "6M": "1d", YTD: "1d", "1Y": "1d", "5Y": "1w", ALL: "1w",
};
/** The two views exported to the static snapshot (contract §3). */
export const SNAPSHOT_VIEWS: { range: BarRange; interval: BarInterval }[] = [{ range: "1D", interval: "1m" }, { range: "1Y", interval: "1d" }];
export const SNAPSHOT_IND = "vwap,sma:20,ema:50,bb:20:2,rsi:14";

export const IND_META: Record<IndicatorType, { name: string; n?: [number, number, number]; k?: [number, number, number]; color: string; desc: string }> = {
  vwap: { name: "VWAP", color: "#f5b342", desc: "Volume-weighted average price, reset each session (intraday only)" },
  sma: { name: "SMA", n: [20, 2, 500], color: "#4cc9f0", desc: "Simple moving average" },
  ema: { name: "EMA", n: [50, 2, 500], color: "#a78bfa", desc: "Exponential moving average" },
  bb: { name: "BB", n: [20, 2, 500], k: [2, 0.5, 5], color: "#60a5fa", desc: "Bollinger bands (basis, upper, lower)" },
  rsi: { name: "RSI", n: [14, 2, 500], color: "#c084fc", desc: "Relative strength index, own pane" },
  volume: { name: "Vol", color: "#8c99b2", desc: "Volume histogram, coloured by bar direction" },
};

/** Contract `ind` token for one indicator; volume is drawn from the bars and needs none. */
export const specToken = (s: IndicatorSpec): string | null =>
  s.type === "volume" ? null : s.type === "vwap" ? "vwap" : s.type === "bb" ? `bb:${s.n}:${s.k}` : `${s.type}:${s.n}`;
export const specTitle = (s: IndicatorSpec) =>
  s.type === "volume" || s.type === "vwap" ? IND_META[s.type].name : s.type === "bb" ? `BB ${s.n} ${s.k}` : `${IND_META[s.type].name} ${s.n}`;

export const newSpec = (type: IndicatorType, over: Partial<IndicatorSpec> = {}): IndicatorSpec => ({
  uid: `${type}-${Math.random().toString(36).slice(2, 8)}`, type, visible: true, color: IND_META[type].color,
  ...(IND_META[type].n ? { n: IND_META[type].n![0] } : {}), ...(IND_META[type].k ? { k: IND_META[type].k![0] } : {}), ...over,
});
export const DEFAULT_INDICATORS = (): IndicatorSpec[] => [
  newSpec("volume"), newSpec("vwap"), newSpec("sma", { n: 20 }), newSpec("ema", { n: 50 }),
];

/** localStorage helpers: per-viewer convenience only, so every access may fail silently. */
export function loadPref<T>(key: string, fallback: T): T {
  try { const s = localStorage.getItem(key); return s ? (JSON.parse(s) as T) : fallback; } catch { return fallback; }
}
export function savePref(key: string, v: unknown) {
  try { localStorage.setItem(key, JSON.stringify(v)); } catch { /* storage unavailable */ }
}

export const CHART_TYPES: { value: ChartType; label: string }[] = [
  { value: "candles", label: "Candles" }, { value: "hollow", label: "Hollow candles" }, { value: "bars", label: "Bars" },
  { value: "line", label: "Line" }, { value: "area", label: "Area" }, { value: "baseline", label: "Baseline" },
];
