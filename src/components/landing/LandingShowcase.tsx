/* /home/user/eclipta-your-smart-learning-journey/src/components/landing/LandingShowcase.tsx */
/**
 * Eclipta homepage — full redesign.
 *
 * Structure (top to bottom):
 *   1. Hero            — "Study is dead. Fight for it." + live HUD + social proof strip
 *   2. LiveTicker      — recent battle results scrolling feed
 *   3. GameLoop        — 5-step "one loop, zero boredom" diagram
 *   4. ClassPicker     — 8 archetypes, personality-first, stats on hover
 *   5. TheClimb        — rank ladder as 2×4 tier grid with unlock descriptions
 *   6. TrophyRoad      — Ecliptar collector grid, locked/unlocked states
 *   7. DailyChallenge  — today's challenge with live countdown to midnight UTC
 *   8. TrainingRoom    — Luna / Tests / Courses / Forum, framed as preparation
 *   9. FinalCTA        — class-select interactive CTA with 8 class tiles
 */
import { useEffect, useMemo, useRef, useState, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Link } from "@tanstack/react-router";
import {
  ArrowRight, Swords, Zap, Heart, Flame, Target, Crown, Trophy, Shield,
  Brain, GraduationCap, MessagesSquare, Sparkles, Timer, ChevronRight,
  PlayCircle, Activity, Users, TrendingUp, Star, Dice5, Scale, FastForward,
  Skull, Lock, CheckCircle2,
} from "lucide-react";
import { useAuth } from "@/hooks/use-auth";
import { ARCHETYPES } from "@/components/battles/archetypes";
import { getTodayChallenge } from "@/lib/daily-challenge";

/* ════════════════════════════════════════════════════════════════════
   SHARED HELPERS
   ════════════════════════════════════════════════════════════════════ */

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="text-center">
      <p className="text-[8px] font-bold tracking-widest text-muted-foreground uppercase">{label}</p>
      <p className="text-xs font-bold font-display tabular-nums">{value}</p>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   1. HERO  —  "Study is dead. Fight for it."
   ════════════════════════════════════════════════════════════════════ */

function Hero() {
  const { isAuthenticated } = useAuth();
  const ctaTo = isAuthenticated ? "/battles" : "/signup";
  const ctaLabel = isAuthenticated ? "ENTER THE ARENA" : "FIGHT FREE";

  const socialProof = [
    { value: "2,847", label: "battles today" },
    { value: "1,284", label: "in queue" },
    { value: "341",   label: "accepted challenge" },
    { value: "16",    label: "Ecliptars to collect" },
  ];

  return (
    <section className="pt-28 pb-0 px-6 relative overflow-hidden">
      {/* Grid overlay */}
      <div
        className="absolute inset-0 pointer-events-none"
        style={{
          backgroundImage:
            "linear-gradient(oklch(1 0 0/3%) 1px,transparent 1px),linear-gradient(90deg,oklch(1 0 0/3%) 1px,transparent 1px)",
          backgroundSize: "64px 64px",
        }}
      />
      {/* Ambient arena glows */}
      <div className="absolute top-[-20%] right-[-10%] w-[42rem] h-[42rem] bg-neon-pink/15 rounded-full blur-[140px] animate-arena-drift" />
      <div className="absolute bottom-[-15%] left-[-15%] w-[36rem] h-[36rem] bg-neon-purple/15 rounded-full blur-[140px] animate-arena-drift [animation-delay:-7s]" />

      <div className="max-w-7xl mx-auto relative grid grid-cols-1 lg:grid-cols-12 gap-10 items-center">
        {/* Left: copy */}
        <div className="lg:col-span-7">
          <motion.div
            initial={{ opacity: 0, y: -8 }} animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.4 }}
            className="inline-flex items-center gap-2 px-3 py-1.5 mb-6 border border-neon-pink/40 bg-neon-pink/5 text-neon-pink text-[10px] font-bold tracking-[0.25em] uppercase"
          >
            <span className="relative flex h-2 w-2">
              <span className="absolute inline-flex h-full w-full rounded-full bg-neon-pink opacity-60 animate-ping" />
              <span className="relative inline-flex rounded-full h-2 w-2 bg-neon-pink" />
            </span>
            Season 01 · Live · 1,284 in queue
          </motion.div>

          <motion.h1
            initial={{ opacity: 0, y: 18 }} animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.55, ease: [0.22, 1, 0.36, 1] }}
            className="text-[3.4rem] md:text-[5.5rem] lg:text-[6.2rem] font-bold tracking-tighter leading-[0.88] mb-6 font-display"
          >
            STUDY IS DEAD. <br />
            <span className="text-neon-pink animate-neon-flicker">FIGHT FOR IT.</span>
          </motion.h1>

          <motion.p
            initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5, delay: 0.1 }}
            className="max-w-xl text-base md:text-lg text-muted-foreground mb-9 leading-relaxed"
          >
            Eclipta turns learning into 1v1 knowledge duels. Pick a class, queue up,
            land combos, climb the ranks. AI tutoring is the warm-up — the arena is the point.
          </motion.p>

          <motion.div
            initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.45, delay: 0.2 }}
            className="flex flex-wrap gap-3 items-center"
          >
            <Link
              to={ctaTo}
              className="px-8 py-4 bg-neon-pink text-foreground font-bold text-sm tracking-[0.2em] inline-flex items-center gap-3 group hover:scale-[1.03] transition-transform animate-battle-charge"
            >
              <Swords className="w-4 h-4" />
              {ctaLabel}
              <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
            </Link>
            <a
              href="#how-it-works"
              className="px-6 py-4 border border-border hover:border-neon-purple text-foreground font-bold text-sm tracking-[0.2em] inline-flex items-center gap-2 transition-colors"
            >
              <PlayCircle className="w-4 h-4" />
              SEE HOW IT WORKS
            </a>
          </motion.div>

          <motion.div
            initial={{ opacity: 0 }} animate={{ opacity: 1 }}
            transition={{ duration: 0.5, delay: 0.35 }}
            className="mt-8 flex flex-wrap items-center gap-x-6 gap-y-2 text-[10px] font-bold tracking-[0.2em] uppercase text-muted-foreground"
          >
            <span className="inline-flex items-center gap-1.5"><Zap className="w-3 h-3 text-neon-purple" /> Free to play</span>
            <span className="inline-flex items-center gap-1.5"><Trophy className="w-3 h-3 text-neon-pink" /> 8 classes · 16 Ecliptars</span>
            <span className="inline-flex items-center gap-1.5"><Crown className="w-3 h-3 text-tier-gold" /> 8 ranked tiers</span>
          </motion.div>
        </div>

        {/* Right: live battle HUD */}
        <div className="lg:col-span-5">
          <LiveBattleHUD />
        </div>
      </div>

      {/* Social proof strip */}
      <div className="max-w-7xl mx-auto relative mt-16 border-t border-border/60 grid grid-cols-2 md:grid-cols-4">
        {socialProof.map((s, i) => (
          <motion.div
            key={s.label}
            initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.4 + i * 0.07, duration: 0.35 }}
            className="py-5 px-6 border-r border-border/60 last:border-r-0 flex flex-col items-center text-center"
          >
            <span className="text-2xl md:text-3xl font-bold font-display text-neon-pink tabular-nums">{s.value}</span>
            <span className="text-[10px] font-bold tracking-[0.2em] uppercase text-muted-foreground mt-1">{s.label}</span>
          </motion.div>
        ))}
      </div>
    </section>
  );
}

