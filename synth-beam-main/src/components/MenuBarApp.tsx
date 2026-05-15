import { useEffect, useMemo, useState } from "react";
import {
  Cpu,
  MonitorCog,
  MemoryStick,
  HardDrive,
  Wifi,
  BatteryMedium,
  Activity,
  Settings,
  ArrowUp,
  ArrowDown,
} from "lucide-react";

function Sparkline({
  data,
  color,
  className = "",
}: {
  data: number[];
  color: string;
  className?: string;
}) {
  const w = 120;
  const h = 28;
  const max = Math.max(...data, 1);
  const min = Math.min(...data, 0);
  const range = max - min || 1;
  const step = w / (data.length - 1);
  const points = data
    .map((v, i) => `${i * step},${h - ((v - min) / range) * h}`)
    .join(" ");
  const area = `M0,${h} L${points} L${w},${h} Z`;

  return (
    <svg
      viewBox={`0 0 ${w} ${h}`}
      className={className}
      preserveAspectRatio="none"
    >
      <defs>
        <linearGradient id={`g-${color}`} x1="0" x2="0" y1="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity="0.45" />
          <stop offset="100%" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={area} fill={`url(#g-${color})`} />
      <polyline
        points={points}
        fill="none"
        stroke={color}
        strokeWidth="1.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function MetricRow({
  icon: Icon,
  label,
  value,
  tint,
  children,
  sparkline,
}: {
  icon: React.ElementType;
  label: string;
  value: string;
  tint: string;
  children?: React.ReactNode;
  sparkline?: number[];
}) {
  return (
    <div className="glass-row rounded-xl px-3 py-2.5 flex items-center gap-3 transition-all hover:scale-[1.01] hover:brightness-105">
      <div
        className="shrink-0 w-9 h-9 rounded-lg flex items-center justify-center"
        style={{
          background: `color-mix(in oklab, ${tint} 18%, transparent)`,
          boxShadow: `inset 0 0 0 1px color-mix(in oklab, ${tint} 30%, transparent)`,
        }}
      >
        <Icon className="w-4 h-4" style={{ color: tint }} strokeWidth={2.2} />
      </div>

      <div className="flex-1 min-w-0">
        <div className="flex items-baseline justify-between gap-2">
          <div className="flex items-baseline gap-2">
            <span className="text-[11px] uppercase tracking-[0.12em] text-muted-foreground font-medium">
              {label}
            </span>
            <span className="font-mono text-[15px] font-semibold tabular-nums text-foreground">
              {value}
            </span>
          </div>
          {sparkline && (
            <Sparkline
              data={sparkline}
              color={tint}
              className="w-[88px] h-5 opacity-90"
            />
          )}
        </div>
        {children && <div className="mt-1">{children}</div>}
      </div>
    </div>
  );
}

function StatChip({ label, value }: { label: string; value: string }) {
  return (
    <span className="inline-flex items-baseline gap-1 text-[11px] text-muted-foreground">
      <span className="opacity-70">{label}</span>
      <span className="font-mono tabular-nums text-foreground/80">{value}</span>
    </span>
  );
}

function useTicker(initial: number[], next: () => number) {
  const [data, setData] = useState(initial);
  useEffect(() => {
    const id = setInterval(() => {
      setData((d) => [...d.slice(1), next()]);
    }, 1200);
    return () => clearInterval(id);
  }, [next]);
  return data;
}

