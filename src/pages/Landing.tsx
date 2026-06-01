// Public marketing landing (the app's `/` for logged-out visitors). Signed-in
// users never see this — the route gate redirects them to the app. Voice:
// professional & trustworthy. Theme-aware, reuses the ambient-gradient style.

import { Link } from "react-router-dom";
import {
  ArrowRight,
  Layers,
  Users,
  HandCoins,
  FileText,
  ShieldCheck,
  WifiOff,
  type LucideIcon,
} from "lucide-react";
import { useAuth } from "@/auth/AuthProvider";
import { Button } from "@/components/ui/button";
import { ThemeToggle } from "@/components/ThemeToggle";
import { Logo, LogoMark } from "@/components/Logo";
import { cn } from "@/lib/utils";

interface Feature {
  icon: LucideIcon;
  title: string;
  body: string;
}

const FEATURES: Feature[] = [
  {
    icon: Layers,
    title: "Multi-line transactions",
    body: "Record split bills, fees, taxes and transfers as a single balanced entry — the way real money moves.",
  },
  {
    icon: Users,
    title: "Shared ledger",
    body: "Split expenses with other people across workspaces. Each side keeps its own books; balances reconcile by consent.",
  },
  {
    icon: HandCoins,
    title: "Debts & dues",
    body: "Track who owes whom, lending, custodial savings and recurring dues — outstanding is always derived, never guessed.",
  },
  {
    icon: FileText,
    title: "Financial-year tax",
    body: "Per-head taxable summaries and TDS totals for the financial year, exportable to CSV in a click.",
  },
  {
    icon: ShieldCheck,
    title: "Roles & workspaces",
    body: "Invite members with precise, role-based permissions. Run a household and a business from one account.",
  },
  {
    icon: WifiOff,
    title: "Works offline",
    body: "A fast, installable app that loads instantly and queues changes when you're offline — built for the move.",
  },
];

export function Landing() {
  const { signIn } = useAuth();

  return (
    <div className="relative min-h-screen overflow-hidden bg-background">
      {/* ambient gradient blobs */}
      <div className="pointer-events-none absolute -left-32 -top-32 h-96 w-96 rounded-full bg-primary/25 blur-3xl" />
      <div className="pointer-events-none absolute -right-32 top-40 h-96 w-96 rounded-full bg-accent2/20 blur-3xl" />

      {/* nav */}
      <header className="relative z-10 mx-auto flex max-w-6xl items-center justify-between px-4 py-5 sm:px-6">
        <Logo size="sm" />
        <div className="flex items-center gap-2">
          <ThemeToggle />
          <Button variant="ghost" size="sm" onClick={() => void signIn()}>
            Sign in
          </Button>
        </div>
      </header>

      {/* hero */}
      <section className="relative z-10 mx-auto max-w-6xl px-4 pb-16 pt-10 text-center sm:px-6 sm:pt-20">
        <LogoMark size="xl" className="mx-auto mb-6 shadow-xl" />
        <h1 className="mx-auto max-w-3xl text-balance text-4xl font-semibold tracking-tight sm:text-5xl">
          Every rupee, <span className="brand-gradient-text">accounted for.</span>
        </h1>
        <p className="mx-auto mt-4 max-w-2xl text-pretty text-base text-muted-foreground sm:text-lg">
          NizKhata is shared, multi-workspace accounting for households and small businesses —
          multi-line transactions, debts, dues and financial-year tax summaries, with role-based
          access and a ledger you can trust.
        </p>
        <div className="mt-8 flex flex-col items-center justify-center gap-3 sm:flex-row">
          <Button size="lg" className="gap-2" onClick={() => void signIn()}>
            Continue with Google
            <ArrowRight className="h-4 w-4" />
          </Button>
          <Button size="lg" variant="outline" asChild>
            <a href="#features">See features</a>
          </Button>
        </div>
        <p className="mt-4 text-xs text-muted-foreground">
          Free to start · your first sign-in creates a personal workspace.
        </p>
      </section>

      {/* features */}
      <section id="features" className="relative z-10 mx-auto max-w-6xl px-4 pb-20 sm:px-6">
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {FEATURES.map((f, i) => (
            <div
              key={f.title}
              className="glass elevated-hover rounded-2xl p-5"
            >
              <span
                className={cn(
                  "flex h-10 w-10 items-center justify-center rounded-xl",
                  i % 2 === 0 ? "bg-primary/10 text-primary" : "bg-accent2/10 text-accent2",
                )}
              >
                <f.icon className="h-5 w-5" />
              </span>
              <h3 className="mt-4 font-semibold tracking-tight">{f.title}</h3>
              <p className="mt-1.5 text-sm text-muted-foreground">{f.body}</p>
            </div>
          ))}
        </div>
      </section>

      {/* trust band */}
      <section className="relative z-10 border-t bg-card/40">
        <div className="mx-auto flex max-w-6xl flex-col items-center gap-4 px-4 py-14 text-center sm:px-6">
          <ShieldCheck className="h-8 w-8 text-primary" />
          <h2 className="max-w-2xl text-2xl font-semibold tracking-tight">
            Your books, your rules.
          </h2>
          <p className="max-w-2xl text-pretty text-sm text-muted-foreground">
            Data is scoped to your workspace and protected by security rules — partners and members
            see only what their role allows. Balances and reports are derived from your entries, so
            the numbers always add up.
          </p>
          <Button size="lg" className="mt-2 gap-2" onClick={() => void signIn()}>
            Get started
            <ArrowRight className="h-4 w-4" />
          </Button>
        </div>
      </section>

      {/* footer */}
      <footer className="relative z-10 border-t">
        <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-3 px-4 py-8 text-sm text-muted-foreground sm:flex-row sm:px-6">
          <Logo size="sm" wordmarkClassName="text-foreground" />
          <p>© {new Date().getFullYear()} NizKhata. Every rupee, accounted for.</p>
          <Link to="/login" className="hover:text-foreground">
            Sign in
          </Link>
        </div>
      </footer>
    </div>
  );
}
