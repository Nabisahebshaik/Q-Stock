import { ReactNode, useEffect, useRef, useState } from "react";

export const TV_BTN = "inline-flex h-8 min-w-8 shrink-0 items-center justify-center gap-1 rounded-md px-1.5 text-[13px] text-muted transition hover:bg-raised hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/60 disabled:cursor-not-allowed disabled:opacity-40";
export const TV_PANEL = "min-w-44 rounded-lg border border-line bg-surface p-1 shadow-xl shadow-black/30";

/** Toolbar icon button with a tooltip (title) and an accessible name. */
export function IconBtn({ label, onClick, active, disabled, children, className = "" }: {
  label: string; onClick?: () => void; active?: boolean; disabled?: boolean; children: ReactNode; className?: string;
}) {
  return (
    <button type="button" title={label} aria-label={label} aria-pressed={active} onClick={onClick} disabled={disabled}
            className={`${TV_BTN} ${active ? "text-accent" : ""} ${className}`}>{children}</button>
  );
}

/** Button that opens a floating panel; closes on outside click or Escape. */
export function Popover({ button, label, children, align = "left", panelClass = "", title, btnClass }: {
  button: ReactNode; label: string; btnClass?: string; children: (close: () => void) => ReactNode; align?: "left" | "right"; panelClass?: string; title?: string;
}) {
  const [open, setOpen] = useState(false);
  const [pos, setPos] = useState<{ top: number; left?: number; right?: number }>({ top: 0 });
  const ref = useRef<HTMLDivElement>(null);
  // Fixed positioning: the toolbar scrolls horizontally on phones, which would clip an absolute panel.
  const toggle = () => {
    const r = ref.current?.getBoundingClientRect();
    if (r) setPos(align === "right" || r.left > window.innerWidth - 240 ? { top: r.bottom + 4, right: Math.max(4, window.innerWidth - r.right) } : { top: r.bottom + 4, left: Math.max(4, r.left) });
    setOpen((o) => !o);
  };
  useEffect(() => {
    if (!open) return;
    const away = () => setOpen(false);
    window.addEventListener("resize", away);
    const down = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false); };
    const key = (e: KeyboardEvent) => { if (e.key === "Escape") setOpen(false); };
    document.addEventListener("mousedown", down); document.addEventListener("keydown", key);
    return () => { document.removeEventListener("mousedown", down); document.removeEventListener("keydown", key); window.removeEventListener("resize", away); };
  }, [open]);
  return (
    <div ref={ref} className="relative">
      <button type="button" title={title ?? label} aria-label={label} aria-haspopup="menu" aria-expanded={open}
              onClick={toggle} className={`${btnClass ?? TV_BTN} ${open ? "bg-raised text-ink" : ""}`}>{button}</button>
      {open && (
        <div role="menu" style={{ position: "fixed", ...pos }} className={`${TV_PANEL} z-[60] max-h-[70vh] overflow-y-auto ${panelClass}`}>
          {children(() => setOpen(false))}
        </div>
      )}
    </div>
  );
}

export function MenuItem({ children, onClick, active, disabled, hint }: { children: ReactNode; onClick?: () => void; active?: boolean; disabled?: boolean; hint?: ReactNode }) {
  return (
    <button type="button" role="menuitem" disabled={disabled} onClick={onClick}
            className={`flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-left text-[13px] transition hover:bg-raised disabled:cursor-not-allowed disabled:opacity-40 ${active ? "text-accent" : "text-ink"}`}>
      {children}{hint != null && <span className="ml-auto pl-3 text-[11px] text-muted">{hint}</span>}
    </button>
  );
}
export const MenuSep = () => <div className="my-1 border-t border-line/70" />;
export const MenuHead = ({ children }: { children: ReactNode }) => <div className="px-2.5 pb-1 pt-1.5 text-[10px] font-medium uppercase tracking-wider text-muted">{children}</div>;