/* ────────── Live Battle HUD card ────────── */

function LiveBattleHUD() {
  const [playerHp, setPlayerHp] = useState(78);
  const [oppHp, setOppHp] = useState(54);
  const [combo, setCombo] = useState(3);
  const [popup, setPopup] = useState<{ id: number; text: string; crit?: boolean } | null>(null);
  const [logIdx, setLogIdx] = useState(0);
  const log = useMemo(() => [
    { text: "+34 DMG · Algebra · 2x combo", crit: false, opp: true,  hp: -34 },
    { text: "CRIT! +52 DMG · Derivatives",   crit: true,  opp: true,  hp: -52 },
    { text: "Healed +18 HP · Focus spent",   crit: false, opp: false, hp: +18, mine: true },
    { text: "+28 DMG · Vectors · 3x combo",  crit: false, opp: true,  hp: -28 },
    { text: "BLOCKED · Wrong answer −12 HP", crit: false, opp: false, hp: -12, mine: true },
  ], []);

  useEffect(() => {
    const id = setInterval(() => {
      const entry = log[logIdx % log.length];
      setPopup({ id: Date.now(), text: entry.text, crit: entry.crit });
      if (entry.mine) {
        setPlayerHp((h) => Math.min(100, Math.max(0, h + entry.hp)));
      } else {
        setOppHp((h) => Math.min(100, Math.max(0, h + entry.hp)));
        if (entry.crit) setCombo((c) => c + 2);
        else setCombo((c) => c + 1);
      }
      setLogIdx((i) => i + 1);
      // Auto-reset on KO so the loop never stalls.
      setTimeout(() => {
        setPlayerHp((h) => (h <= 5 ? 78 : h));
        setOppHp((h) => (h <= 5 ? 64 : h));
      }, 2200);
    }, 2400);
    return () => clearInterval(id);
  }, [log, logIdx]);

  return (
    <motion.div
      initial={{ opacity: 0, x: 28, skewX: -3 }} animate={{ opacity: 1, x: 0, skewX: 0 }}
      transition={{ duration: 0.55, delay: 0.18, ease: [0.22, 1, 0.36, 1] }}
      className="relative"
    >
      <div className="absolute -inset-2 bg-gradient-to-tr from-neon-pink/30 via-neon-purple/20 to-neon-cyan/20 blur-2xl opacity-60" />
      <div className="relative glass-panel p-6">
        <div className="flex items-center justify-between mb-5">
          <div className="flex items-center gap-2">
            <Activity className="w-3.5 h-3.5 text-neon-pink" />
            <span className="text-[10px] font-bold tracking-[0.25em] uppercase text-neon-pink">Live · Round 3</span>
          </div>
          <span className="text-[10px] font-mono tracking-widest text-muted-foreground">BO5 · RANKED</span>
        </div>

        {/* Player */}
        <FighterRow
          name="YOU" sub="Speedster · Diamond II" hp={playerHp}
          icon={Zap} colorClass="text-neon-cyan" borderClass="border-neon-cyan/40" barClass="bg-neon-cyan"
          alignRight={false}
        />

        {/* Center mid bar with combo + damage popup */}
        <div className="relative my-4 h-14 flex items-center justify-center border-y border-border/60">
          <div className="flex items-center gap-3">
            <Flame className="w-4 h-4 text-neon-pink" />
            <span className="text-2xl font-bold font-display tabular-nums text-neon-pink">
              {combo}<span className="text-xs text-muted-foreground">x COMBO</span>
            </span>
            <span className="hidden sm:inline w-px h-5 bg-border" />
            <span className="hidden sm:inline-flex items-center gap-1 text-xs text-muted-foreground">
              <Timer className="w-3 h-3" /> 0:08
            </span>
          </div>
          <AnimatePresence>
            {popup && (
              <motion.div
                key={popup.id}
                initial={{ opacity: 0, y: 8, scale: 0.9 }}
                animate={{ opacity: 1, y: -18, scale: 1 }}
                exit={{ opacity: 0, y: -36, scale: 0.95 }}
                transition={{ duration: 0.7 }}
                className={`absolute right-2 top-1 px-2 py-0.5 text-[10px] font-bold tracking-wider ${
                  popup.crit
                    ? "bg-neon-pink text-foreground"
                    : "bg-neon-purple/20 text-neon-purple border border-neon-purple/40"
                }`}
              >
                {popup.text}
              </motion.div>
            )}
          </AnimatePresence>
        </div>

        {/* Opponent */}
        <FighterRow
          name="@kazu_47" sub="Chud · Diamond I" hp={oppHp}
          icon={Crown} colorClass="text-tier-champion" borderClass="border-tier-champion/40" barClass="bg-tier-champion"
          alignRight
        />

        <div className="mt-5 flex items-center justify-between text-[10px] font-bold tracking-widest uppercase">
          <span className="text-muted-foreground">Reward · <span className="text-neon-cyan">+185 XP</span></span>
          <span className="text-muted-foreground">On the line · <span className="text-neon-pink">Diamond Promo</span></span>
        </div>
      </div>
    </motion.div>
  );
}

