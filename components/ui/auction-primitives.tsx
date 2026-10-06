"use client";

import type { ReactNode } from "react";

export function Surface({ className = "", children }: { className?: string; children: ReactNode }) {
  return <section className={`ui-surface ${className}`.trim()}>{children}</section>;
}

export function Eyebrow({ children, accent = true }: { children: ReactNode; accent?: boolean }) {
  return <p className={`ui-eyebrow ${accent ? "with-accent" : ""}`.trim()}>{children}</p>;
}

export function Price({ value, className = "" }: { value: number; className?: string }) {
  const crores = value / 100;
  const label = value >= 100 ? `₹${crores.toFixed(2)} Cr` : `₹${value.toFixed(0)} L`; 
  return <span className={`price ${className}`.trim()}>{label}</span>;
}

export function TeamMark({ code, size = "md" }: { code?: string | null; size?: "sm" | "md" | "lg" }) {
  return <span className={`team-mark team-mark-${size} team-${(code ?? "open").toLowerCase()}`}>{code ?? "—"}</span>;
}

export function Chip({ children, tone = "neutral" }: { children: ReactNode; tone?: "neutral" | "gold" | "green" | "purple" | "red" | "blue" }) {
  return <span className={`ui-chip chip-${tone}`}>{children}</span>;
}

export function StatusBadge({ status }: { status: string }) {
  const tone = status === "SOLD" ? "green" : status === "CURRENT" ? "gold" : status === "UNSOLD" ? "red" : "neutral";
  return <span className={`status-badge status-${tone}`}>{status}</span>;
}

export function SegmentedTabs<T extends string>({ items, value, onChange }: { items: Array<{ value: T; label: string; icon?: ReactNode }>; value: T; onChange: (value: T) => void }) {
  return <div className="segmented-tabs" role="tablist">{items.map(item => <button className={value === item.value ? "active" : ""} key={item.value} role="tab" aria-selected={value === item.value} onClick={() => onChange(item.value)}>{item.icon}{item.label}</button>)}</div>;
}

export function EmptyState({ title, body }: { title: string; body: string }) {
  return <div className="empty-state"><span className="empty-state-mark">✦</span><strong>{title}</strong><p>{body}</p></div>;
}
