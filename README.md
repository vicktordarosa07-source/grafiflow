# GrafiFlow

Aplicativo web progressivo para orçamento e aproveitamento de bobinas e chapas. A aplicação continua funcionando offline no Windows e no Android; os dados locais são mantidos no IndexedDB e podem ser exportados em backup.

## Stack

- **GitHub:** versionamento do código-fonte.
- **Vercel:** publicação do app estático/PWA.
- **Supabase:** autenticação por e-mail, espaços de trabalho, sincronização entre dispositivos, RLS e estrutura inicial de assinaturas.

O núcleo de cálculo não depende de conexão. A nuvem é uma camada opcional: quando o usuário entra e há internet, o GrafiFlow sincroniza rascunho, catálogo e orçamentos; alterações offline entram em uma fila local e são enviadas ao reconectar. O IndexedDB também separa os espaços locais por conta; ao sair, o espaço daquela conta deixa de aparecer no modo local anônimo e seus dados continuam no dispositivo para quando o titular entrar novamente.

## Publicação na Vercel

1. Configure no projeto Vercel as variáveis `GRAFIFLOW_SUPABASE_URL` e `GRAFIFLOW_SUPABASE_ANON_KEY`. Para ativar a verificação antirobô, configure também `GRAFIFLOW_SUPABASE_CAPTCHA_SITE_KEY`.
2. Use `npm run build` como comando de build e `build` como diretório de saída (já definido em `vercel.json`).
3. A chave `anon` do Supabase é uma chave pública para uso no navegador. **Nunca configure `service_role` no front-end ou na Vercel como variável exposta ao cliente.** As regras RLS protegem os dados.

Sem as duas variáveis, o app é publicado e funciona localmente, mas a conta e a sincronização em nuvem ficam desativadas.

## Supabase

Aplique, nesta ordem, `supabase/migrations/202610030001_grafiflow_core.sql`, `supabase/migrations/202610040001_account_profiles.sql`, `supabase/migrations/202610060001_sync_conflict_versions.sql` e `supabase/migrations/202610070001_incremental_sync_catalog_types.sql` no projeto Supabase. A primeira migração cria um perfil e um espaço de trabalho próprio para cada usuário, além das políticas RLS que impedem uma conta de ler ou gravar dados de outro espaço; a segunda adiciona os dados de cadastro e preenchimento de orçamento ao perfil privado do titular; a terceira usa versões geradas pelo servidor para rejeitar gravações baseadas em uma versão remota antiga; a quarta cria um cursor incremental seguro para a sincronização, separa acabamentos, insumos, mão de obra e extras em tipos próprios e migra os itens existentes. Sem a quarta migração, o app mantém compatibilidade com o formato antigo e continua fazendo a carga completa dos registros.

O PWA busca apenas registros alterados desde o último cursor do espaço de trabalho. A carga inicial continua trazendo todos os registros, em páginas; exclusões permanecem como marcadores para que também sejam propagadas. O cursor usa sequência gerada pelo banco e gravações do mesmo espaço são serializadas para não pular alterações concorrentes.

Configure `https://grafiflow.vercel.app` como Site URL e permita essa origem nas Redirect URLs. Em Auth > Providers > Email, mantenha a confirmação de e-mail ativada; o app não salva a sessão de um cadastro que já venha autenticado e informa quando o projeto Supabase não está exigindo confirmação. Em Auth > Email Templates, use `{{ .ConfirmationURL }}` como destino de um botão “Confirmar cadastro” no modelo Confirm Signup e um botão “Redefinir senha” no modelo Reset Password. Para entrega confiável de mensagens a usuários reais, configure SMTP próprio em Auth > SMTP Settings; o envio padrão do Supabase é restrito e não é adequado para produção.

### Segurança de contas

- O formulário exige nome completo, e-mail válido, senha e repetição da senha. Novas senhas precisam ter ao menos 12 caracteres; configure o mesmo mínimo em Auth > Providers > Email para que a regra também seja aplicada no servidor.
- O Supabase Auth guarda as senhas com hash e limita tentativas de autenticação. Ative a proteção contra senhas vazadas quando disponível no plano do projeto.
- Cada cadastro recebe um espaço próprio. As políticas RLS e as funções do banco autorizam a sincronização somente para membros desse espaço. A chave `service_role` nunca deve ser usada no navegador.
- O projeto já publica cabeçalhos de segurança, incluindo CSP, proteção contra iframe, HSTS, `nosniff` e política de referência.
- A aplicação aceita Cloudflare Turnstile nos fluxos de cadastro, entrada e recuperação de senha. Para ativá-lo, crie um widget Turnstile, configure a chave pública em `GRAFIFLOW_SUPABASE_CAPTCHA_SITE_KEY` na Vercel e coloque a chave secreta somente em Supabase > Auth > Bot and Abuse Protection. Nunca coloque a chave secreta no GitHub, na Vercel como variável de cliente ou no navegador.

As proteções do navegador complementam as validações do servidor. Antes de abrir inscrições ao público, confirme as opções de Auth, teste o envio de e-mails com SMTP próprio e execute o Security Advisor do projeto Supabase.

Ao informar um CEP completo em Minha conta, o GrafiFlow consulta o ViaCEP e sugere rua, bairro, cidade e UF. Só o CEP é enviado ao serviço; número e complemento continuam sendo preenchidos pelo usuário, e os demais campos podem ser editados.

## Configuração inicial das plataformas

1. No Supabase, aplique as migrações indicadas e configure confirmação de e-mail, senha, URL de redirecionamento e SMTP.
2. Na Vercel, mantenha `npm run build` e a pasta `build` como saída.
3. Nas variáveis de ambiente da Vercel, defina `GRAFIFLOW_SUPABASE_URL` e `GRAFIFLOW_SUPABASE_ANON_KEY`; adicione a chave pública do Turnstile se a proteção antirobô estiver habilitada no Supabase.
4. Publique novamente e teste cadastro, confirmação, login, recuperação de senha, isolamento entre duas contas, sincronização entre dispositivos e uso offline.

Os dados locais do site antigo pertencem à origem antiga do navegador. Exporte um backup nele e importe no novo GrafiFlow para levar catálogo e orçamentos; a primeira sincronização enviará os dados importados à conta conectada.

## Assinaturas

A migração prepara a tabela de assinaturas e o isolamento por espaço de trabalho, mas ainda não configura planos, checkout, cobrança recorrente, webhooks do provedor nem bloqueio de recursos por plano. Esses passos dependem da escolha do provedor e dos preços; não há cobrança ativa neste pacote.

## Desenvolvimento local

```sh
npm run build
npm run preview
```

Para testar sincronização, defina as variáveis do Supabase antes do build. Para testar somente o cálculo/offline, elas podem ficar vazias. O CAPTCHA é opcional no build, mas sua chave pública precisa estar presente se a proteção correspondente estiver ativa no Supabase.
