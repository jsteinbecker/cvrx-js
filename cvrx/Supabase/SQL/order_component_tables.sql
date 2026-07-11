-- Run this in Supabase SQL editor after the base facility/order/profile tables exist.
-- This replaces the older products/order_components shape with:
-- rxcui_concepts -> ordered_components -> utilized_lots, with NDC products linked to concepts.

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create table if not exists public.rxcui_concepts (
    id uuid primary key default gen_random_uuid(),
    facility_id uuid not null references public.facilities(id) on delete cascade,
    name text not null,
    rxcui text,
    tty text,
    imported_at timestamptz,
    strength double precision not null,
    strength_unit text not null,
    ml_concentration double precision,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint rxcui_concepts_name_not_blank check (btrim(name) <> ''),
    constraint rxcui_concepts_strength_positive check (strength > 0),
    constraint rxcui_concepts_ml_concentration_positive check (ml_concentration is null or ml_concentration > 0)
);

create index if not exists rxcui_concepts_facility_idx
on public.rxcui_concepts (facility_id);

create unique index if not exists rxcui_concepts_facility_id_idx
on public.rxcui_concepts (facility_id, id);

create unique index if not exists rxcui_concepts_facility_rxcui_tty_idx
on public.rxcui_concepts (facility_id, rxcui, tty)
where rxcui is not null and tty is not null;

create table if not exists public.ndc_products (
    facility_id uuid not null references public.facilities(id) on delete cascade,
    ndc text not null,
    labeler_code text,
    product_code text,
    package_code text,
    name text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (facility_id, ndc),
    constraint ndc_products_ndc_not_blank check (btrim(ndc) <> '')
);

create index if not exists ndc_products_facility_idx
on public.ndc_products (facility_id);

create table if not exists public.rxcui_concept_ndc_products (
    facility_id uuid not null references public.facilities(id) on delete cascade,
    concept_id uuid not null,
    ndc text not null,
    created_at timestamptz not null default now(),
    primary key (facility_id, concept_id, ndc),
    foreign key (facility_id, concept_id) references public.rxcui_concepts(facility_id, id) on delete cascade,
    foreign key (facility_id, ndc) references public.ndc_products(facility_id, ndc) on delete cascade
);

create index if not exists rxcui_concept_ndc_products_ndc_idx
on public.rxcui_concept_ndc_products (facility_id, ndc);

create table if not exists public.ordered_components (
    id uuid primary key default gen_random_uuid(),
    facility_id uuid not null references public.facilities(id) on delete cascade,
    order_id uuid not null references public.orders(id) on delete cascade,
    concept_id uuid not null,
    total_quantity double precision not null,
    quantity_unit text not null,
    is_unexpected boolean not null default false,
    unexpected_barcode_value text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint ordered_components_total_quantity_positive check (total_quantity > 0),
    foreign key (facility_id, concept_id) references public.rxcui_concepts(facility_id, id)
);

create index if not exists ordered_components_order_idx
on public.ordered_components (order_id);

create unique index if not exists ordered_components_facility_id_idx
on public.ordered_components (facility_id, id);

create index if not exists ordered_components_concept_idx
on public.ordered_components (concept_id);

create table if not exists public.utilized_lots (
    id uuid primary key default gen_random_uuid(),
    facility_id uuid not null references public.facilities(id) on delete cascade,
    component_id uuid not null,
    barcode_value text,
    lot text not null,
    expiration date,
    mfg text,
    strength_quantity double precision not null,
    photo_bucket_id uuid,
    scanned_by uuid references public.profiles(id),
    scanned_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint utilized_lots_lot_not_blank check (btrim(lot) <> ''),
    constraint utilized_lots_strength_quantity_positive check (strength_quantity > 0),
    foreign key (facility_id, component_id) references public.ordered_components(facility_id, id) on delete cascade
);

create index if not exists utilized_lots_component_idx
on public.utilized_lots (component_id);

create index if not exists utilized_lots_facility_idx
on public.utilized_lots (facility_id);

drop trigger if exists rxcui_concepts_set_updated_at on public.rxcui_concepts;
create trigger rxcui_concepts_set_updated_at
before update on public.rxcui_concepts
for each row
execute function public.set_updated_at();

drop trigger if exists ndc_products_set_updated_at on public.ndc_products;
create trigger ndc_products_set_updated_at
before update on public.ndc_products
for each row
execute function public.set_updated_at();

drop trigger if exists ordered_components_set_updated_at on public.ordered_components;
create trigger ordered_components_set_updated_at
before update on public.ordered_components
for each row
execute function public.set_updated_at();

drop trigger if exists utilized_lots_set_updated_at on public.utilized_lots;
create trigger utilized_lots_set_updated_at
before update on public.utilized_lots
for each row
execute function public.set_updated_at();

alter table public.rxcui_concepts enable row level security;
alter table public.ndc_products enable row level security;
alter table public.rxcui_concept_ndc_products enable row level security;
alter table public.ordered_components enable row level security;
alter table public.utilized_lots enable row level security;

create or replace function public.user_has_facility_access(target_facility_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.facility_memberships membership
        join public.profiles profile on profile.id = membership.user_id
        where membership.facility_id = target_facility_id
          and membership.user_id = auth.uid()
          and profile.active = true
    );
$$;

create policy "Authenticated facility users can read rxcui concepts"
on public.rxcui_concepts
for select
to authenticated
using (public.user_has_facility_access(facility_id));

create policy "Authenticated facility users can write rxcui concepts"
on public.rxcui_concepts
for all
to authenticated
using (public.user_has_facility_access(facility_id))
with check (public.user_has_facility_access(facility_id));

create policy "Authenticated facility users can read ndc products"
on public.ndc_products
for select
to authenticated
using (public.user_has_facility_access(facility_id));

create policy "Authenticated facility users can write ndc products"
on public.ndc_products
for all
to authenticated
using (public.user_has_facility_access(facility_id))
with check (public.user_has_facility_access(facility_id));

create policy "Authenticated facility users can read concept ndc links"
on public.rxcui_concept_ndc_products
for select
to authenticated
using (public.user_has_facility_access(facility_id));

create policy "Authenticated facility users can write concept ndc links"
on public.rxcui_concept_ndc_products
for all
to authenticated
using (public.user_has_facility_access(facility_id))
with check (public.user_has_facility_access(facility_id));

create policy "Authenticated facility users can read ordered components"
on public.ordered_components
for select
to authenticated
using (public.user_has_facility_access(facility_id));

create policy "Authenticated facility users can write ordered components"
on public.ordered_components
for all
to authenticated
using (public.user_has_facility_access(facility_id))
with check (public.user_has_facility_access(facility_id));

create policy "Authenticated facility users can read utilized lots"
on public.utilized_lots
for select
to authenticated
using (public.user_has_facility_access(facility_id));

create policy "Authenticated facility users can write utilized lots"
on public.utilized_lots
for all
to authenticated
using (public.user_has_facility_access(facility_id))
with check (public.user_has_facility_access(facility_id));
