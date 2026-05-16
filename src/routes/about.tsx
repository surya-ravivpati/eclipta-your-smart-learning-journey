import { createFileRoute, Link } from "@tanstack/react-router";
import { motion } from "framer-motion";
import { useState } from "react";
import { toast } from "sonner";
import {
  Sparkles, Target, Swords, Trophy, Brain, Users, User, Mail, Github,
  MessageSquare, Send, CheckCircle2, Loader2, AlertCircle,
} from "lucide-react";
import { supabase } from "@/integrations/supabase/client";

// ─── Contact form ────────────────────────────────────────────────────
// Backed by submit_contact_message RPC (validates, rate-limits, runs through
// moderation, stores in contact_messages). Previously this opened mailto: —
// which silently fell off the rails for any user without a mail client.

interface FieldErrors {
  name?: string;
  email?: string;
  message?: string;
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function ContactForm() {
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [subject, setSubject] = useState("");
  const [message, setMessage] = useState("");
  const [errors, setErrors] = useState<FieldErrors>({});
  const [submitting, setSubmitting] = useState(false);
  const [sent, setSent] = useState(false);

  const validate = (): FieldErrors => {
    const next: FieldErrors = {};
    const n = name.trim(), e = email.trim(), m = message.trim();
    if (n.length < 2)             next.name    = "At least 2 characters.";
    else if (n.length > 80)       next.name    = "Keep it under 80 characters.";
    if (!EMAIL_RE.test(e))        next.email   = "Enter a valid email.";
    if (m.length < 10)            next.message = "Add a bit more detail (10+ characters).";
    else if (m.length > 4000)     next.message = "Trim it under 4000 characters.";
    return next;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (submitting) return;
    const v = validate();
    setErrors(v);
    if (Object.keys(v).length > 0) {
      toast.error("Please fix the highlighted fields.");
      return;
    }

    setSubmitting(true);
    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await supabase.rpc("submit_contact_message" as any, {
        p_name:       name.trim(),
        p_email:      email.trim(),
        p_subject:    subject.trim() || null,
        p_message:    message.trim(),
        p_user_agent: typeof navigator !== "undefined" ? navigator.userAgent : null,
      });
      if (error) {
        toast.error(error.message || "Couldn't send — try again in a moment.");
        return;
      }
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      if ((data as any)?.moderation_status === "hidden") {
        toast.message("Message received — held for review", {
          description: "We'll look at it shortly.",
        });
      } else {
        toast.success("Message sent — we usually reply within 48 hours.");
      }
      setSent(true);
      setName(""); setEmail(""); setSubject(""); setMessage("");
      setErrors({});
    } catch (err) {
      console.error("contact form submit failed", err);
      toast.error("Network hiccup — please try again.");
    } finally {
      setSubmitting(false);
    }
  };

  if (sent) {
    return (
      <div className="glass-panel p-8 border border-neon-cyan/30 text-center">
        <CheckCircle2 className="w-10 h-10 text-neon-cyan mx-auto mb-3" />
        <h3 className="font-bold font-display text-lg mb-2">Message received</h3>
        <p className="text-sm text-muted-foreground max-w-sm mx-auto mb-5">
          Thanks for reaching out. We read everything that lands in the inbox
          and usually reply within 48 hours.
        </p>
        <button
          type="button"
          onClick={() => setSent(false)}
          className="px-4 py-2 text-[11px] font-bold tracking-widest border border-neon-cyan/40 text-neon-cyan hover:bg-neon-cyan/10 transition-colors"
        >
          SEND ANOTHER
        </button>
      </div>
    );
  }

  const onBlur = (field: keyof FieldErrors) => () => {
    const v = validate();
    setErrors((prev) => ({ ...prev, [field]: v[field] }));
  };