export default function MenuBarApp() {
  const cpu = useTicker(
    [22, 25, 30, 28, 26, 31, 27, 29, 33, 28],
    useMemo(() => () => 22 + Math.round(Math.random() * 14), []),
  );
  const gpu = useTicker(
    [65, 70, 68, 72, 75, 71, 69, 73, 70, 71],
    useMemo(() => () => 60 + Math.round(Math.random() * 18), []),
  );

  return (
    <div
      className="min-h-screen w-full flex flex-col items-center justify-start pt-10 px-4"
      style={{ background: "var(--gradient-wallpaper)" }}
    >
      {/* Dropdown panel */}
      <div className="w-full max-w-md glass-panel rounded-3xl p-3 space-y-2">
        {/* Header */}
        <div className="flex items-center justify-between px-1.5 pt-0.5 pb-1">
          <div className="flex items-center gap-2">
            <span className="live-dot w-1.5 h-1.5 rounded-full bg-emerald-500" />
            <span className="text-[11px] uppercase tracking-[0.18em] text-muted-foreground font-semibold">
              System · Live
            </span>
          </div>
          <span className="text-[11px] font-mono text-muted-foreground tabular-nums">
            5.15 · Fri
          </span>
        </div>

        <MetricRow
          icon={Cpu}
          label="CPU"
          value="28%"
          tint="var(--cpu)"
          sparkline={cpu}
        >
          <div className="flex gap-3">
            <StatChip label="Sys" value="9%" />
            <StatChip label="User" value="18%" />
            <StatChip label="Idle" value="72%" />
          </div>
        </MetricRow>

        <MetricRow
          icon={MonitorCog}
          label="GPU"
          value="71%"
          tint="var(--gpu)"
          sparkline={gpu}
        >
          <div className="flex gap-3">
            <StatChip label="VRAM" value="1.56 GB" />
          </div>
        </MetricRow>

        <MetricRow icon={MemoryStick} label="Memory" value="85%" tint="var(--mem)">
          <div className="flex items-center gap-3">
            <div className="flex-1 h-1 rounded-full bg-foreground/8 overflow-hidden">
              <div
                className="h-full rounded-full"
                style={{
                  width: "85%",
                  background: `linear-gradient(90deg, var(--mem), color-mix(in oklab, var(--mem) 70%, white))`,
                }}
              />
            </div>
            <StatChip label="Pressure" value="0%" />
            <StatChip label="Swap" value="3.4G" />
          </div>
        </MetricRow>

        <MetricRow icon={HardDrive} label="Storage" value="27%" tint="var(--disk)">
          <div className="flex items-center gap-3">
            <div className="flex-1 h-1 rounded-full bg-foreground/8 overflow-hidden">
              <div
                className="h-full rounded-full"
                style={{
                  width: "27%",
                  background: `linear-gradient(90deg, var(--disk), color-mix(in oklab, var(--disk) 70%, white))`,
                }}
              />
            </div>
            <StatChip label="" value="273.5 / 994.7 GB" />
          </div>
        </MetricRow>

        <MetricRow icon={Wifi} label="Network" value="Wi-Fi" tint="var(--net)">
          <div className="flex gap-4">
            <span className="inline-flex items-center gap-1 text-[11px] font-mono tabular-nums text-foreground/80">
              <ArrowUp className="w-3 h-3" style={{ color: "var(--net)" }} />
              243 KB/s
            </span>
            <span className="inline-flex items-center gap-1 text-[11px] font-mono tabular-nums text-foreground/80">
              <ArrowDown className="w-3 h-3" style={{ color: "var(--net)" }} />
              444 KB/s
            </span>
          </div>
        </MetricRow>

        <MetricRow icon={BatteryMedium} label="Battery" value="77%" tint="var(--batt)">
          <div className="flex gap-3">
            <StatChip label="" value="On battery" />
            <StatChip label="Adapter" value="—" />
            <StatChip label="Power" value="9.9 W" />
          </div>
        </MetricRow>

        {/* Footer actions */}
        <div className="grid grid-cols-2 gap-2 pt-1">
          <button className="glass-row rounded-xl py-2.5 flex items-center justify-center gap-2 text-[12px] font-medium hover:brightness-110 transition">
            <Activity className="w-3.5 h-3.5" strokeWidth={2.2} />
            Activity Monitor
          </button>
          <button className="glass-row rounded-xl py-2.5 flex items-center justify-center gap-2 text-[12px] font-medium hover:brightness-110 transition">
            <Settings className="w-3.5 h-3.5" strokeWidth={2.2} />
            Settings
          </button>
        </div>
      </div>

      <p className="mt-6 text-[11px] text-foreground/50 tracking-wider uppercase">
        Liquid Glass · Menu Bar Concept
      </p>
    </div>
  );
}
