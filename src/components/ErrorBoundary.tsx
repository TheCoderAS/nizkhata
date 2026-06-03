// Top-level + per-route error boundary. A render error in any screen would
// otherwise white-screen the whole app; this catches it and shows a friendly
// recover/reload fallback instead. Class component because React only supports
// error catching via getDerivedStateFromError / componentDidCatch.

import { Component, type ErrorInfo, type ReactNode } from "react";
import { AlertTriangle, RotateCcw } from "lucide-react";
import { Button } from "@/components/ui/button";

interface Props {
  children: ReactNode;
  /** Re-mounts children when this changes (e.g. route path) to clear the error. */
  resetKey?: string;
  /** "page" keeps the app shell; "app" is the full-screen top-level fallback. */
  variant?: "page" | "app";
}

interface State {
  error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidUpdate(prev: Props) {
    // Clear the error when navigating to a different route.
    if (this.state.error && prev.resetKey !== this.props.resetKey) {
      this.setState({ error: null });
    }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    // eslint-disable-next-line no-console
    console.error("[ErrorBoundary]", error, info.componentStack);
  }

  render() {
    if (!this.state.error) return this.props.children;

    const isApp = this.props.variant === "app";
    return (
      <div
        className={
          isApp
            ? "flex min-h-screen flex-col items-center justify-center gap-4 bg-background p-6 text-center"
            : "flex flex-col items-center justify-center gap-4 rounded-xl border border-destructive/30 bg-destructive/5 p-10 text-center"
        }
      >
        <span className="flex h-12 w-12 items-center justify-center rounded-full bg-destructive/10 text-destructive">
          <AlertTriangle className="h-6 w-6" />
        </span>
        <div>
          <h2 className="text-lg font-semibold">Something went wrong</h2>
          <p className="mt-1 max-w-md text-sm text-muted-foreground">
            {isApp
              ? "The app hit an unexpected error. Reloading usually fixes it."
              : "This screen hit an unexpected error. Try again, or reload the app."}
          </p>
        </div>
        <div className="flex gap-2">
          {!isApp && (
            <Button variant="outline" onClick={() => this.setState({ error: null })}>
              <RotateCcw className="h-4 w-4" /> Try again
            </Button>
          )}
          <Button onClick={() => window.location.reload()}>Reload app</Button>
        </div>
      </div>
    );
  }
}
