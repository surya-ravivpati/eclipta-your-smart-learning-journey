import { motion } from "framer-motion";
import { Link } from "@tanstack/react-router";
import { useAuth } from "@/hooks/use-auth";
import heroImage from "@/assets/hero-arena.jpg";

export function HeroSection() {
  const { isAuthenticated } = useAuth();
  const ctaTo = isAuthenticated ? "/battles" : "/signup";
  return (
    <section className="pt-32 pb-20 px-6 relative overflow-hidden">
      {/* Ambient glow */}
      <div className="absolute top-[-10%] right-[-10%] w-96 h-96 bg-neon-purple/20 rounded-full blur-[120px] animate-pulse" />
      <div className="absolute bottom-[10%] left-[-5%] w-80 h-80 bg-neon-pink/10 rounded-full blur-[100px]" />

      <div className="max-w-7xl mx-auto grid grid-cols-1 lg:grid-cols-12 gap-12 items-center relative">
        <motion.div
          className="lg:col-span-7"
          initial={{ opacity: 0, y: 30 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7 }}
        >
          <div className="inline-block px-3 py-1 mb-6 border border-neon-pink/50 text-neon-pink text-[10px] font-bold tracking-[0.2em] uppercase">
            Season 01: The Awakening
          </div>
          <h1 className="text-7xl md:text-8xl font-bold tracking-tighter leading-[0.9] mb-8 font-display">
            LEARN AT <br />
            <span className="text-neon-purple">
              VELOCITY.
            </span>
          </h1>
          <p className="max-w-[45ch] text-lg text-muted-foreground mb-10 leading-relaxed">
            The world's first adaptive learning arena. Master complex disciplines through
            AI-driven growth paths, high-stakes battles, and personalized courses.
          </p>
          <div className="flex flex-wrap gap-4">
            <Link
              to={ctaTo}
              className="px-8 py-4 bg-neon-pink text-foreground font-bold text-sm tracking-widest flex items-center gap-3 group transition-all hover:scale-105 neon-glow-pink"
            >
              START YOUR ASCENT
              <span className="group-hover:translate-x-1 transition-transform">→</span>
            </Link>
            <Link
              to="/about"
              className="px-8 py-4 border border-border hover:border-neon-purple text-foreground font-bold text-sm tracking-widest flex items-center gap-3 transition-colors"
            >
              LEARN MORE
            </Link>
          </div>
        </motion.div>

        {/* Featured Duel Card */}
        <motion.div
          className="lg:col-span-5 relative"
          initial={{ opacity: 0, x: 40 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.7, delay: 0.2 }}
        >
          <div className="absolute -inset-1 bg-gradient-to-tr from-neon-purple/20 to-neon-pink/20 blur-2xl opacity-50" />
          <div className="relative glass-panel p-8">
            <div className="flex justify-between items-end mb-10">
              <div>
                <p className="text-[10px] tracking-widest text-neon-pink mb-1 uppercase font-bold">Today's Featured Duel</p>
                <h3 className="text-2xl font-bold font-display">Mental Math Arena</h3>
              </div>
              <div className="text-right">
                <p className="text-2xl font-bold tabular-nums text-neon-purple">3 ★</p>
                <p className="text-[10px] tracking-widest text-muted-foreground font-bold uppercase">Difficulty</p>
              </div>
            </div>

            <div className="space-y-4 mb-8">
              <div className="flex items-center justify-between text-xs border-b border-border/50 pb-3">
                <span className="text-muted-foreground uppercase tracking-widest font-bold text-[10px]">Format</span>
                <span className="font-bold">1v1 · Best of 5</span>
              </div>
              <div className="flex items-center justify-between text-xs border-b border-border/50 pb-3">
                <span className="text-muted-foreground uppercase tracking-widest font-bold text-[10px]">Topics</span>
                <span className="font-bold">Algebra · Fractions · Exponents</span>
              </div>
              <div className="flex items-center justify-between text-xs">
                <span className="text-muted-foreground uppercase tracking-widest font-bold text-[10px]">Reward</span>
                <span className="font-bold text-neon-cyan">+150 XP · Ecliptar Shard</span>
              </div>
            </div>

            <Link
              to="/battles"
              className="block w-full py-4 text-center bg-neon-purple/10 border border-neon-purple text-neon-purple text-xs font-bold tracking-widest hover:bg-neon-purple hover:text-background transition-all"
            >
              START THIS BATTLE →
            </Link>
          </div>
        </motion.div>
      </div>

      {/* Hero Image */}
      <motion.div
        className="max-w-7xl mx-auto mt-20 relative"
        initial={{ opacity: 0, y: 40 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.8, delay: 0.4 }}
      >
        <div className="absolute -inset-2 bg-gradient-to-r from-neon-purple/20 to-neon-pink/10 blur-3xl opacity-40" />
        <div className="relative border border-border rounded-xl overflow-hidden">
          <img src={heroImage} alt="Eclipta Arena" className="w-full aspect-video object-cover opacity-70" width={1920} height={1080} />
          <div className="absolute inset-0 bg-gradient-to-t from-background via-transparent to-transparent" />
        </div>
      </motion.div>
    </section>
  );
}
