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
begin
  if auth.uid() is null or not public.is_grafiflow_workspace_member(target_workspace_id) then
    raise exception 'workspace access denied' using errcode = '42501';
  end if;
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

    if item_type is null or item_type not in ('draft', 'material', 'quote') or item_id is null or char_length(item_id) > 200 or (not item_deleted and item_payload is null) then
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
