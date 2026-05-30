// PWA update toast: when a new service worker is ready, offer a one-tap reload.
// Uses virtual:pwa-register/react from vite-plugin-pwa.

import { useRegisterSW } from "virtual:pwa-register/react";
import { Button } from "@/components/ui/button";
import { RefreshCw } from "lucide-react";

export function PWAPrompt() {
  const {
    needRefresh: [needRefresh, setNeedRefresh],
    updateServiceWorker,
  } = useRegisterSW();

  if (!needRefresh) return null;

  return (
    <div className="fixed bottom-4 left-1/2 z-[200] -translate-x-1/2 animate-fade-in-up">
      <div className="flex items-center gap-3 rounded-full border bg-card px-4 py-2 shadow-lg">
        <RefreshCw className="h-4 w-4 text-primary" />
        <span className="text-sm">A new version is available.</span>
        <Button size="sm" onClick={() => void updateServiceWorker(true)}>
          Reload
        </Button>
        <Button
          size="sm"
          variant="ghost"
          onClick={() => setNeedRefresh(false)}
        >
          Later
        </Button>
      </div>
    </div>
  );
}
