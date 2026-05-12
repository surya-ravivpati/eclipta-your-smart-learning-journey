DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.user_profiles;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;
ALTER TABLE public.user_profiles REPLICA IDENTITY FULL;