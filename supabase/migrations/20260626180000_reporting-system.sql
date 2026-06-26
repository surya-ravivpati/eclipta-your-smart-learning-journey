-- ════════════════════════════════════════════════════════════════════════
-- Verified, auto-acting reporting backend.
--
-- Core principle: a report is a TRIGGER FOR RE-EVALUATION, never a decision.
-- A report causes the existing moderation pipeline to re-scan the target at
-- higher priority; only the pipeline's own independent verdict acts. Reports
-- NEVER remove content by count — that is the brigading vector this design
-- exists to prevent.
--
-- Unifies forum + username + study-room-chat reporting into ONE backend
-- (the per-surface forum_reports / study_room_reports flows are superseded;
-- the forum's count-based auto-hide is retired below).
--
-- Idempotent. Depends on the moderation-unified migration (moderation_config,
-- moderation_decisions, review_queue, apply_moderation_outcome).
-- ════════════════════════════════════════════════════════════════════════

-- ── Config — all reporting thresholds live here, tunable without code ──────
INSERT INTO public.moderation_config(key, value, notes) VALUES
  ('reporting', jsonb_build_object(
     'rescan_dedupe_seconds', 60,        -- one re-scan per content-state window
     'report_rate_per_hour', 20,         -- per-reporter intake rate limit
     'escalate_high_trust_count', 2,     -- this many high-trust reporters on
                                         -- pipeline-CLEAN content → human review
     'high_trust_min_reports', 3,        -- a reporter counts as "high trust" once
     'high_trust_min_ratio', 0.5,        --   they have ≥N reports and ≥this confirmed ratio
     'trust_window_hours', 720,          -- rolling window for the trust signal (30d)
     'brigade_unconfirmed_count', 4,     -- this many unconfirmed reports by one
     'brigade_window_hours', 168         --   reporter vs one target → abuse signal
   ), 'Reporting thresholds. Product-tunable; no code change needed.')
ON CONFLICT (key) DO NOTHING;

-- ── apply_moderation_outcome: now also returns the decision row id so a report
--    can link to the exact moderation_decisions record it triggered. ────────
CREATE OR REPLACE FUNCTION public.apply_moderation_outcome(
  p_surface text, p_target_type text, p_content_ref uuid, p_author uuid,
  p_decision text, p_category text, p_confidence integer, p_layers text[],
  p_self_harm boolean, p_severity integer, p_snapshot text, p_needs_rescan boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cfg jsonb := public.moderation_cfg('repeat_offender');
  v_severe text[]; v_count integer; v_until timestamptz := NULL; v_paused boolean := false;
  v_decision_id uuid;
BEGIN
  INSERT INTO public.moderation_decisions(surface_type, target_type, content_ref, author_id,
            decision, category, confidence, layers, self_harm)
  VALUES (p_surface, p_target_type, p_content_ref, p_author,
          p_decision, p_category, p_confidence, coalesce(p_layers,'{}'), coalesce(p_self_harm,false))
  RETURNING id INTO v_decision_id;

  IF coalesce(p_self_harm, false) THEN
    INSERT INTO public.wellbeing_alerts(user_id, surface_type, content_ref, snapshot)
    VALUES (p_author, p_surface, p_content_ref, left(coalesce(p_snapshot,''), 1000));
  END IF;

  IF p_decision = 'flag' THEN
    INSERT INTO public.review_queue(surface_type, target_type, content_ref, author_id,
              snapshot, category, confidence, severity)
    VALUES (p_surface, p_target_type, p_content_ref, p_author,
            left(coalesce(p_snapshot,''), 2000), p_category, coalesce(p_confidence,0), coalesce(p_severity,0));
  END IF;

  IF coalesce(p_needs_rescan, false) THEN
    INSERT INTO public.moderation_rescan_queue(surface_type, target_type, content_ref, snapshot, author_id)
    VALUES (p_surface, p_target_type, p_content_ref, left(coalesce(p_snapshot,''), 4000), p_author);
  END IF;

  IF p_decision IN ('block','flag') AND p_category IS NOT NULL THEN
    SELECT array_agg(cat) INTO v_severe
      FROM jsonb_array_elements_text(coalesce(v_cfg->'severe_categories','[]'::jsonb)) AS t(cat);
    IF p_category = ANY(coalesce(v_severe,'{}')) AND p_author IS NOT NULL THEN
      SELECT count(*) INTO v_count FROM public.moderation_decisions
       WHERE author_id = p_author AND decision IN ('block','flag') AND category = ANY(v_severe)
         AND created_at > now() - make_interval(hours => COALESCE((v_cfg->>'window_hours')::int,168));
      IF v_count >= COALESCE((v_cfg->>'severe_count')::int, 3)
         AND public.is_posting_paused(p_author) IS NULL THEN
        v_until := now() + make_interval(hours => COALESCE((v_cfg->>'pause_hours')::int, 24));
        INSERT INTO public.user_posting_pauses(user_id, until, reason)
        VALUES (p_author, v_until, 'Auto soft-pause: ' || v_count || ' severe violations in window — pending human review.');
        v_paused := true;
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object('paused', v_paused, 'pause_until', v_until, 'decision_id', v_decision_id);
END; $$;
REVOKE ALL ON FUNCTION public.apply_moderation_outcome(text,text,uuid,uuid,text,text,integer,text[],boolean,integer,text,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_moderation_outcome(text,text,uuid,uuid,text,text,integer,text[],boolean,integer,text,boolean) TO service_role;

-- ── Unified reports table (every surface, one backend) ─────────────────────
CREATE TABLE IF NOT EXISTS public.reports (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id   uuid NOT NULL,
  target_type   text NOT NULL CHECK (target_type IN ('thread','answer','comment','username','chat_message')),
  target_id     uuid,                          -- null for AI/system-authored content with no row
  target_author uuid,                          -- resolved content author (trust/brigade analysis)
  category      text,
  note          text,
  status        text NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending','scanning','action_taken','no_violation','escalated','target_gone','closed')),
  confirmed     boolean,                        -- re-scan result: true=violation confirmed, false=clean, null=pending/gone
  decision_id   uuid REFERENCES public.moderation_decisions(id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  processed_at  timestamptz
);
-- One OPEN report per reporter per target (re-reporting refreshes it). Partial
-- unique so closed/historical rows don't block a later genuine re-report.
CREATE UNIQUE INDEX IF NOT EXISTS uq_reports_open
  ON public.reports(reporter_id, target_type, target_id)
  WHERE status IN ('pending','scanning');
CREATE INDEX IF NOT EXISTS idx_reports_target ON public.reports(target_type, target_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reports_reporter ON public.reports(reporter_id, created_at DESC);
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- Reporter sees ONLY their own reports (for the generic outcome state); mods see all.
DROP POLICY IF EXISTS "reporter sees own reports" ON public.reports;
CREATE POLICY "reporter sees own reports" ON public.reports FOR SELECT TO authenticated
  USING (reporter_id = auth.uid()
         OR public.has_role(auth.uid(),'moderator') OR public.has_role(auth.uid(),'admin'));
-- All writes go through SECURITY DEFINER RPCs; no direct client writes.

-- ── Reporter trust — DERIVED from confirmed/unconfirmed reports (no drift) ──
CREATE OR REPLACE VIEW public.reporter_trust AS
  SELECT reporter_id,
         count(*) FILTER (WHERE confirmed IS TRUE)  AS confirmed,
         count(*) FILTER (WHERE confirmed IS FALSE) AS unconfirmed,
         count(*) FILTER (WHERE confirmed IS NOT NULL) AS resolved,
         max(created_at) AS last_report_at
    FROM public.reports
   WHERE created_at > now() - make_interval(hours =>
           COALESCE((public.moderation_cfg('reporting')->>'trust_window_hours')::int, 720))
   GROUP BY reporter_id;

-- A reporter is "high trust" once they have enough resolved reports AND a
-- confirmed ratio at/above the configured floor. New reporters are neutral
-- (treated as high-trust by default so genuine first-time reports still count).
CREATE OR REPLACE FUNCTION public.reporter_is_high_trust(p_user uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cfg jsonb := public.moderation_cfg('reporting');
  v_min int := COALESCE((v_cfg->>'high_trust_min_reports')::int, 3);
  v_ratio numeric := COALESCE((v_cfg->>'high_trust_min_ratio')::numeric, 0.5);
  v_conf int; v_resolved int;
BEGIN
  SELECT confirmed, resolved INTO v_conf, v_resolved FROM public.reporter_trust WHERE reporter_id = p_user;
  IF v_resolved IS NULL OR v_resolved < v_min THEN RETURN true; END IF;  -- not enough history → neutral/trusted
  RETURN (v_conf::numeric / NULLIF(v_resolved,0)) >= v_ratio;
END; $$;
GRANT EXECUTE ON FUNCTION public.reporter_is_high_trust(uuid) TO authenticated, service_role;
GRANT SELECT ON public.reporter_trust TO authenticated;   -- RLS on base reports still gates rows

-- Resolve a target's author + whether it still exists, across surfaces.
CREATE OR REPLACE FUNCTION public.report_target_author(p_target_type text, p_target_id uuid)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_author uuid;
BEGIN
  IF p_target_id IS NULL THEN RETURN NULL; END IF;
  IF    p_target_type = 'thread'       THEN SELECT user_id INTO v_author FROM public.forum_threads  WHERE id = p_target_id;
  ELSIF p_target_type = 'answer'       THEN SELECT user_id INTO v_author FROM public.forum_answers  WHERE id = p_target_id;
  ELSIF p_target_type = 'comment'      THEN SELECT user_id INTO v_author FROM public.forum_comments WHERE id = p_target_id;
  ELSIF p_target_type = 'chat_message' THEN SELECT user_id INTO v_author FROM public.study_room_messages WHERE id = p_target_id;
  ELSIF p_target_type = 'username'     THEN v_author := p_target_id;   -- username target_id IS the user
  END IF;
  RETURN v_author;
END; $$;
GRANT EXECUTE ON FUNCTION public.report_target_author(text, uuid) TO service_role;

-- ── submit_report — persist + dedupe re-scan trigger (logs EVERY report) ───
CREATE OR REPLACE FUNCTION public.submit_report(
  p_target_type text, p_target_id uuid, p_category text, p_note text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_cfg jsonb := public.moderation_cfg('reporting');
  v_dedupe int := COALESCE((v_cfg->>'rescan_dedupe_seconds')::int, 60);
  v_recent int; v_author uuid; v_report_id uuid;
  v_recent_processed boolean; v_inflight boolean; v_need_rescan boolean;
  v_prev record;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_target_type NOT IN ('thread','answer','comment','username','chat_message') THEN
    RAISE EXCEPTION 'Invalid target type'; END IF;

  SELECT count(*) INTO v_recent FROM public.reports
   WHERE reporter_id = v_uid AND created_at > now() - interval '1 hour';
  IF v_recent >= COALESCE((v_cfg->>'report_rate_per_hour')::int, 20) THEN
    RAISE EXCEPTION 'You are reporting too fast. Try again later.'; END IF;

  v_author := public.report_target_author(p_target_type, p_target_id);

  -- Serialize concurrent reports on the SAME target so exactly one claims the
  -- re-scan (the "10 simultaneous reports → one re-scan" guarantee).
  PERFORM pg_advisory_xact_lock(hashtext(p_target_type || ':' || coalesce(p_target_id::text, '')));

  -- A scan is redundant if one just completed (within the window) or is in
  -- flight (a fresh 'scanning' report exists).
  SELECT EXISTS (SELECT 1 FROM public.reports
                  WHERE target_type = p_target_type AND target_id IS NOT DISTINCT FROM p_target_id
                    AND processed_at > now() - make_interval(secs => v_dedupe)) INTO v_recent_processed;
  SELECT EXISTS (SELECT 1 FROM public.reports
                  WHERE target_type = p_target_type AND target_id IS NOT DISTINCT FROM p_target_id
                    AND status = 'scanning' AND created_at > now() - interval '2 minutes') INTO v_inflight;
  v_need_rescan := NOT v_recent_processed AND NOT v_inflight;

  -- Upsert the reporter's open report. The scan claimer marks it 'scanning'.
  INSERT INTO public.reports(reporter_id, target_type, target_id, target_author, category, note, status)
  VALUES (v_uid, p_target_type, p_target_id, v_author, left(coalesce(p_category,''),60),
          nullif(left(coalesce(p_note,''),1000),''),
          CASE WHEN v_need_rescan THEN 'scanning' ELSE 'pending' END)
  ON CONFLICT (reporter_id, target_type, target_id) WHERE status IN ('pending','scanning')
  DO UPDATE SET category = EXCLUDED.category, note = EXCLUDED.note, created_at = now(),
                status = CASE WHEN v_need_rescan THEN 'scanning' ELSE reports.status END
  RETURNING id INTO v_report_id;

  -- If a scan ALREADY completed in-window, the just-run apply_report_outcome
  -- won't see this new row — inherit that outcome now so the report still
  -- closes with a generic status. (An in-flight scan WILL catch a 'pending' row.)
  IF v_recent_processed AND NOT v_inflight THEN
    SELECT status, confirmed, decision_id INTO v_prev
      FROM public.reports
     WHERE target_type = p_target_type AND target_id IS NOT DISTINCT FROM p_target_id
       AND processed_at IS NOT NULL AND id <> v_report_id
     ORDER BY processed_at DESC LIMIT 1;
    IF FOUND THEN
      UPDATE public.reports
         SET status = v_prev.status, confirmed = v_prev.confirmed,
             decision_id = v_prev.decision_id, processed_at = now()
       WHERE id = v_report_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'report_id', v_report_id,
    'need_rescan', v_need_rescan,
    'target_exists', (v_author IS NOT NULL OR p_target_id IS NULL)
  );
END; $$;
GRANT EXECUTE ON FUNCTION public.submit_report(text, uuid, text, text) TO authenticated;

-- ── mark_report_target_gone — graceful close when content vanished ─────────
CREATE OR REPLACE FUNCTION public.mark_report_target_gone(p_target_type text, p_target_id uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.reports SET status = 'target_gone', processed_at = now()
   WHERE target_type = p_target_type AND target_id IS NOT DISTINCT FROM p_target_id
     AND status IN ('pending','scanning');
$$;
GRANT EXECUTE ON FUNCTION public.mark_report_target_gone(text, uuid) TO service_role;

-- ── apply_report_outcome — the verified, trust-weighted action logic ───────
-- Called by the report edge AFTER the pipeline re-scan. Links the decision to
-- every open report on the target, records confirmed/unconfirmed, and decides
-- between auto-action (pipeline already acted), escalation, or quiet close —
-- never removing content by report count.
CREATE OR REPLACE FUNCTION public.apply_report_outcome(
  p_target_type text, p_target_id uuid, p_target_author uuid,
  p_decision text, p_category text, p_confidence integer, p_decision_id uuid, p_snapshot text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cfg jsonb := public.moderation_cfg('reporting');
  v_confirmed boolean := p_decision IN ('block','flag');
  v_high_trust int; v_status text; v_escalate boolean := false;
  r record;
BEGIN
  IF v_confirmed THEN
    -- The pipeline acted on its own findings — that IS the action a report
    -- unlocks. Reporters who flagged it are confirmed.
    v_status := 'action_taken';
  ELSE
    -- Pipeline found nothing. Count DISTINCT high-trust reporters on this target;
    -- enough of them on clean content → escalate to a human (gray zone), but
    -- NEVER auto-remove.
    SELECT count(DISTINCT reporter_id) INTO v_high_trust
      FROM public.reports
     WHERE target_type = p_target_type AND target_id IS NOT DISTINCT FROM p_target_id
       AND status IN ('pending','scanning')
       AND public.reporter_is_high_trust(reporter_id);
    v_escalate := v_high_trust >= COALESCE((v_cfg->>'escalate_high_trust_count')::int, 2);
    v_status := CASE WHEN v_escalate THEN 'escalated' ELSE 'no_violation' END;
  END IF;

  -- Link + close every open report on this target with the SAME outcome.
  UPDATE public.reports
     SET confirmed = v_confirmed, decision_id = p_decision_id,
         status = v_status, processed_at = now()
   WHERE target_type = p_target_type AND target_id IS NOT DISTINCT FROM p_target_id
     AND status IN ('pending','scanning');

  -- Make the pipeline's action real on a chat message it now BLOCKS (the edge
  -- already applies row visibility for forum rows; chat has no such hook).
  -- 'flag' deliberately leaves chat visible — flagged chat posts normally and
  -- is handled via the review queue, per the moderation spec.
  IF p_decision = 'block' AND p_target_type = 'chat_message' AND p_target_id IS NOT NULL THEN
    UPDATE public.study_room_messages
       SET moderation_status = 'removed', moderation_category = p_category,
           moderation_reason = 'Removed after review'
     WHERE id = p_target_id;
  END IF;

  -- Escalation → priority human review queue (not a removal).
  IF v_escalate THEN
    INSERT INTO public.review_queue(surface_type, target_type, content_ref, author_id,
              snapshot, category, confidence, severity)
    VALUES ('report', p_target_type, p_target_id, p_target_author,
            left(coalesce(p_snapshot,''),2000), 'report_escalation', coalesce(p_confidence,0), 6);
  END IF;

  -- Brigade / harassment-by-reporting signal: a reporter with many unconfirmed
  -- reports against the SAME target author over the window → surface for review.
  IF NOT v_confirmed AND p_target_author IS NOT NULL THEN
    FOR r IN
      SELECT reporter_id, count(*) AS n
        FROM public.reports
       WHERE target_author = p_target_author AND confirmed IS FALSE
         AND created_at > now() - make_interval(hours => COALESCE((v_cfg->>'brigade_window_hours')::int,168))
       GROUP BY reporter_id
      HAVING count(*) >= COALESCE((v_cfg->>'brigade_unconfirmed_count')::int, 4)
    LOOP
      -- One open abuse signal per (reporter → target author) at a time.
      IF NOT EXISTS (
        SELECT 1 FROM public.review_queue
         WHERE category = 'reporting_abuse' AND status = 'pending'
           AND content_ref = r.reporter_id AND author_id = p_target_author
      ) THEN
        INSERT INTO public.review_queue(surface_type, target_type, content_ref, author_id,
                  snapshot, category, confidence, severity)
        VALUES ('report', 'reporter', r.reporter_id, p_target_author,
                'Possible reporting abuse: ' || r.n || ' unconfirmed reports against the same user.',
                'reporting_abuse', 0, 7);
      END IF;
    END LOOP;
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.apply_report_outcome(text,text,text,uuid,text,text,integer,uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_report_outcome(text,uuid,uuid,text,text,integer,uuid,text) TO service_role;

-- Retire the forum's count-based auto-hide: reports must never remove content
-- on their own. submit_forum_report becomes a thin shim into the unified
-- reports table (no report_count bump, no auto-hide). Existing callers keep
-- working; the verified re-scan flow is what acts now.
CREATE OR REPLACE FUNCTION public.submit_forum_report(
  p_target_type text, p_target_id uuid, p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_res jsonb;
BEGIN
  v_res := public.submit_report(p_target_type, p_target_id, 'reported', p_reason);
  RETURN jsonb_build_object('ok', true, 'deduplicated', false,
                            'auto_hidden', false, 'report_id', v_res->'report_id');
END; $$;

NOTIFY pgrst, 'reload schema';
