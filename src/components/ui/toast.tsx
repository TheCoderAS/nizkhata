// Minimal toast system (no extra dependency). Provides useToast() + <Toaster/>.

import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { X } from "lucide-react";
import { cn } from "@/lib/utils";

type ToastVariant = "default" | "success" | "error";
interface Toast {
  id: number;
  title: string;
  description?: string;
  variant: ToastVariant;
}

interface ToastApi {
  toast: (t: { title: string; description?: string; variant?: ToastVariant }) => void;
  /**
   * Run an async action, surfacing a success toast on completion and an error
   * toast (with the thrown message) on failure — so a failed write never fails
   * silently. Returns true on success, false on error.
   */
  runWithToast: (
    action: () => Promise<unknown>,
    opts?: { success?: string; error?: string },
  ) => Promise<boolean>;
}

const ToastContext = createContext<ToastApi | undefined>(undefined);

let counter = 0;

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const remove = useCallback((id: number) => {
    setToasts((ts) => ts.filter((t) => t.id !== id));
  }, []);

  const toast = useCallback<ToastApi["toast"]>(
    ({ title, description, variant = "default" }) => {
      const id = ++counter;
      setToasts((ts) => [...ts, { id, title, description, variant }]);
      setTimeout(() => remove(id), 4000);
    },
    [remove],
  );

  const runWithToast = useCallback<ToastApi["runWithToast"]>(
    async (action, opts) => {
      try {
        await action();
        if (opts?.success) toast({ title: opts.success, variant: "success" });
        return true;
      } catch (e) {
        toast({
          title: opts?.error ?? "Couldn't save changes",
          description: e instanceof Error ? e.message : undefined,
          variant: "error",
        });
        return false;
      }
    },
    [toast],
  );

  const api = useMemo(() => ({ toast, runWithToast }), [toast, runWithToast]);

  return (
    <ToastContext.Provider value={api}>
      {children}
      <div className="fixed bottom-4 right-4 z-[100] flex w-80 flex-col gap-2">
        {toasts.map((t) => (
          <div
            key={t.id}
            role="status"
            className={cn(
              "relative rounded-md border p-3 pr-9 shadow-md",
              t.variant === "success" && "border-green-200 bg-green-50 text-green-800",
              t.variant === "error" && "border-red-200 bg-red-50 text-red-800",
              t.variant === "default" && "border-border bg-background",
            )}
          >
            <p className="text-sm font-medium">{t.title}</p>
            {t.description && (
              <p className="text-xs opacity-80">{t.description}</p>
            )}
            <button
              type="button"
              aria-label="Dismiss"
              onClick={() => remove(t.id)}
              className="absolute right-1.5 top-1.5 rounded p-1 opacity-60 transition-opacity hover:opacity-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-current"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast(): ToastApi {
  const ctx = useContext(ToastContext);
  if (!ctx) throw new Error("useToast must be used within <ToastProvider>");
  return ctx;
}
