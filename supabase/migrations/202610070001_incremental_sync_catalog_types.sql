create sequence if not exists public.grafiflow_records_change_seq as bigint;

alter table public.grafiflow_records
  add column if not exists change_seq bigint;

alter table public.grafiflow_records
  alter column change_seq set default nextval('public.grafiflow_records_change_seq');

update public.grafiflow_records
set change_seq = nextval('public.grafiflow_records_change_seq')
where change_seq is null;

alter table public.grafiflow_records
  alter column change_seq set not null;

create unique index if not exists grafiflow_records_change_seq_idx
  on public.grafiflow_records(change_seq);

create index if not exists grafiflow_records_workspace_change_seq_idx
  on public.grafiflow_records(workspace_id, change_seq);

create or replace function public.bump_grafiflow_record_change_seq()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.change_seq := nextval('public.grafiflow_records_change_seq');
  return new;
end;
$$;

drop trigger if exists bump_grafiflow_record_change_seq on public.grafiflow_records;
create trigger bump_grafiflow_record_change_seq
  before update on public.grafiflow_records
  for each row execute function public.bump_grafiflow_record_change_seq();

alter table public.grafiflow_records
  drop constraint if exists grafiflow_records_record_type_check;

alter table public.grafiflow_records
  add constraint grafiflow_records_record_type_check
  check (record_type in (
    'draft', 'material', 'quote',
    'catalog_finish', 'catalog_supply', 'catalog_labor', 'catalog_extra'
  ));

insert into public.grafiflow_records as current_record
  (workspace_id, record_type, record_id, payload, is_deleted, updated_at)
select
  workspace_id,
  case payload ->> 'catalogCategory'
    when 'finish' then 'catalog_finish'
    when 'supply' then 'catalog_supply'
    when 'labor' then 'catalog_labor'
    when 'extra' then 'catalog_extra'
  end,
  record_id,
  payload,
  is_deleted,
  updated_at
from public.grafiflow_records
where record_type = 'material'
  and not is_deleted
  and payload ->> 'catalogCategory' in ('finish', 'supply', 'labor', 'extra')
on conflict (workspace_id, record_type, record_id) do update
  set payload = excluded.payload,
      is_deleted = excluded.is_deleted,
      updated_at = excluded.updated_at
  where current_record.updated_at < excluded.updated_at;

update public.grafiflow_records
set payload = null,
    is_deleted = true,
    updated_at = clock_timestamp()
where record_type = 'material'
  and not is_deleted
  and payload ->> 'catalogCategory' in ('finish', 'supply', 'labor', 'extra');

create or replace function public.sync_grafiflow_records(target_workspace_id uuid, changes jsonb)
returns setof public.grafiflow_records
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  item jsonb;
  item_type text;
  item_id text;
  item_time timestamptz;
  item_base_updated_at timestamptz;
  item_has_base boolean;
  item_deleted boolean;
  item_payload jsonb;
  server_time timestamptz;
  item_rows_changed integer;
