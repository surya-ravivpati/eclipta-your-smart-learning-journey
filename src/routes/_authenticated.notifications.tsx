import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Navbar } from "@/components/Navbar";
import { useNotifications, type Notification } from "@/hooks/use-notifications";
import { Bell, Check, Trash2, MessageSquare, UserPlus, AtSign, MessageCircle, Award, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/_authenticated/notifications")({
  head: () => ({
    meta: [
      { title: "Notifications – Eclipta" },
      { name: "description", content: "Replies, mentions, follows, and accepted answers." },
    ],
  }),
  component: NotificationsPage,
});

function iconFor(type: string) {
  if (type === "follow") return UserPlus;
  if (type === "reply") return MessageSquare;
  if (type === "comment") return MessageCircle;
  if (type === "accepted") return Award;
  if (type.startsWith("mention_")) return AtSign;
  return Bell;
}

function describe(n: Notification): string {
  const meta = n.meta ?? {};
  const author = (meta as { author?: string; username?: string }).author ?? (meta as { username?: string }).username ?? "Someone";
  const title = (meta as { title?: string }).title ?? "";
  switch (n.type) {
    case "follow": return `${author} started following you`;
    case "reply": return `${author} replied to "${title}"`;
    case "comment": return `${author} commented on your answer in "${title}"`;
    case "accepted": return `Your answer was accepted on "${title}"`;
    case "mention_thread": return `${author} mentioned you in "${title}"`;
    case "mention_answer": return `${author} mentioned you in an answer on "${title}"`;
    case "mention_comment": return `${author} mentioned you in a comment on "${title}"`;
    default: return n.type;
  }
}

function timeAgo(iso: string): string {
  const m = Math.floor((Date.now() - +new Date(iso)) / 60000);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h`;
  return `${Math.floor(h / 24)}d`;
}

function NotificationsPage() {
  const { items, unread, loading, markAllRead, markRead, remove } = useNotifications();
  const navigate = useNavigate();

  return (
    <div className="min-h-screen bg-background text-foreground">
      <Navbar />
      <section className="pt-24 pb-16 max-w-3xl mx-auto px-6">
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-3xl font-bold font-display tracking-tight inline-flex items-center gap-2">
            <Bell className="w-6 h-6 text-neon-purple" /> Notifications
            {unread > 0 && (
              <span className="text-[10px] font-bold tracking-widest bg-neon-pink text-foreground px-2 py-0.5">
                {unread} NEW
              </span>
            )}
          </h1>
          {unread > 0 && (
            <button
              onClick={markAllRead}
              className="text-xs font-bold tracking-widest text-neon-purple hover:underline inline-flex items-center gap-1"
            >
              <Check className="w-3 h-3" /> MARK ALL READ
            </button>
          )}
        </div>

        {loading && items.length === 0 ? (
          <div className="flex justify-center py-16"><Loader2 className="w-6 h-6 animate-spin text-neon-purple" /></div>
        ) : items.length === 0 ? (
          <div className="text-center py-16 text-muted-foreground">
            <Bell className="w-8 h-8 mx-auto mb-3 opacity-40" />
            <p className="text-sm">You're all caught up.</p>
          </div>
        ) : (
          <ul className="space-y-2">
            {items.map((n) => {
              const Icon = iconFor(n.type);
              const Body = (
                <div className={cn(
                  "glass-panel p-4 flex items-start gap-3 transition-colors",
                  !n.read && "border-neon-purple/40 bg-neon-purple/5"
                )}>
                  <Icon className="w-4 h-4 mt-0.5 text-neon-purple shrink-0" />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm leading-snug">{describe(n)}</p>
                    <p className="text-[10px] text-muted-foreground mt-1">{timeAgo(n.created_at)}</p>
                  </div>
                  <button
                    onClick={(e) => { e.preventDefault(); e.stopPropagation(); remove(n.id); }}
                    className="text-muted-foreground hover:text-destructive p-1"
                    aria-label="Dismiss"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                </div>
              );
              if (n.link) {
                return (
                  <li key={n.id}>
                    <a
                      href={n.link}
                      onClick={(e) => {
                        e.preventDefault();
                        if (!n.read) markRead(n.id);
                        navigate({ to: n.link as string });
                      }}
                      className="block"
                    >
                      {Body}
                    </a>
                  </li>
                );
              }
              return <li key={n.id}>{Body}</li>;
            })}
          </ul>
        )}
      </section>
    </div>
  );
}