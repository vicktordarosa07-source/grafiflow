import test from 'node:test';
import assert from 'node:assert/strict';
import { captchaSecurityMetadata, localDatabaseForAccount, MIN_PASSWORD_LENGTH, userFacingAuthError, validateRegistration } from '../dist/auth-flow.js';

test('registration requires a full name, valid email, long password, and matching confirmation', () => {
  assert.equal(validateRegistration({ fullName: '', email: 'a@example.com', password: 'a'.repeat(12), confirmation: 'a'.repeat(12) }).ok, false);
  assert.equal(validateRegistration({ fullName: 'Helder', email: 'a@example.com', password: 'a'.repeat(12), confirmation: 'a'.repeat(12) }).ok, false);
  assert.equal(validateRegistration({ fullName: 'Helder Rosa', email: 'invalid', password: 'a'.repeat(12), confirmation: 'a'.repeat(12) }).ok, false);
  assert.equal(validateRegistration({ fullName: 'Helder Rosa', email: 'a@example.com', password: 'short', confirmation: 'short' }).ok, false);
  assert.equal(validateRegistration({ fullName: 'Helder Rosa', email: 'a@example.com', password: 'a'.repeat(129), confirmation: 'a'.repeat(129) }).ok, false);
  assert.equal(validateRegistration({ fullName: 'Helder Rosa', email: 'a@example.com', password: 'a'.repeat(12), confirmation: 'b'.repeat(12) }).ok, false);
});

test('registration normalizes name and email without changing password contents', () => {
  const password = '  phrase is private  ';
  const result = validateRegistration({
    fullName: '  Helder   Pedro da Rosa  ',
    email: '  HELDER@EXAMPLE.COM ',
    password,
    confirmation: password,
  });
  assert.deepEqual(result, { ok: true, fullName: 'Helder Pedro da Rosa', email: 'helder@example.com' });
});

test('password rule matches the policy shown in the form', () => {
  assert.equal(MIN_PASSWORD_LENGTH, 12);
});

test('CAPTCHA token uses Supabase Auth security metadata format', () => {
  assert.deepEqual(captchaSecurityMetadata('turnstile-token'), {
    gotrue_meta_security: { captcha_token: 'turnstile-token' },
  });
  assert.deepEqual(captchaSecurityMetadata(''), {});
});

test('offline database partitions account data while preserving the first account database', () => {
  const baseName = 'grafiflow-local-v1';
  assert.equal(localDatabaseForAccount({ baseName }), baseName);
  assert.equal(localDatabaseForAccount({ baseName, activeOwnerId: 'user-a', primaryOwnerId: 'user-a' }), baseName);
  assert.equal(localDatabaseForAccount({ baseName, primaryOwnerId: 'user-a' }), `${baseName}:guest`);
  assert.notEqual(
    localDatabaseForAccount({ baseName, activeOwnerId: 'user-a', primaryOwnerId: 'user-a' }),
    localDatabaseForAccount({ baseName, activeOwnerId: 'user-b', primaryOwnerId: 'user-a' }),
  );
  assert.equal(
    localDatabaseForAccount({ baseName, activeOwnerId: 'user-a', primaryOwnerId: 'user-a', sessionOwnerId: 'user-b' }),
    `${baseName}:user:user-b`,
  );
});

test('authentication errors do not expose server details or reveal registered emails', () => {
  assert.equal(userFacingAuthError(new Error('User already registered'), 'signup'), 'Não foi possível criar a conta com esse endereço. Tente entrar ou recuperar a senha.');
  assert.equal(userFacingAuthError(new Error('Invalid login credentials')), 'E-mail ou senha incorretos.');
  assert.equal(userFacingAuthError(new Error('provider internal diagnostic')), 'Não foi possível concluir o acesso. Confira os dados e tente novamente.');
  assert.match(userFacingAuthError(new Error('email not confirmed')), /Confirme seu e-mail/);
  assert.match(userFacingAuthError(new Error('captcha verification failed')), /verificação antirobô/);
  assert.match(userFacingAuthError(new Error('over_email_send_rate_limit')), /Aguarde alguns minutos/);
});
