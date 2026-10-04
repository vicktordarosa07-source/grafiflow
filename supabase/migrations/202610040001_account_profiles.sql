alter table public.profiles
  add column if not exists cpf text not null default '',
  add column if not exists phone text not null default '',
  add column if not exists postal_code text not null default '',
  add column if not exists street text not null default '',
  add column if not exists address_number text not null default '',
  add column if not exists address_complement text not null default '',
  add column if not exists neighborhood text not null default '',
  add column if not exists city text not null default '',
  add column if not exists state text not null default '',
  add column if not exists quote_business_name text not null default '',
  add column if not exists quote_business_phone text not null default '',
  add column if not exists quote_business_email text not null default '',
  add column if not exists quote_document text not null default '',
  add column if not exists quote_address text not null default '';

comment on column public.profiles.cpf is 'Dado pessoal do titular; protegido pelas políticas RLS de proprietário do perfil.';
comment on column public.profiles.quote_document is 'Documento que o usuário escolhe exibir nos orçamentos.';
comment on column public.profiles.quote_address is 'Endereço comercial que o usuário escolhe exibir nos orçamentos.';

