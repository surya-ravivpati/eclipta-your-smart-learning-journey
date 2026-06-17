-- claim_ecliptar previously validated p_slug against a hardcoded allowlist, so
-- every new Ecliptar (c/d slots, god creatures) required another migration —
-- and a missed migration meant "Unknown ecliptar slug" on claim. Validate by
-- SHAPE instead: "<archetype>-<a..d>" or one of the named God creatures. This
-- covers the full 4-per-archetype roster and any future archetype with no
-- further migrations.

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
  v_exists boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_slug IS NULL OR NOT (
       p_slug ~ '^[a-z]+-[a-d]$'
       OR p_slug IN ('newton', 'ecliptadon', 'einsteinium', 'temporobys')
     ) THEN
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