  return (
    <form onSubmit={handleSubmit} className="glass-panel p-6 border border-neon-purple/20 space-y-4" noValidate>
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div className="flex items-center gap-2">
          <div className="w-9 h-9 bg-neon-purple/10 border border-neon-purple/40 flex items-center justify-center">
            <Mail className="w-4 h-4 text-neon-purple" />
          </div>
          <div>
            <h3 className="font-bold font-display text-base leading-tight">Send us a message</h3>
            <p className="text-[11px] text-muted-foreground">Goes straight to the team inbox.</p>
          </div>
        </div>
        <span className="text-[10px] text-muted-foreground">Usually replied within 48h</span>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <Field
          label="Name" value={name} onChange={setName} maxLength={80}
          error={errors.name} onBlur={onBlur("name")}
          autoComplete="name" required
        />
        <Field
          label="Email" type="email" value={email} onChange={setEmail} maxLength={120}
          error={errors.email} onBlur={onBlur("email")}
          autoComplete="email" required
        />
      </div>

      <Field
        label="Subject" value={subject} onChange={setSubject} maxLength={120}
        placeholder="What's this about? (optional)"
      />

      <div>
        <label className="text-[10px] font-bold tracking-widest text-muted-foreground uppercase flex items-center justify-between">
          <span>Message <span className="text-neon-pink">*</span></span>
          <span className={message.length > 4000 ? "text-neon-pink" : "text-muted-foreground/70"}>
            {message.length}/4000
          </span>
        </label>
        <textarea
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          onBlur={onBlur("message")}
          rows={6}
          maxLength={4000}
          placeholder="How can we help? Feedback, questions, bug reports — all welcome."
          className={`w-full mt-1 bg-secondary/30 border px-3 py-2 text-sm focus:outline-none focus:ring-1 resize-none transition-colors ${
            errors.message
              ? "border-neon-pink focus:ring-neon-pink"
              : "border-input focus:ring-neon-purple"
          }`}
          required
        />
        {errors.message && (
          <p className="text-[11px] text-neon-pink mt-1 inline-flex items-center gap-1">
            <AlertCircle className="w-3 h-3" />{errors.message}
          </p>
        )}
      </div>

      <div className="flex items-center justify-between gap-3 flex-wrap pt-1">
        <p className="text-[10px] text-muted-foreground">
          By submitting, you agree we may reply to <span className="text-foreground">{email.trim() || "your email"}</span>.
        </p>
        <button
          type="submit"
          disabled={submitting}
          className="px-5 py-2.5 text-xs font-bold tracking-widest bg-neon-purple text-primary-foreground hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed transition-opacity inline-flex items-center gap-2"
        >
          {submitting ? (
            <><Loader2 className="w-3.5 h-3.5 animate-spin" />SENDING…</>
          ) : (
            <><Send className="w-3.5 h-3.5" />SEND MESSAGE</>
          )}
        </button>
      </div>
    </form>
  );
}

function Field({
  label, value, onChange, type = "text", maxLength, placeholder, error, onBlur, autoComplete, required,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  type?: string;
  maxLength?: number;
  placeholder?: string;
  error?: string;
  onBlur?: () => void;
  autoComplete?: string;
  required?: boolean;
}) {
  return (
    <div>
      <label className="text-[10px] font-bold tracking-widest text-muted-foreground uppercase">
        {label} {required && <span className="text-neon-pink">*</span>}
      </label>
      <input
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        onBlur={onBlur}
        maxLength={maxLength}
        placeholder={placeholder}
        autoComplete={autoComplete}
        required={required}
        className={`w-full mt-1 bg-secondary/30 border px-3 py-2 text-sm focus:outline-none focus:ring-1 transition-colors ${
          error
            ? "border-neon-pink focus:ring-neon-pink"
            : "border-input focus:ring-neon-purple"
        }`}
      />
      {error && (
        <p className="text-[11px] text-neon-pink mt-1 inline-flex items-center gap-1">
          <AlertCircle className="w-3 h-3" />{error}
        </p>
      )}
    </div>
  );
}

// ─── Page content ────────────────────────────────────────────────────

const FOUNDERS = [
  {
    name: "Surya Ravipati",
    role: "Co-Founder · Engineering",
    bio: "Architect of Eclipta's adaptive learning engine and the arena that wraps it.",
    initials: "SR",
  },
  {
    name: "Aarit Perswal",
    role: "Co-Founder · Product",
    bio: "Builds the battle systems and gamified progression that make learning addictive.",
    initials: "AP",
  },
];

const PILLARS = [
  { icon: Brain,     title: "Adaptive AI",            desc: "Luna learns your pace, your weak spots, and the way you think — then meets you there." },
  { icon: Swords,    title: "Battles, Not Worksheets", desc: "Knowledge battles turn rote practice into competitive duels with real stakes." },
  { icon: Trophy,    title: "Trophy Road Progression", desc: "Every XP point unlocks new ranks, Ecliptars, and rewards worth claiming." },
  { icon: Target,    title: "Personalized Mastery",   desc: "Adaptive tests and personalized courses target the exact skills you need next." },
  { icon: Users,     title: "Built for Learners",     desc: "Forums, leaderboards, and community challenges keep momentum alive." },
  { icon: Sparkles,  title: "Designed to Delight",    desc: "A neon arena aesthetic that makes you actually want to come back tomorrow." },
];