function FighterRow(props: {
  name: string; sub: string; hp: number;
  icon: React.ComponentType<{ className?: string }>;
  colorClass: string; borderClass: string; barClass: string; alignRight: boolean;
}) {
  const { name, sub, hp, icon: Icon, colorClass, borderClass, barClass, alignRight } = props;
  return (
    <div className={`flex items-center gap-3 ${alignRight ? "flex-row-reverse text-right" : ""}`}>
      <div className={`w-12 h-12 shrink-0 border ${borderClass} bg-secondary/40 flex items-center justify-center`}>
        <Icon className={`w-5 h-5 ${colorClass}`} />
      </div>
      <div className="flex-1 min-w-0">
        <div className={`flex items-baseline justify-between gap-2 ${alignRight ? "flex-row-reverse" : ""}`}>
          <span className="font-bold text-sm font-display tracking-wider truncate">{name}</span>
          <span className="text-[10px] font-mono tabular-nums text-muted-foreground">{Math.round(hp)}/100</span>
        </div>
        <p className="text-[10px] tracking-[0.18em] uppercase text-muted-foreground mb-1.5 truncate">{sub}</p>
        <div className="h-2 bg-secondary/60 relative overflow-hidden">
          <motion.div
            className={`h-full ${barClass}`}
            animate={{ width: `${hp}%` }}
            transition={{ type: "spring", stiffness: 120, damping: 18 }}
          />
          <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent animate-xp-shimmer pointer-events-none" />
        </div>
      </div>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   2. LIVE TICKER  —  recent results scroll
   ════════════════════════════════════════════════════════════════════ */

const TICKER_DATA = [
  { winner: "@nova_q",  klass: "Speedster",   loser: "@brio",   time: "0:47", topic: "Calculus" },
  { winner: "@kira_x",  klass: "Healer",      loser: "@hyx",    time: "1:12", topic: "Vocab" },
  { winner: "@orin",    klass: "Chud",        loser: "@drei_v", time: "0:38", topic: "Physics" },
  { winner: "@zee",     klass: "Fulcrum",     loser: "@mara",   time: "1:02", topic: "Geometry" },
  { winner: "@tav",     klass: "Accelerator", loser: "@ilya",   time: "0:55", topic: "French" },
  { winner: "@mio",     klass: "Tank",        loser: "@cyx_r",  time: "1:24", topic: "Chemistry" },
  { winner: "@ren_44",  klass: "Gambler",     loser: "@noor",   time: "0:29", topic: "History" },
  { winner: "@aki",     klass: "God",         loser: "@silas",  time: "1:41", topic: "Linear Alg." },
] as const;

function LiveTicker() {
  // Duplicate items for seamless infinite loop
  const items = [...TICKER_DATA, ...TICKER_DATA];
  return (
    <div className="border-y border-border bg-arena-light/40 overflow-hidden">
      <div className="relative flex items-center h-14">
        {/* Label pill — larger and more prominent */}
        <div className="absolute left-0 top-0 bottom-0 z-10 px-5 flex items-center gap-2.5 bg-neon-pink text-foreground border-r border-neon-pink/60">
          <span className="relative flex h-2 w-2">
            <span className="absolute inline-flex h-full w-full rounded-full bg-foreground opacity-60 animate-ping" />
            <span className="relative inline-flex rounded-full h-2 w-2 bg-foreground" />
          </span>
          <span className="text-[10px] font-bold tracking-[0.3em] uppercase whitespace-nowrap">LIVE FEED</span>
        </div>

        {/* Player count badge */}
        <div className="absolute right-0 top-0 bottom-0 z-10 px-4 flex items-center bg-background/80 border-l border-border">
          <span className="text-[10px] font-bold tracking-widest text-muted-foreground whitespace-nowrap">
            <span className="text-neon-cyan">1,284</span> watching
          </span>
        </div>

        <div className="absolute left-0 right-0 overflow-hidden pl-44 pr-28">
          <div className="flex items-center gap-10 animate-[ticker_45s_linear_infinite] whitespace-nowrap">
            {items.map((t, i) => (
              <div key={i} className="flex items-center gap-2 text-xs">
                <Swords className="w-3 h-3 text-neon-pink shrink-0" />
                <span className="text-foreground font-medium">{t.winner}</span>
                <span className="text-[10px] uppercase tracking-widest text-neon-cyan font-bold">{t.klass}</span>
                <span className="text-muted-foreground">defeated</span>
                <span className="text-foreground">{t.loser}</span>
                <span className="text-muted-foreground">·</span>
                <span className="text-muted-foreground">{t.topic}</span>
                <span className="text-muted-foreground">·</span>
                <span className="font-mono text-neon-pink tabular-nums">{t.time}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
      <style>{`@keyframes ticker { from { transform: translateX(0); } to { transform: translateX(-50%); } }`}</style>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   3. GAME LOOP  —  5-step "one loop, zero boredom" diagram
   ════════════════════════════════════════════════════════════════════ */

const LOOP_STEPS = [
  {
    num: "01",
    icon: Users,
    label: "QUEUE",
    desc: "Pick your class. Find a real opponent.",
  },
  {
    num: "02",
    icon: Swords,
    label: "DUEL",
    desc: "Answer fast. Hit hard. Build combos.",
  },
  {
    num: "03",
    icon: TrendingUp,
    label: "WIN",
    desc: "Earn XP. Climb the rated ladder.",
  },
  {
    num: "04",
    icon: Trophy,
    label: "COLLECT",
    desc: "Unlock Ecliptars. Fill the Trophy Road.",
  },
  {
    num: "05",
    icon: Flame,
    label: "RETURN",
    desc: "Daily challenges. New rivals. Repeat.",
  },
] as const;

function GameLoop() {
  return (
    <section id="how-it-works" className="px-6 py-24 scroll-mt-20 border-y border-border bg-secondary/10">
      <div className="max-w-6xl mx-auto">
        <div className="text-center mb-14">
          <p className="text-[11px] font-bold tracking-[0.3em] uppercase text-neon-cyan mb-3">The System</p>
          <h2 className="text-4xl md:text-6xl font-bold font-display tracking-tight mb-4">
            One loop. Zero boredom.
          </h2>
          <p className="text-muted-foreground max-w-2xl mx-auto">
            Every battle feeds the next. There&apos;s always something to win, earn, or climb.
          </p>
        </div>

        <div className="flex flex-col md:flex-row items-stretch gap-0 md:gap-0">
          {LOOP_STEPS.map((step, i) => {
            const Icon = step.icon;
            return (
              <div key={step.num} className="flex flex-col md:flex-row items-center flex-1">
                <motion.div
                  initial={{ opacity: 0, y: 22 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={{ once: true }}
                  transition={{ delay: i * 0.1, duration: 0.45 }}
                  className="flex-1 glass-panel p-6 text-center group hover:border-neon-cyan/40 transition-colors w-full"
                >
                  {/* Number badge */}
                  <span className="inline-block text-[10px] font-bold tracking-[0.3em] text-muted-foreground mb-4 font-mono">
                    {step.num}
                  </span>
                  <div className="w-12 h-12 mx-auto mb-4 border border-neon-cyan/30 bg-neon-cyan/5 flex items-center justify-center group-hover:border-neon-cyan/60 transition-colors">
                    <Icon className="w-6 h-6 text-neon-cyan group-hover:scale-110 transition-transform" />
                  </div>
                  <p className="text-[10px] font-bold tracking-[0.3em] uppercase text-neon-cyan mb-2">{step.label}</p>
                  <p className="text-xs text-muted-foreground leading-relaxed">{step.desc}</p>
                </motion.div>

                {/* Arrow connector — only between steps, not after the last */}
                {i < LOOP_STEPS.length - 1 && (
                  <div className="flex items-center justify-center px-2 py-3 md:py-0 shrink-0">
                    <ChevronRight className="w-4 h-4 text-neon-pink/60 rotate-90 md:rotate-0" />
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   4. CLASS PICKER  —  personality-first, stats on hover
   ════════════════════════════════════════════════════════════════════ */

const CLASS_PERSONALITIES: Record<string, { blurb: string; playstyle: string }> = {
  speedster:   { blurb: "The sprinter. Faster questions, higher stakes, bigger hits.",         playstyle: "Aggressive" },
  tank:        { blurb: "The immovable. You take forever to die. You deal nothing.",            playstyle: "Defensive" },
  chud:        { blurb: "The gambit. Maximum damage. Minimal health. Do or die.",               playstyle: "Aggressive" },
  gambler:     { blurb: "Pure chaos. Stats roll fresh every match. You never know.",            playstyle: "Chaos" },
  healer:      { blurb: "The grind. Impossible to kill. Infuriating to fight.",                 playstyle: "Sustain" },
  fulcrum:     { blurb: "The precision build. Land combos consistently. Punish mistakes.",      playstyle: "Technical" },
  accelerator: { blurb: "The snowball. Starts weak. Gets terrifying.",                          playstyle: "Scaling" },
  god:         { blurb: "Endgame only. All stats maxed. Questions hardest. Not a starter.",     playstyle: "Endgame" },
};

const PLAYSTYLE_COLORS: Record<string, string> = {
  Aggressive: "text-neon-pink border-neon-pink/40",
  Defensive:  "text-tier-silver border-tier-silver/40",
  Chaos:      "text-tier-gold border-tier-gold/40",
  Sustain:    "text-neon-pink border-neon-pink/40",
  Technical:  "text-neon-purple border-neon-purple/40",
  Scaling:    "text-tier-platinum border-tier-platinum/40",
  Endgame:    "text-tier-god border-tier-god/40",
};

function ClassPicker() {
  const [hoveredClass, setHoveredClass] = useState<string | null>(null);

  const order: (keyof typeof ARCHETYPES)[] = [
    "speedster", "tank", "chud", "gambler", "healer", "fulcrum", "accelerator", "god",
  ];

  return (
    <section className="px-6 py-24 border-y border-border bg-secondary/15">
      <div className="max-w-7xl mx-auto">
        <div className="text-center mb-12">
          <p className="text-[11px] font-bold tracking-[0.3em] uppercase text-neon-cyan mb-3">Eight Classes · One Main</p>
          <h2 className="text-4xl md:text-6xl font-bold font-display tracking-tight mb-2">
            Eight classes. One main.
          </h2>
          <h3 className="text-xl md:text-2xl font-bold font-display text-muted-foreground tracking-tight mb-4">
            Pick how you fight.
          </h3>
          <p className="text-muted-foreground max-w-2xl mx-auto">
            Every archetype changes the rules of engagement. Hover a card to see the numbers behind the personality.
          </p>
        </div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          {order.map((id, i) => {
            const a = ARCHETYPES[id];
            const personality = CLASS_PERSONALITIES[id];
            const Icon = a.icon;
            const isHovered = hoveredClass === id;
            const playstyleColor = PLAYSTYLE_COLORS[personality.playstyle] ?? "text-muted-foreground border-border";

            return (
              <motion.div
                key={id}
                initial={{ opacity: 0, y: 18 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ delay: (i % 4) * 0.06, duration: 0.4 }}
                onMouseEnter={() => setHoveredClass(id)}
                onMouseLeave={() => setHoveredClass(null)}
              >
                <Link
                  to="/battles"
                  className={`group block glass-panel p-5 h-full transition-all hover:-translate-y-1 ${
                    isHovered ? `border-[${a.color.replace("text-", "")}]/50` : ""
                  }`}
                  style={isHovered ? { borderColor: "var(--neon-accent, currentColor)" } : {}}
                >
                  <div className={`w-10 h-10 border ${a.borderColor} bg-background/30 flex items-center justify-center mb-3`}>
                    <Icon className={`w-5 h-5 ${a.color} group-hover:scale-110 transition-transform`} />
                  </div>

                  <div className={`inline-flex items-center px-1.5 py-0.5 border text-[8px] font-bold tracking-widest uppercase mb-2 ${playstyleColor}`}>
                    {personality.playstyle}
                  </div>

                  <h3 className={`text-sm font-bold font-display tracking-wider mb-2 ${a.color}`}>
                    {a.name.replace("The ", "").toUpperCase()}
                  </h3>

                  <p className="text-[11px] text-muted-foreground leading-relaxed mb-3">
                    {personality.blurb}
                  </p>

                  {/* Stats — shown on hover */}
                  <AnimatePresence>
                    {isHovered && (
                      <motion.div
                        initial={{ opacity: 0, height: 0 }}
                        animate={{ opacity: 1, height: "auto" }}
                        exit={{ opacity: 0, height: 0 }}
                        transition={{ duration: 0.2 }}
                        className="overflow-hidden"
                      >
                        <div className="grid grid-cols-3 gap-1 text-center border-t border-border/50 pt-3 mt-1">
                          <Stat label="HP"  value={String(a.maxHp)} />
                          <Stat label="DMG" value={String(a.baseDamage)} />
                          <Stat label="DIFF" value={`${a.diffMin}-${a.diffMax}`} />
                        </div>
                        <p className="text-[9px] uppercase tracking-widest text-muted-foreground mt-2 text-center">{a.passive}</p>
                      </motion.div>
                    )}
                  </AnimatePresence>
                </Link>
              </motion.div>
            );
          })}
        </div>
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   5. THE CLIMB  —  tier grid with unlock descriptions
   ════════════════════════════════════════════════════════════════════ */

const TIER_DATA = [
  { name: "Bronze",   color: "text-tier-bronze",   glow: "neon-glow-bronze",   unlock: "Entry tier. Everyone starts here." },
  { name: "Silver",   color: "text-tier-silver",   glow: "neon-glow-silver",   unlock: "First milestone. Proving you can fight." },
  { name: "Gold",     color: "text-tier-gold",     glow: "neon-glow-gold",     unlock: "Mid-ladder. Season rewards begin." },
  { name: "Diamond",  color: "text-tier-diamond",  glow: "neon-glow-diamond",  unlock: "Top quartile. Real competition starts." },
  { name: "Platinum", color: "text-tier-platinum", glow: "neon-glow-platinum", unlock: "Elite 15%. Harder opponents, better XP." },
  { name: "Champion", color: "text-tier-champion", glow: "neon-glow-champion", unlock: "Top 5%. Seasonal cosmetics unlock." },
  { name: "Unreal",   color: "text-tier-unreal",   glow: "neon-glow-unreal",   unlock: "Top 1%. Name appears on leaderboard." },
  { name: "God",      color: "text-tier-god",      glow: "neon-glow-god",      unlock: "The summit. Rarest rank. Global recognition." },
] as const;

function TheClimb() {
  return (
    <section className="px-6 py-24">
      <div className="max-w-6xl mx-auto">
        <div className="text-center mb-14">
          <p className="text-[11px] font-bold tracking-[0.3em] uppercase text-tier-gold mb-3">The Climb</p>
          <h2 className="text-4xl md:text-6xl font-bold font-display tracking-tight mb-4">
            Eight tiers. One throne.
          </h2>
          <p className="text-muted-foreground max-w-2xl mx-auto">
            Every win moves you up. Every loss costs. Hit Champion to unlock seasonal
            cosmetics. Hit God and your name appears on the global leaderboard.
          </p>
        </div>

        {/* 2-row × 4-col grid on desktop, 4×2 on mobile */}
        <div className="grid grid-cols-4 md:grid-cols-4 gap-3">
          {TIER_DATA.map((t, i) => {
            const isGod = t.name === "God";
            return (
              <motion.div
                key={t.name}
                initial={{ opacity: 0, y: 18 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ delay: i * 0.06, duration: 0.4 }}
                className={`glass-panel p-4 text-center group hover:-translate-y-1 transition-transform relative overflow-hidden ${
                  isGod ? "col-span-2 md:col-span-1 ring-1 ring-tier-god/30" : ""
                }`}
              >
                {isGod && (
                  <div className="absolute inset-0 bg-tier-god/5 pointer-events-none" />
                )}
                <div className={`w-11 h-11 mx-auto mb-3 rounded-full bg-background/40 flex items-center justify-center ${isGod ? "animate-rank-aura" : ""}`}>
                  <Crown className={`w-5 h-5 ${t.color} ${isGod ? "neon-glow-god" : ""}`} />
                </div>
                <p className={`text-[11px] font-bold tracking-widest uppercase mb-2 ${t.color} ${isGod ? "text-glow-god" : ""}`}>
                  {t.name}
                </p>
                <p className="text-[9px] text-muted-foreground leading-relaxed">{t.unlock}</p>
                <p className="text-[8px] font-mono tabular-nums text-muted-foreground/50 mt-1">T{i + 1}</p>
              </motion.div>
            );
          })}
        </div>
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   6. TROPHY ROAD  —  Ecliptar collector grid
   ════════════════════════════════════════════════════════════════════ */

type EcliptarTile = {
  name: string;
  icon: React.ComponentType<{ className?: string }>;
  color: string;
  role: string;
  locked: boolean;
  boss?: boolean;
};

const ECLIPTAR_TILES: EcliptarTile[] = [
  { name: "Velo",       icon: Zap,          color: "text-neon-cyan",     role: "Speedster",   locked: false },
  { name: "Aegis",      icon: Shield,       color: "text-tier-silver",   role: "Tank",        locked: false },
  { name: "Pyre",       icon: Skull,        color: "text-tier-champion", role: "Chud",        locked: false },
  { name: "Luko",       icon: Dice5,        color: "text-tier-gold",     role: "Gambler",     locked: false },
  { name: "Soren",      icon: Heart,        color: "text-neon-pink",     role: "Healer",      locked: true  },
  { name: "Axion",      icon: Scale,        color: "text-neon-purple",   role: "Fulcrum",     locked: true  },
  { name: "Newton",     icon: Trophy,       color: "text-tier-gold",     role: "God · Boss",  locked: true,  boss: true },
  { name: "ECLIPTADON", icon: Crown,        color: "text-tier-god",      role: "God · Boss",  locked: true,  boss: true },
];

function TrophyRoad() {
  return (
    <section className="px-6 py-24 border-y border-border bg-arena-light/40">
      <div className="max-w-6xl mx-auto grid grid-cols-1 lg:grid-cols-12 gap-12 items-center">
        <div className="lg:col-span-5">
          <p className="text-[11px] font-bold tracking-[0.3em] uppercase text-neon-purple mb-3">Trophy Road</p>
          <h2 className="text-4xl md:text-5xl font-bold font-display tracking-tight mb-5">
            Collect what you defeat.
          </h2>
          <p className="text-muted-foreground mb-6 leading-relaxed">
            Win battles. Hit checkpoints. 16 Ecliptars to claim.
            Two only drop from end-game bosses — Newton and ECLIPTADON are not starter unlocks.
          </p>
          <div className="flex flex-wrap gap-2 mb-6 text-[10px] font-bold tracking-widest uppercase">
            <span className="px-2.5 py-1 border border-neon-purple/40 text-neon-purple">16 total Ecliptars</span>
            <span className="px-2.5 py-1 border border-neon-pink/40 text-neon-pink">2 boss-only drops</span>
          </div>
          <Link
            to="/progress"
            className="inline-flex items-center gap-2 px-5 py-3 border border-neon-purple/50 text-neon-purple hover:bg-neon-purple hover:text-background text-xs font-bold tracking-[0.25em] transition-colors"
          >
            VIEW THE ROAD <ChevronRight className="w-3.5 h-3.5" />
          </Link>
        </div>

        <div className="lg:col-span-7 grid grid-cols-4 gap-3">
          {ECLIPTAR_TILES.map((t, i) => {
            const Icon = t.icon;
            return (
              <motion.div
                key={t.name}
                initial={{ opacity: 0, scale: 0.9 }}
                whileInView={{ opacity: 1, scale: 1 }}
                viewport={{ once: true }}
                transition={{ delay: i * 0.05, type: "spring", stiffness: 240, damping: 20 }}
                className={`glass-panel aspect-square flex flex-col items-center justify-center p-3 group hover:-translate-y-1 transition-transform relative overflow-hidden ${
                  t.boss ? "ring-1 ring-tier-god/40" : ""
                }`}
              >
                {t.locked ? (
                  <>
                    <div className="relative">
                      <Icon className={`w-7 h-7 ${t.color} mb-2 opacity-20`} />
                      <Lock className="w-3.5 h-3.5 text-muted-foreground absolute -top-1 -right-1" />
                    </div>
                    <p className="text-[9px] font-bold font-display tracking-wider text-center text-muted-foreground/50">
                      {t.boss ? "BOSS" : "???"}
                    </p>
                    {t.boss && (
                      <p className="text-[8px] uppercase tracking-widest text-tier-god/60 mt-0.5">End-game</p>
                    )}
                  </>
                ) : (
                  <>
                    <Icon className={`w-7 h-7 ${t.color} mb-2 group-hover:scale-110 transition-transform`} />
                    <p className="text-[10px] font-bold font-display tracking-wider text-center">{t.name}</p>
                    <p className="text-[8px] uppercase tracking-widest text-muted-foreground mt-0.5">{t.role}</p>
                    <CheckCircle2 className="w-3 h-3 text-neon-cyan absolute top-1.5 right-1.5 opacity-60" />
                  </>
                )}
              </motion.div>
            );
          })}
        </div>
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   7. DAILY CHALLENGE  —  live countdown to midnight UTC
   ════════════════════════════════════════════════════════════════════ */

function useMidnightCountdown() {
  const [countdown, setCountdown] = useState("--:--:--");

  const tick = useCallback(() => {
    const now = new Date();
    const midnight = new Date(Date.UTC(
      now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1,
    ));
    const diff = Math.max(0, Math.floor((midnight.getTime() - now.getTime()) / 1000));
    const h = Math.floor(diff / 3600).toString().padStart(2, "0");
    const m = Math.floor((diff % 3600) / 60).toString().padStart(2, "0");
    const s = (diff % 60).toString().padStart(2, "0");
    setCountdown(`${h}:${m}:${s}`);
  }, []);

  useEffect(() => {
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, [tick]);

  return countdown;
}

function DailyChallenge() {
  const ch = getTodayChallenge();
  const countdown = useMidnightCountdown();

  return (
    <section className="px-6 py-20">
      <div className="max-w-5xl mx-auto">
        {/* Pulsing neon-pink border */}
        <div className="relative glass-panel p-8 md:p-12 overflow-hidden ring-1 ring-neon-pink/30 animate-battle-charge">
          <div className="absolute -top-20 -right-20 w-72 h-72 bg-neon-pink/20 rounded-full blur-[100px]" />
          <div className="relative grid grid-cols-1 md:grid-cols-3 gap-6 items-center">
            <div className="md:col-span-2">
              <div className="inline-flex items-center gap-2 px-2.5 py-1 border border-neon-pink/40 bg-neon-pink/5 text-neon-pink text-[10px] font-bold tracking-[0.25em] uppercase mb-4">
                <Sparkles className="w-3 h-3" /> Today&apos;s Challenge
              </div>

              <h3 className="text-3xl md:text-4xl font-bold font-display tracking-tight mb-2">{ch.title}</h3>
              <p className="text-muted-foreground mb-4">{ch.goal}</p>

              <div className="flex flex-wrap gap-2 text-[10px] font-bold tracking-widest uppercase mb-4">
                <span className="px-2.5 py-1 border border-neon-cyan/40 text-neon-cyan">+{ch.target} {ch.unit} required</span>
                <span className="px-2.5 py-1 border border-neon-pink/40 text-neon-pink">Reward · {ch.reward}</span>
              </div>

              <div className="flex flex-wrap items-center gap-4 text-[11px] text-muted-foreground">
                {/* Live countdown */}
                <div className="flex items-center gap-1.5">
                  <Timer className="w-3.5 h-3.5 text-neon-pink" />
                  <span>Resets in </span>
                  <span className="font-mono font-bold text-neon-pink tabular-nums">{countdown}</span>
                </div>
                <span className="text-muted-foreground/50">·</span>
                <span className="flex items-center gap-1"><Star className="w-3 h-3 text-tier-gold" /> 341 players accepted today</span>
              </div>
            </div>

            <div className="flex md:justify-end">
              <Link
                to="/battles"
                className="px-7 py-4 bg-neon-pink text-foreground font-bold text-sm tracking-[0.2em] inline-flex items-center gap-2 hover:scale-105 transition-transform animate-battle-charge"
              >
                ACCEPT <ArrowRight className="w-4 h-4" />
              </Link>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   8. TRAINING ROOM  —  Luna / Tests / Courses / Forum
   ════════════════════════════════════════════════════════════════════ */

const TRAINING_TOOLS = [
  {
    icon: Brain,
    label: "Luna",
    tag: "AI Tutor",
    blurb: "Hint-first AI that identifies your gaps before opponents do.",
    to: "/luna" as const,
  },
  {
    icon: Target,
    label: "Adaptive Tests",
    tag: "Practice",
    blurb: "Adaptive questions that branch on every answer.",
    to: "/adaptive-tests" as const,
  },
  {
    icon: GraduationCap,
    label: "Courses",
    tag: "Curriculum",
    blurb: "Structured tracks to build your knowledge base.",
    to: "/certified" as const,
  },
  {
    icon: MessagesSquare,
    label: "Forum",
    tag: "Community",
    blurb: "Stack-Exchange-style threads for every topic.",
    to: "/forum" as const,
  },
] as const;

function TrainingRoom() {
  return (
    <section className="px-6 py-24">
      <div className="max-w-6xl mx-auto">
        <div className="text-center mb-12">
          <p className="text-[11px] font-bold tracking-[0.3em] uppercase text-neon-cyan mb-3">Between Matches</p>
          <h2 className="text-3xl md:text-4xl font-bold font-display tracking-tight mb-3">
            Sharpen the edge.
          </h2>
          <p className="text-muted-foreground max-w-xl mx-auto text-sm">
            What separates ranked players from everyone else isn&apos;t talent — it&apos;s preparation.
          </p>
        </div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          {TRAINING_TOOLS.map((s, i) => {
            const Icon = s.icon;
            return (
              <motion.div
                key={s.label}
                initial={{ opacity: 0, y: 14 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ delay: i * 0.06, duration: 0.4 }}
              >
                <Link
                  to={s.to}
                  className="block glass-panel p-5 h-full hover:border-neon-purple/40 transition-colors group"
                >
                  <Icon className="w-5 h-5 text-neon-purple mb-3 group-hover:scale-110 transition-transform" />
                  <p className="text-[10px] font-bold tracking-widest uppercase text-muted-foreground mb-1">{s.tag}</p>
                  <h3 className="text-sm font-bold font-display tracking-wider mb-2">{s.label}</h3>
                  <p className="text-[11px] text-muted-foreground leading-relaxed">{s.blurb}</p>
                </Link>
              </motion.div>
            );
          })}
        </div>
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   9. FINAL CTA  —  class-select interactive CTA
   ════════════════════════════════════════════════════════════════════ */

const CTA_CLASS_ORDER: (keyof typeof ARCHETYPES)[] = [
  "speedster", "tank", "chud", "gambler", "healer", "fulcrum", "accelerator", "god",
];

function FinalCta() {
  const { isAuthenticated } = useAuth();
  const [hoveredCta, setHoveredCta] = useState<string | null>(null);

  return (
    <section className="px-6 pt-8 pb-24">
      <div className="max-w-5xl mx-auto relative overflow-hidden glass-panel p-10 md:p-16 text-center">
        <div className="absolute -top-20 -right-20 w-72 h-72 bg-neon-pink/25 rounded-full blur-[100px]" />
        <div className="absolute -bottom-20 -left-20 w-72 h-72 bg-neon-purple/25 rounded-full blur-[100px]" />

        <div className="relative">
          <motion.div
            animate={{ rotate: [0, 6, -6, 0] }}
            transition={{ duration: 4, repeat: Infinity, ease: "easeInOut" }}
            className="mx-auto mb-5 w-fit"
          >
            <Swords className="w-9 h-9 text-neon-pink" />
          </motion.div>

          <h2 className="text-4xl md:text-6xl font-bold font-display tracking-tight mb-4">
            The arena is open.
          </h2>
          <p className="text-muted-foreground max-w-xl mx-auto mb-10">
            Free to start. Pick a class, queue up, find out what kind of fighter you are.
          </p>

          {/* 8 class icon tiles */}
          <div className="flex flex-wrap justify-center gap-2 mb-10">
            {CTA_CLASS_ORDER.map((id) => {
              const a = ARCHETYPES[id];
              const Icon = a.icon;
              const isHov = hoveredCta === id;
              return (
                <Link
                  key={id}
                  to={isAuthenticated ? "/battles" : "/signup"}
                  onMouseEnter={() => setHoveredCta(id)}
                  onMouseLeave={() => setHoveredCta(null)}
                  className={`flex flex-col items-center gap-1.5 p-3 border transition-all hover:-translate-y-1 ${
                    isHov ? `${a.borderColor} bg-secondary/40` : "border-border/50 hover:border-border"
                  }`}
                >
                  <Icon className={`w-5 h-5 ${isHov ? a.color : "text-muted-foreground"} transition-colors`} />
                  <span className={`text-[8px] font-bold tracking-widest uppercase ${isHov ? a.color : "text-muted-foreground"} transition-colors`}>
                    {a.name.replace("The ", "")}
                  </span>
                </Link>
              );
            })}
          </div>

          <div className="flex flex-wrap justify-center gap-3">
            {isAuthenticated ? (
              <>
                <Link
                  to="/battles"
                  className="px-8 py-4 bg-neon-pink text-foreground font-bold text-sm tracking-[0.2em] inline-flex items-center gap-2 hover:scale-105 transition-transform animate-battle-charge"
                >
                  <Swords className="w-4 h-4" /> BATTLE NOW <ArrowRight className="w-4 h-4" />
                </Link>
                <Link
                  to="/progress"
                  className="px-7 py-4 border border-border hover:border-neon-purple text-foreground font-bold text-sm tracking-[0.2em] transition-colors"
                >
                  TROPHY ROAD
                </Link>
              </>
            ) : (
              <>
                <Link
                  to="/signup"
                  className="px-8 py-4 bg-neon-pink text-foreground font-bold text-sm tracking-[0.2em] inline-flex items-center gap-2 hover:scale-105 transition-transform animate-battle-charge"
                >
                  <Swords className="w-4 h-4" /> CREATE ACCOUNT <ArrowRight className="w-4 h-4" />
                </Link>
                <Link
                  to="/progress"
                  className="px-7 py-4 border border-border hover:border-neon-purple text-foreground font-bold text-sm tracking-[0.2em] transition-colors"
                >
                  TROPHY ROAD
                </Link>
              </>
            )}
          </div>
        </div>
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   ROOT EXPORT
   ════════════════════════════════════════════════════════════════════ */

export function LandingShowcase() {
  return (
    <>
      <Hero />
      <LiveTicker />
      <GameLoop />
      <ClassPicker />
      <TheClimb />
      <TrophyRoad />
      <DailyChallenge />
      <TrainingRoom />
      <FinalCta />
    </>
  );
}
