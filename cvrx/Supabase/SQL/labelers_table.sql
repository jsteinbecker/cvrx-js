-- Run this in Supabase SQL editor before syncing labelers from the app.

create table if not exists public.labelers (
    name text primary key,
    full_name text not null,
    labeler_codes text[] not null default '{}',
    hidden boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint labelers_name_not_blank check (btrim(name) <> ''),
    constraint labelers_full_name_not_blank check (btrim(full_name) <> ''),
    constraint labelers_codes_not_empty check (cardinality(labeler_codes) > 0)
);

create index if not exists labelers_labeler_codes_idx
on public.labelers using gin (labeler_codes);

alter table public.labelers enable row level security;

create policy "Authenticated users can read labelers"
on public.labelers
for select
to authenticated
using (true);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists labelers_set_updated_at on public.labelers;
create trigger labelers_set_updated_at
before update on public.labelers
for each row
execute function public.set_updated_at();