const STATS = [
  { value: "7",   label: "Archetypes" },
  { value: "8",   label: "Trophy tiers" },
  { value: "AI",  label: "Adaptive tutor" },
  { value: "24/7", label: "Live battles" },
];

export const Route = createFileRoute("/about")({
  head: () => ({
    meta: [
      { title: "About Eclipta – A Smarter Way to Learn" },
      { name: "description", content: "Eclipta turns learning into a battle arena. Meet the team and the mission behind the world's first adaptive learning playground." },
      { property: "og:title", content: "About Eclipta" },
      { property: "og:description", content: "How Eclipta turns learning into a competitive arena powered by AI, battles, and trophy roads." },
    ],
  }),
  component: AboutPage,
});

function AboutPage() {
  return (
    <div className="min-h-screen bg-background text-foreground antialiased">
      <section className="pt-24 pb-20 max-w-5xl mx-auto px-6">
        {/* Hero */}
        <motion.div
          className="text-center mb-14"
          initial={{ opacity: 0, y: 30 }}
          animate={{ opacity: 1, y: 0 }}
        >
          <div className="inline-flex items-center gap-2 px-4 py-1.5 border border-neon-pink/30 bg-neon-pink/10 text-neon-pink text-xs font-bold tracking-widest mb-6">
            <Sparkles className="w-3 h-3" />
            ABOUT ECLIPTA
          </div>
          <h1 className="text-5xl md:text-7xl font-bold font-display tracking-tight mb-5 leading-[1.05]">
            Learning, but make it{" "}
            <span className="text-neon-pink">an arena</span>.
          </h1>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto leading-relaxed">
            Eclipta is the world's first adaptive learning arena. We rebuilt education from the
            ground up — AI-driven growth paths, knowledge battles, and a trophy road that
            actually feels like progress.
          </p>
        </motion.div>

        {/* Stats strip */}
        <motion.div
          className="grid grid-cols-2 md:grid-cols-4 gap-px bg-border/40 border border-border mb-14 overflow-hidden"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
        >
          {STATS.map((s) => (
            <div key={s.label} className="bg-background/60 backdrop-blur px-5 py-5 text-center">
              <div className="text-2xl md:text-3xl font-bold font-display text-neon-cyan tabular-nums">{s.value}</div>
              <div className="text-[10px] font-bold tracking-widest text-muted-foreground mt-1">{s.label.toUpperCase()}</div>
            </div>
          ))}
        </motion.div>

        {/* Mission */}
        <motion.div
          className="glass-panel p-8 md:p-10 mb-14 border border-neon-purple/20"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
        >
          <div className="flex items-center gap-2 mb-3">
            <div className="w-1 h-6 bg-neon-purple" />
            <h2 className="text-2xl font-bold font-display text-neon-purple">Our Mission</h2>
          </div>
          <p className="text-muted-foreground leading-relaxed text-base md:text-lg">
            Traditional learning platforms reward completion. Eclipta rewards{" "}
            <span className="text-foreground font-bold">growth</span>. Every battle you win,
            every course you finish, every adaptive test you crush feeds one progression
            engine — your XP — that unlocks new Ecliptars, ranks, and challenges. Mastery
            should feel like leveling up, not grinding.
          </p>
        </motion.div>

        {/* Pillars */}
        <div className="mb-16">
          <div className="text-center mb-8">
            <p className="text-[10px] font-bold tracking-widest text-neon-cyan mb-2">WHAT MAKES ECLIPTA</p>
            <h2 className="text-3xl font-bold font-display tracking-tight">Six pillars, one arena</h2>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {PILLARS.map((p, i) => {
              const Icon = p.icon;
              return (
                <motion.div
                  key={p.title}
                  className="glass-panel p-6 border border-border hover:border-neon-purple/40 hover:bg-neon-purple/[0.02] transition-colors group"
                  initial={{ opacity: 0, y: 20 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={{ once: true }}
                  transition={{ delay: i * 0.05 }}
                >
                  <div className="w-10 h-10 mb-4 bg-neon-purple/10 border border-neon-purple/30 flex items-center justify-center group-hover:bg-neon-purple/20 transition-colors">
                    <Icon className="w-5 h-5 text-neon-purple" />
                  </div>
                  <h3 className="font-bold font-display text-lg mb-2 leading-tight">{p.title}</h3>
                  <p className="text-sm text-muted-foreground leading-relaxed">{p.desc}</p>
                </motion.div>
              );
            })}
          </div>
        </div>

        {/* Founders */}
        <motion.div
          className="mb-16"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
        >
          <div className="text-center mb-8">
            <p className="text-[10px] font-bold tracking-widest text-neon-cyan mb-2">THE TEAM</p>
            <h2 className="text-3xl font-bold font-display tracking-tight">Meet the founders</h2>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {FOUNDERS.map((f, i) => (
              <motion.div
                key={f.name}
                className="glass-panel p-6 border border-neon-cyan/20 hover:border-neon-cyan/50 transition-colors flex items-start gap-4"
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ delay: i * 0.1 }}
              >
                <div className="w-16 h-16 shrink-0 bg-neon-cyan/10 border border-neon-cyan/40 flex items-center justify-center text-neon-cyan font-bold font-display text-lg tracking-wider">
                  {f.initials}
                </div>
                <div className="min-w-0">
                  <h3 className="font-bold font-display text-lg leading-tight">{f.name}</h3>
                  <p className="text-[10px] font-bold tracking-widest text-neon-cyan mt-1 mb-2">{f.role.toUpperCase()}</p>
                  <p className="text-sm text-muted-foreground leading-relaxed">{f.bio}</p>
                </div>
              </motion.div>
            ))}
          </div>
        </motion.div>

        {/* Contact */}
        <motion.div
          id="contact"
          className="mb-16 scroll-mt-24"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
        >
          <div className="text-center mb-8">
            <p className="text-[10px] font-bold tracking-widest text-neon-purple mb-2">CONTACT</p>
            <h2 className="text-3xl font-bold font-display tracking-tight">Get in touch</h2>
            <p className="text-sm text-muted-foreground mt-2 max-w-xl mx-auto">
              Questions, feedback, bug reports, or just want to say hi — pick the channel that fits.
            </p>
          </div>
          <div className="grid grid-cols-1 lg:grid-cols-[1fr_320px] gap-4">
            <ContactForm />
            <div className="grid gap-3 content-start">
              <Link
                to="/forum"
                className="glass-panel p-5 border border-neon-pink/20 hover:border-neon-pink/50 hover:bg-neon-pink/[0.02] transition-colors group block"
              >
                <MessageSquare className="w-5 h-5 text-neon-pink mb-2 group-hover:scale-110 transition-transform" />
                <h3 className="font-bold font-display text-sm mb-1">Community Forum</h3>
                <p className="text-xs text-muted-foreground leading-snug">Best for product questions and learner support.</p>
              </Link>
              <a
                href="mailto:hello@eclipta.app"
                className="glass-panel p-5 border border-neon-purple/20 hover:border-neon-purple/50 hover:bg-neon-purple/[0.02] transition-colors group block"
              >
                <Mail className="w-5 h-5 text-neon-purple mb-2 group-hover:scale-110 transition-transform" />
                <h3 className="font-bold font-display text-sm mb-1">Direct Email</h3>
                <p className="text-xs text-muted-foreground leading-snug break-all">hello@eclipta.app</p>
              </a>
              <a
                href="https://github.com"
                target="_blank"
                rel="noopener noreferrer"
                className="glass-panel p-5 border border-neon-cyan/20 hover:border-neon-cyan/50 hover:bg-neon-cyan/[0.02] transition-colors group block"
              >
                <Github className="w-5 h-5 text-neon-cyan mb-2 group-hover:scale-110 transition-transform" />
                <h3 className="font-bold font-display text-sm mb-1">Open Source</h3>
                <p className="text-xs text-muted-foreground leading-snug">Report bugs, suggest features, or contribute.</p>
              </a>
            </div>
          </div>
        </motion.div>

        {/* CTA */}
        <motion.div
          className="text-center glass-panel p-10 md:p-12 border border-neon-pink/20 relative overflow-hidden"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
        >
          <div className="absolute inset-0 bg-gradient-to-br from-neon-pink/5 via-transparent to-neon-purple/5 pointer-events-none" />
          <div className="relative">
            <h2 className="text-3xl md:text-4xl font-bold font-display mb-3 leading-tight">Ready to enter the arena?</h2>
            <p className="text-muted-foreground mb-7 max-w-md mx-auto">
              Pick an archetype, claim your first Ecliptar, and start climbing the Trophy Road.
            </p>
            <div className="flex gap-3 justify-center flex-wrap">
              <Link
                to="/signup"
                className="px-6 py-3 bg-neon-pink text-primary-foreground text-xs font-bold tracking-widest hover:opacity-90 transition-opacity"
              >
                CREATE ACCOUNT
              </Link>
              <Link
                to="/"
                className="px-6 py-3 border border-border text-xs font-bold tracking-widest hover:border-neon-purple transition-colors"
              >
                EXPLORE FIRST
              </Link>
            </div>
          </div>
        </motion.div>
      </section>
    </div>
  );
}
