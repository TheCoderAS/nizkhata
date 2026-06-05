// Animated number that tweens from 0 (or its previous value) to the target on
// mount and on change. Used for headline figures so balances feel earned rather
// than just appearing. Honors prefers-reduced-motion by snapping to the value.

import { useEffect, useRef, useState } from "react";

function prefersReducedMotion() {
  return (
    typeof window !== "undefined" &&
    window.matchMedia?.("(prefers-reduced-motion: reduce)").matches
  );
}

// easeOutCubic — fast start, gentle settle.
const ease = (t: number) => 1 - Math.pow(1 - t, 3);

export function CountUp({
  value,
  duration = 800,
  format,
  className,
}: {
  value: number;
  duration?: number;
  // Render the (possibly fractional) in-flight number. Defaults to a rounded
  // en-IN integer.
  format?: (n: number) => string;
  className?: string;
}) {
  const fmt = format ?? ((n: number) => Intl.NumberFormat("en-IN").format(Math.round(n)));
  // Start from 0 so the first mount ticks up; subsequent changes tween from the
  // last shown value (tracked in fromRef).
  const [display, setDisplay] = useState(0);
  const fromRef = useRef(0);
  const rafRef = useRef<number>();

  useEffect(() => {
    if (prefersReducedMotion() || duration <= 0) {
      setDisplay(value);
      fromRef.current = value;
      return;
    }
    const from = fromRef.current;
    const delta = value - from;
    if (delta === 0) return;
    const start = performance.now();

    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / duration);
      if (t < 1) {
        // Round in-flight for clean ticking; land on the exact value at rest so
        // paise aren't lost in the final render.
        setDisplay(Math.round(from + delta * ease(t)));
        rafRef.current = requestAnimationFrame(tick);
      } else {
        setDisplay(value);
        fromRef.current = value;
      }
    };
    rafRef.current = requestAnimationFrame(tick);
    return () => {
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
      fromRef.current = value; // so the next change tweens from where we are
    };
  }, [value, duration]);

  return <span className={className}>{fmt(display)}</span>;
}
