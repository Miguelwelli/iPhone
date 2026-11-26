-- Tabela principal de jogos da NEXUS STORE (consumida pelo NEXUS ADMIN e pelo app do PS4)
create table if not exists public.games (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    cover_url text not null,
    banner_url text,
    description text not null,
    category text not null,
    platform text not null default 'PS4',
    size text not null,
    download_url text not null,
    published boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.games enable row level security;

-- Leitura pública apenas de jogos publicados (para o catálogo do PS4)
create policy "Public read published games"
on public.games for select
using (published = true);

-- Escrita autenticada para administradores
create policy "Authenticated insert games"
on public.games for insert
to authenticated
with check (true);

create policy "Authenticated update games"
on public.games for update
to authenticated
using (true);

create policy "Authenticated delete games"
on public.games for delete
to authenticated
using (true);

-- Buckets de armazenamento para capas e banners
insert into storage.buckets (id, name, public)
values ('covers', 'covers', true), ('banners', 'banners', true)
on conflict (id) do nothing;
