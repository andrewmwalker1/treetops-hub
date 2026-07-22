-- Tree Tops Hub — info-pdfs storage bucket setup
-- Fixes: "Upload failed (403): new row violates row-level security policy"
-- when uploading a PDF guide from Admin -> Info.
--
-- Root cause: marking a Storage bucket "Public" in the Supabase dashboard
-- only allows anonymous READS of files in it. It does NOT grant the anon
-- key permission to upload (INSERT) new files — that's a separate Row
-- Level Security policy on the storage.objects table, which was never
-- created for this bucket.
--
-- Safe to run even if the bucket/policies already exist — every step is
-- idempotent, matching the style of 01-app-data-baseline.sql.

-- 1. Make sure the bucket exists and is public (readable without auth).
insert into storage.buckets (id, name, public)
values ('info-pdfs', 'info-pdfs', true)
on conflict (id) do update set public = true;

-- 2. Row Level Security on storage.objects — allow the app's anon key to
--    read and upload PDFs in this bucket specifically (not any bucket).
--    This matches how app_data already works: no user auth in this app,
--    so access control is "anyone with the public anon key," same as
--    every other write path here.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'info_pdfs_select_anon'
  ) then
    create policy info_pdfs_select_anon on storage.objects
      for select using (bucket_id = 'info-pdfs');
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'info_pdfs_insert_anon'
  ) then
    create policy info_pdfs_insert_anon on storage.objects
      for insert with check (bucket_id = 'info-pdfs');
  end if;
end $$;
