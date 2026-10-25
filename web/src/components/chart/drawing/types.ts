/** Drawing tools: shared types. Anchors live in data space (bar time in the chart's
 *  UTCTimestamp seconds, price) so drawings survive zoom, scroll, interval changes and reloads. */

export type DrawingTool =
  | "cursor" | "crosshair"
  | "trend" | "ray" | "hline" | "hray" | "vline" | "rect" | "fib" | "measure" | "text";

/** Tools that create a drawing (everything except the two pointer modes). */
export type ShapeType = Exclude<DrawingTool, "cursor" | "crosshair">;

export interface Anchor { time: number; price: number }

export interface Drawing {
  id: string;
  type: ShapeType;
  /** First anchor (the only one for hline / hray / vline / text). */
  a: Anchor;
  /** Second anchor for two-point tools. */
  b?: Anchor;
  text?: string;
}

export interface DrawingManager {
  setTool(t: DrawingTool): void;
  getTool(): DrawingTool;
  setMagnet(b: boolean): void;
  setLocked(b: boolean): void;
  setVisible(b: boolean): void;
  clear(): void;
  undo(): void;
  redo(): void;
  canUndo(): boolean;
  canRedo(): boolean;
  destroy(): void;
}

export const TWO_POINT: ReadonlySet<ShapeType> = new Set<ShapeType>(["trend", "ray", "rect", "fib", "measure"]);

export const FIB_LEVELS = [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1] as const;
