import { useEffect, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";

export type Notification = {
  id: string;
  user_id: string;
  actor_id: string | null;
  type: string;
  link: string | null;
  meta: Record<string, unknown>;
  read: boolean;
  created_at: string;
};

/**
 * Lightweight notification feed. Polls every 60s and exposes mutations.
 * Realtime would be nicer, but polling is enough for the current volume
 * and avoids one more channel to maintain.
 */
export function useNotifications() {
  const { user } = useAuth();
  const [items, setItems] = useState<Notification[]>([]);
  const [loading, setLoading] = useState(false);

  const refresh = useCallback(async () => {
    if (!user) { setItems([]); return; }
    setLoading(true);
    const { data } = await supabase
      .from("notifications")
      .select("*")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false })
      .limit(40);
    setItems((data as Notification[]) ?? []);
    setLoading(false);
  }, [user]);

  useEffect(() => {
    refresh();
    if (!user) return;
    const id = setInterval(refresh, 60_000);
    return () => clearInterval(id);
  }, [user, refresh]);

  const unread = items.filter((n) => !n.read).length;

  const markAllRead = async () => {
    if (!user || unread === 0) return;
    await supabase.from("notifications").update({ read: true }).eq("user_id", user.id).eq("read", false);
    setItems((xs) => xs.map((n) => ({ ...n, read: true })));
  };

  const markRead = async (id: string) => {
    await supabase.from("notifications").update({ read: true }).eq("id", id);
    setItems((xs) => xs.map((n) => (n.id === id ? { ...n, read: true } : n)));
  };

  const remove = async (id: string) => {
    await supabase.from("notifications").delete().eq("id", id);
    setItems((xs) => xs.filter((n) => n.id !== id));
  };

  return { items, unread, loading, refresh, markAllRead, markRead, remove };
}