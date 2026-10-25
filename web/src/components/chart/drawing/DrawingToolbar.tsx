import { Fragment, KeyboardEvent, ReactNode, useRef } from "react";
import {
  ArrowRightFromLine, Crosshair, Eye, EyeOff, Lock, LockOpen, Magnet, Minus, MousePointer2, MoveUpRight,
  Redo2, Ruler, Rows3, SeparatorVertical, Square, Trash2, TrendingUp, Type, Undo2, ZoomIn, ZoomOut,
} from "lucide-react";
import type { DrawingTool } from "./types";

type IconT = typeof Crosshair;

const TOOLS: { tool: DrawingTool; label: string; Icon: IconT; group: number }[] = [
  { tool: "cursor", label: "Cursor", Icon: MousePointer2, group: 0 },
  { tool: "crosshair", label: "Crosshair", Icon: Crosshair, group: 0 },
  { tool: "trend", label: "Trend line", Icon: TrendingUp, group: 1 },
  { tool: "ray", label: "Ray", Icon: MoveUpRight, group: 1 },
  { tool: "hline", label: "Horizontal line", Icon: Minus, group: 1 },
  { tool: "hray", label: "Horizontal ray", Icon: ArrowRightFromLine, group: 1 },
  { tool: "vline", label: "Vertical line", Icon: SeparatorVertical, group: 1 },
  { tool: "rect", label: "Rectangle", Icon: Square, group: 2 },
  { tool: "fib", label: "Fibonacci retracement", Icon: Rows3, group: 2 },
  { tool: "measure", label: "Price range (measure)", Icon: Ruler, group: 2 },
  { tool: "text", label: "Text", Icon: Type, group: 2 },
];

export interface DrawingToolbarProps {
  tool: DrawingTool;
  onTool: (t: DrawingTool) => void;
  magnet: boolean;
  onMagnet: (b: boolean) => void;
  locked: boolean;
  onLocked: (b: boolean) => void;
  visible: boolean;
  onVisible: (b: boolean) => void;
  onClear: () => void;
  onZoomIn: () => void;
  onZoomOut: () => void;
  /** Default true (TradingView-style left bar); false lays the buttons out in a row. */
  vertical?: boolean;
  /** Optional undo / redo buttons (shown when the handlers are given). */
  onUndo?: () => void;
  onRedo?: () => void;
  canUndo?: boolean;
  canRedo?: boolean;
  className?: string;
}

function Btn({ label, onClick, active, pressed, disabled, danger, children }: {
  label: string; onClick: () => void; active?: boolean; pressed?: boolean; disabled?: boolean; danger?: boolean; children: ReactNode;
}) {
  const on = active || pressed;
  return (
    <button type="button" title={label} aria-label={label} onClick={onClick} disabled={disabled}
            aria-pressed={pressed ?? active}
            data-dt-btn=""
            className={`grid h-9 w-9 shrink-0 place-items-center rounded-lg transition
              focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/60
              disabled:cursor-not-allowed disabled:opacity-35
              ${on ? "bg-accent/15 text-accent" : danger ? "text-muted hover:bg-down/10 hover:text-down" : "text-muted hover:bg-raised hover:text-ink"}`}>
      {children}
    </button>
  );
}

/** TradingView-style drawing toolbar. Arrow keys move focus between buttons (roving within the toolbar). */
export function DrawingToolbar(p: DrawingToolbarProps) {
  const vertical = p.vertical ?? true;
  const ref = useRef<HTMLDivElement>(null);

  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    const keys = vertical ? ["ArrowUp", "ArrowDown"] : ["ArrowLeft", "ArrowRight"];
    if (![...keys, "Home", "End"].includes(e.key) || !ref.current) return;
    const btns = Array.from(ref.current.querySelectorAll<HTMLButtonElement>("button[data-dt-btn]:not(:disabled)"));
    const i = btns.indexOf(document.activeElement as HTMLButtonElement);
    if (i < 0 && e.key !== "Home" && e.key !== "End") return;
    e.preventDefault();
    const n = btns.length;
    const j = e.key === "Home" ? 0 : e.key === "End" ? n - 1 : (i + (e.key === keys[1] ? 1 : -1) + n) % n;
    btns[j]?.focus();
  };

  const sep = <div aria-hidden className={vertical ? "my-1 h-px w-6 shrink-0 bg-line" : "mx-1 h-6 w-px shrink-0 bg-line"} />;
  const sz = 18;

  return (
    <div ref={ref} role="toolbar" aria-label="Drawing tools" aria-orientation={vertical ? "vertical" : "horizontal"}
         onKeyDown={onKeyDown}
         className={`flex items-center gap-0.5 ${vertical ? "flex-col overflow-y-auto px-1 py-1.5" : "flex-row overflow-x-auto px-1.5 py-1"} ${p.className ?? ""}`}>
      {TOOLS.map(({ tool, label, Icon, group }, k) => (
        <Fragment key={tool}>
          {k > 0 && TOOLS[k - 1].group !== group && sep}
          <Btn label={!p.visible && group > 0 ? `${label} (drawings hidden)` : label} active={p.tool === tool}
               disabled={!p.visible && group > 0} onClick={() => p.onTool(tool)}>
            <Icon size={sz} strokeWidth={1.75} aria-hidden />
          </Btn>
        </Fragment>
      ))}
      {sep}
      <Btn label={p.magnet ? "Magnet mode: on" : "Magnet mode: snap to OHLC"} pressed={p.magnet} onClick={() => p.onMagnet(!p.magnet)}>
        <Magnet size={sz} strokeWidth={1.75} aria-hidden />
      </Btn>
      <Btn label={p.locked ? "Unlock drawings" : "Lock all drawings"} pressed={p.locked} onClick={() => p.onLocked(!p.locked)}>
        {p.locked ? <Lock size={sz} strokeWidth={1.75} aria-hidden /> : <LockOpen size={sz} strokeWidth={1.75} aria-hidden />}
      </Btn>
      <Btn label={p.visible ? "Hide all drawings" : "Show all drawings"} pressed={!p.visible} onClick={() => p.onVisible(!p.visible)}>
        {p.visible ? <Eye size={sz} strokeWidth={1.75} aria-hidden /> : <EyeOff size={sz} strokeWidth={1.75} aria-hidden />}
      </Btn>
      {p.onUndo && (
        <Btn label="Undo (Ctrl+Z)" disabled={p.canUndo === false} onClick={p.onUndo}><Undo2 size={sz} strokeWidth={1.75} aria-hidden /></Btn>
      )}
      {p.onRedo && (
        <Btn label="Redo (Ctrl+Y)" disabled={p.canRedo === false} onClick={p.onRedo}><Redo2 size={sz} strokeWidth={1.75} aria-hidden /></Btn>
      )}
      <Btn label="Remove all drawings" danger onClick={p.onClear}>
        <Trash2 size={sz} strokeWidth={1.75} aria-hidden />
      </Btn>
      {sep}
      <Btn label="Zoom in" onClick={p.onZoomIn}><ZoomIn size={sz} strokeWidth={1.75} aria-hidden /></Btn>
      <Btn label="Zoom out" onClick={p.onZoomOut}><ZoomOut size={sz} strokeWidth={1.75} aria-hidden /></Btn>
    </div>
  );
}