begin
  if auth.uid() is null or not public.is_grafiflow_workspace_member(target_workspace_id) then
    raise exception 'workspace access denied' using errcode = '42501';
  end if;
  perform workspace_row.id
  from public.workspaces workspace_row
  where workspace_row.id = target_workspace_id
  for update;
  if changes is null or jsonb_typeof(changes) <> 'array' then
    raise exception 'changes must be a JSON array' using errcode = '22023';
  end if;

  for item in select value from jsonb_array_elements(changes)
  loop
    item_type := item ->> 'record_type';
    item_id := item ->> 'record_id';
    item_time := coalesce(nullif(item ->> 'updated_at', '')::timestamptz, now());
    item_has_base := item -> 'base_updated_at' is not null;
    item_base_updated_at := nullif(item ->> 'base_updated_at', '')::timestamptz;
    item_deleted := coalesce((item ->> 'is_deleted')::boolean, false);
    item_payload := case when item_deleted then null else item -> 'payload' end;
    server_time := clock_timestamp();

    if item_type is null
      or item_type not in ('draft', 'material', 'quote', 'catalog_finish', 'catalog_supply', 'catalog_labor', 'catalog_extra')
      or item_id is null
      or char_length(item_id) > 200
      or (not item_deleted and item_payload is null)
      or (not item_deleted and item_type = 'catalog_finish' and item_payload ->> 'catalogCategory' is distinct from 'finish')
      or (not item_deleted and item_type = 'catalog_supply' and item_payload ->> 'catalogCategory' is distinct from 'supply')
      or (not item_deleted and item_type = 'catalog_labor' and item_payload ->> 'catalogCategory' is distinct from 'labor')
      or (not item_deleted and item_type = 'catalog_extra' and item_payload ->> 'catalogCategory' is distinct from 'extra')
    then
      raise exception 'invalid GrafiFlow record' using errcode = '22023';
    end if;

    insert into public.grafiflow_records (workspace_id, record_type, record_id, payload, is_deleted, updated_at)
    values (target_workspace_id, item_type, item_id, item_payload, item_deleted, server_time)
    on conflict (workspace_id, record_type, record_id) do update
      set payload = excluded.payload,
          is_deleted = excluded.is_deleted,
          updated_at = excluded.updated_at
      where case
        when item_has_base and item_base_updated_at is not null then
          public.grafiflow_records.updated_at = item_base_updated_at
        when item_has_base then
          public.grafiflow_records.is_deleted = excluded.is_deleted
          and (public.grafiflow_records.payload - '_syncUpdatedAt' - '_cloudVersionAt' - 'updatedAt')
            is not distinct from (excluded.payload - '_syncUpdatedAt' - '_cloudVersionAt' - 'updatedAt')
        else public.grafiflow_records.updated_at < excluded.updated_at
      end;
    get diagnostics item_rows_changed = row_count;

    if item_rows_changed > 0 and item_type = 'material' and item_deleted then
      update public.grafiflow_records
      set payload = null,
          is_deleted = true,
          updated_at = clock_timestamp()
      where workspace_id = target_workspace_id
        and record_id = item_id
        and record_type in ('catalog_finish', 'catalog_supply', 'catalog_labor', 'catalog_extra')
        and not is_deleted;
    end if;
  end loop;

  return query
    select record_row.*
    from public.grafiflow_records record_row
    where record_row.workspace_id = target_workspace_id
      and exists (
        select 1
        from jsonb_array_elements(changes) changed
        where changed ->> 'record_type' = record_row.record_type
          and changed ->> 'record_id' = record_row.record_id
      )
    order by record_row.record_type, record_row.record_id;
end;
$$;

revoke all on function public.sync_grafiflow_records(uuid, jsonb) from public, anon;
grant execute on function public.sync_grafiflow_records(uuid, jsonb) to authenticated;

create or replace function public.list_grafiflow_records(
  target_workspace_id uuid,
  after_change_seq bigint default 0,
  page_size integer default 500
)
returns setof public.grafiflow_records
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_grafiflow_workspace_member(target_workspace_id) then
    raise exception 'workspace access denied' using errcode = '42501';
  end if;
  if coalesce(after_change_seq, 0) < 0 or page_size is null or page_size < 1 or page_size > 1000 then
    raise exception 'invalid change cursor or page size' using errcode = '22023';
  end if;

  return query
    select record_row.*
    from public.grafiflow_records record_row
    where record_row.workspace_id = target_workspace_id
      and record_row.change_seq > coalesce(after_change_seq, 0)
    order by record_row.change_seq
    limit page_size;
end;
$$;

revoke all on function public.list_grafiflow_records(uuid, bigint, integer) from public, anon;
grant execute on function public.list_grafiflow_records(uuid, bigint, integer) to authenticated;
