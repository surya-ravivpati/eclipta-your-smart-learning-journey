-- Four Ecliptars per archetype (was two). Widen the claim_ecliptar allowlist
-- to accept the new -c/-d slugs and the two extra God-class creatures. The
-- function body is otherwise unchanged; claimArchetypeReward still grants every
-- not-yet-owned Ecliptar for an archetype from its monster node, so existing
-- players can re-open the node to collect the new c/d slots.

CREATE OR REPLACE FUNCTION public.claim_ecliptar(
  p_slug text,
  p_archetype text,
  p_name text,
  p_node_id integer
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_allowed text[] := ARRAY[
    'speedster-a','speedster-b','speedster-c','speedster-d',
    'tank-a','tank-b','tank-c','tank-d',
    'chud-a','chud-b','chud-c','chud-d',
    'gambler-a','gambler-b','gambler-c','gambler-d',
    'healer-a','healer-b','healer-c','healer-d',
    'fulcrum-a','fulcrum-b','fulcrum-c','fulcrum-d',
    'accelerator-a','accelerator-b','accelerator-c','accelerator-d',
    'god-a','god-b','newton','ecliptadon','einsteinium','temporobys'
  ];
  v_exists boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_slug IS NULL OR NOT (p_slug = ANY (v_allowed)) THEN
    RAISE EXCEPTION 'Unknown ecliptar slug: %', p_slug;
  END IF;
  IF p_archetype IS NULL OR length(p_archetype) < 2 OR length(p_archetype) > 40 THEN
    RAISE EXCEPTION 'Invalid archetype';
  END IF;
  IF p_node_id IS NULL OR p_node_id < 0 OR p_node_id > 1000 THEN
    RAISE EXCEPTION 'Invalid node';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.user_ecliptars WHERE user_id = v_uid AND ecliptar_slug = p_slug
  ) INTO v_exists;
  IF v_exists THEN
    RETURN jsonb_build_object('already_claimed', true, 'slug', p_slug);
  END IF;

  INSERT INTO public.user_ecliptars(user_id, archetype, ecliptar_slug, ecliptar_name, node_id)
  VALUES (v_uid, p_archetype, p_slug, COALESCE(NULLIF(trim(p_name), ''), p_slug), p_node_id);

  RETURN jsonb_build_object('already_claimed', false, 'slug', p_slug);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_ecliptar(text, text, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_ecliptar(text, text, text, integer) TO authenticated;
