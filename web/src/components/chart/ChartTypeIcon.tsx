import type { ReactNode } from "react";
import { ChartArea, ChartCandlestick, ChartLine } from "lucide-react";
import type { ChartType } from "./types";

const Svg = ({ size, children }: { size: number; children: ReactNode }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.75} strokeLinecap="round" strokeLinejoin="round" aria-hidden>{children}</svg>
);

/** Icon per chart type; lucide has no hollow-candle, OHLC-bar or baseline glyphs, so those are drawn here. */
export default function ChartTypeIcon({ type, size = 18 }: { type: ChartType; size?: number }) {
  switch (type) {
    case "hollow":
      return <Svg size={size}><path d="M7 3v3M7 16v5M17 3v2M17 13v8" /><rect x="4.5" y="6" width="5" height="10" rx="0.5" /><rect x="14.5" y="5" width="5" height="8" rx="0.5" fill="currentColor" /></Svg>;
    case "bars":
      return <Svg size={size}><path d="M7 4v16M4 8h3M7 15h3M17 3v15M14 6h3M17 13h3" /></Svg>;
    case "baseline":
      return <Svg size={size}><path d="M3 12h18" strokeDasharray="2 2.5" /><path d="M3 16l4-6 4 3 4-8 6 9" /></Svg>;
    case "line": return <ChartLine size={size} aria-hidden />;
    case "area": return <ChartArea size={size} aria-hidden />;
    default: return <ChartCandlestick size={size} aria-hidden />;
  }
}
