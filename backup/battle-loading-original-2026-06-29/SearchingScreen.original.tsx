/**
 * ORIGINAL battle loading / "searching for opponent" screen — captured verbatim
 * before the cinematic redesign (2026-06-29). This is the exact JSX that lived
 * in the `phase === "searching"` branch of src/components/KnowledgeBattles.tsx.
 *
 * To restore: paste this block back into that branch (replacing <BattleIntro/>),
 * or restore the full files in this folder (see RESTORE.md). Requires the
 * imports: motion (framer-motion); Users, Ghost, Bot, Target (lucide-react);
 * ARCHETYPES; and the component state `archetype`, `matchTier`, `matchStatus`.
 */

// if (phase === "searching") {
//   const arch = ARCHETYPES[archetype];
//   const tierConfig = {
//     live:  { label: "LIVE PvP",    icon: Users,  color: "text-neon-cyan",    glow: "border-neon-cyan/60"    },
//     ghost: { label: "GHOST",       icon: Ghost,  color: "text-neon-purple",  glow: "border-neon-purple/60"  },
//     bot:   { label: "AI BOT",      icon: Bot,    color: "text-muted-foreground", glow: "border-border"      },
//   } as const;
//   return (
//     <motion.div className="btt-card text-center py-16 px-10" initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
//       <motion.div
//         className="w-20 h-20 mx-auto mb-8 border flex items-center justify-center"
//         animate={{
//           borderColor: ["oklch(0.60 0.17 255)", "oklch(0.58 0.17 252)", "oklch(0.78 0.13 88)", "oklch(0.60 0.17 255)"],
//           rotate: 360,
//         }}
//         transition={{ duration: 2, repeat: Infinity, ease: "linear" }}
//       >
//         <Target className="w-8 h-8 text-neon-pink" />
//       </motion.div>
//
//       <h3 className="btt-shout text-4xl mb-2">Finding an opponent…</h3>
//       <p className={`inline-flex items-center gap-1 text-xs font-bold ${arch.color} mb-6`}>
//         <arch.icon className="w-3.5 h-3.5" /> {arch.name}
//       </p>
//
//       {/* Tier priority indicator */}
//       <div className="flex items-center justify-center gap-2 mb-4">
//         {(["live", "ghost", "bot"] as const).map((tier, i) => {
//           const cfg     = tierConfig[tier];
//           const Icon    = cfg.icon;
//           const active  = matchTier === tier;
//           const passed  = (["live", "ghost", "bot"] as const).indexOf(matchTier) > i;
//           return (
//             <div key={tier} className="flex items-center gap-2">
//               <motion.div
//                 className={`flex items-center gap-1 px-2 py-1 border text-[10px] font-bold tracking-widest transition-all ${
//                   active  ? `${cfg.color} ${cfg.glow} bg-white/5` :
//                   passed  ? "text-primary border-primary/40 bg-primary/5" :
//                             "text-muted-foreground/30 border-border/30"
//                 }`}
//                 animate={active ? { opacity: [0.7, 1, 0.7] } : {}}
//                 transition={{ repeat: Infinity, duration: 1.2 }}
//               >
//                 <Icon className="w-3 h-3" />
//                 {cfg.label}
//               </motion.div>
//               {i < 2 && <span className="text-muted-foreground/30 text-xs">→</span>}
//             </div>
//           );
//         })}
//       </div>
//
//       <p className="text-xs text-muted-foreground tabular-nums">{matchStatus}</p>
//       <motion.div className="flex justify-center gap-1 mt-4" animate={{ opacity: [0.3, 1, 0.3] }} transition={{ duration: 1.5, repeat: Infinity }}>
//         {[0, 1, 2].map(i => <div key={i} className="w-2 h-2 bg-neon-pink rounded-full" />)}
//       </motion.div>
//     </motion.div>
//   );
// }
