export const MIN_PASSWORD_LENGTH = 12;

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function validateRegistration({ fullName, email, password, confirmation }) {
  const normalizedName = String(fullName || '').trim().replace(/\s+/g, ' ');
  const normalizedEmail = String(email || '').trim().toLowerCase();
  const nameParts = normalizedName.split(' ').filter(Boolean);

  if (normalizedName.length > 160 || nameParts.length < 2) {
    return { ok: false, message: 'Informe seu nome e sobrenome.' };
  }
  if (normalizedEmail.length > 254 || !EMAIL_PATTERN.test(normalizedEmail)) {
    return { ok: false, message: 'Digite um endereço de e-mail válido.' };
  }
  if (String(password || '').length < MIN_PASSWORD_LENGTH) {
    return { ok: false, message: `A senha precisa ter pelo menos ${MIN_PASSWORD_LENGTH} caracteres.` };
  }
  if (String(password || '').length > 128) {
    return { ok: false, message: 'A senha ultrapassou o tamanho máximo permitido.' };
  }
  if (password !== confirmation) {
    return { ok: false, message: 'As senhas não coincidem.' };
  }

  return { ok: true, fullName: normalizedName, email: normalizedEmail };
}

export function captchaSecurityMetadata(token) {
  return token ? { gotrue_meta_security: { captcha_token: token } } : {};
}

export function localDatabaseForAccount({ baseName, activeOwnerId = '', primaryOwnerId = '', sessionOwnerId = '' }) {
  const ownerId = String(sessionOwnerId || activeOwnerId || '').trim();
  const primaryId = String(primaryOwnerId || '').trim();
  if (!ownerId) return primaryId ? `${baseName}:guest` : baseName;
  if (!primaryId || ownerId === primaryId) return baseName;
  return `${baseName}:user:${encodeURIComponent(ownerId)}`;
}

export function userFacingAuthError(error, action = 'login') {
  const message = `${error?.message || error || ''} ${error?.code || ''}`.toLowerCase();
  if (/email not confirmed|email_not_confirmed|email.*not.*confirm/.test(message)) {
    return 'Confirme seu e-mail antes de entrar. Se não encontrar a mensagem, toque em “Reenviar confirmação”.';
  }
  if (/captcha|turnstile|hcaptcha|anti.?rob[oô]|verifica[cç][aã]o de seguran[cç]a/.test(message)) {
    return 'Não foi possível validar a verificação antirobô. Confira o desafio e tente novamente.';
  }
  if (/rate.?limit|too many requests|too many attempts|over_email_send_rate_limit/.test(message)) {
    return 'Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.';
  }
  if (/weak.?password|password.*(minimum|least|character|strength)/.test(message)) {
    return `Escolha uma senha com pelo menos ${MIN_PASSWORD_LENGTH} caracteres.`;
  }
  if (/user already registered|already registered|user already exists|email already exists/.test(message)) {
    return 'Não foi possível criar a conta com esse endereço. Tente entrar ou recuperar a senha.';
  }
  if (/invalid login credentials|invalid credentials|invalid email or password/.test(message)) {
    return 'E-mail ou senha incorretos.';
  }
  if (/failed to fetch|network|load failed|offline|timed out/.test(message)) {
    return 'Não foi possível conectar. Verifique a internet e tente novamente.';
  }
  if (action === 'recovery' || action === 'resend') {
    return 'Se houver uma conta que precise dessa mensagem, enviaremos as instruções para o e-mail informado.';
  }
  if (action === 'signup') return 'Não foi possível concluir o cadastro. Confira os dados e tente novamente.';
  return 'Não foi possível concluir o acesso. Confira os dados e tente novamente.';
}
