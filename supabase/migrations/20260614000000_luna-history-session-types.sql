-- Fix: learning_history.session_type CHECK only allowed
-- ('chat','battle','test','course'), but the app inserts 'luna-session'
-- (full Luna surface) and 'adaptive_test' (adaptive tests). Those inserts
-- violated the constraint, threw, and were swallowed by client-side
-- try/catch — so full Luna sessions and every adaptive test were silently
-- never recorded, starving Luna's memory/personalization of its richest
-- signals.
--
-- Widen the allowed set to match what the client actually writes. Existing
-- valid values are preserved; no data backfill is needed because the
-- rejected rows were never inserted in the first place.

ALTER TABLE public.learning_history
  DROP CONSTRAINT IF EXISTS learning_history_session_type_check;

ALTER TABLE public.learning_history
  ADD CONSTRAINT learning_history_session_type_check
  CHECK (session_type IN (
    'chat',
    'luna-session',
    'battle',
    'test',
    'adaptive_test',
    'course'
  ));
